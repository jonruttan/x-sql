; # x-sql -- SQL on x-lang
;
; ## sql/my.x -- MySQL's wire protocol, the client's end
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The protocol MySQL and MariaDB share (MySQL's "Client/Server Protocol",
; version 10 of the handshake, protocol 4.1 of the rest): the handshake,
; sign-in by mysql_native_password, by caching_sha2_password where the
; server has the password cached, and in the clear when the server asks
; for that, and COM_QUERY, whose results come as text.  TLS is asked for
; after the server's handshake, with a short answer that says so, and the
; full answer then goes through it.
;
; It speaks over a SqlLink (sql/link).  A packet is a three-byte length,
; least byte first, a sequence number, and a payload.  Integers in a
; payload are least byte first, and one that is "length-encoded" is a byte
; under 251, or a byte that says how many bytes follow.
;
; A query answers a list with an entry for each statement the server ran:
;   (NAMES TYPES RIGHTS ROWS TAG)   NAMES the columns, TYPES their types'
;       names, RIGHTS whether each is a number, ROWS lists of
;       (TEXT . NULL) cells, and TAG nil; or, for a statement that answers
;       no rows, all four nil and TAG what the mysql client says of it,
;       "Query OK, 2 rows affected"

(module sql/my)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/num/tower)
(import x/codec/bytes)
(import x/codec/sha1)
(import x/codec/sha256)
(import sql/link sql-link-text)

; --- bytes -------------------------------------------------------------------

(def %my-nul (Bytes of-list (list 0)))

; The integer of N bytes of REGION from AT, least byte first
(def %my-uint
  (fn (_ region at n)
    ((fn (self i acc)
       (if (< i 0) acc
         (self (- i 1) (+ (* acc 256) (Bytes ref region (+ at i))))))
     (- n 1) 0)))

; N as COUNT bytes, least first
(def %my-put-uint
  (fn (self w n count)
    (when (> count 0)
      (Bytes put-u8 w (Num remainder n 256))
      (self w (Num quotient n 256) (- count 1)))))

; The text of REGION from AT to the NUL that ends it, and where the next
; thing starts: (TEXT . NEXT)
(def %my-cstring
  (fn (_ region at)
    (let ((n (Bytes find (Bytes sub region at (- (Bytes length region) at)) %my-nul)))
      (when (null? n) (error "Protocol Error: a string with no end in a server packet"))
      (pair (sql-link-text (Bytes sub region at n)) (+ at n 1)))))

; The first bytes of a length-encoded integer that say more bytes follow,
; and how many; 251 alone is a NULL in a row
(def %my-length-null 251)
(def %my-length-wider (list (pair 252 2) (pair 253 3) (pair 254 8)))

; A length-encoded integer at AT: (N . NEXT), N nil for the NULL byte
(def %my-length
  (fn (_ region at)
    (let ((b (Bytes ref region at)))
      (match
        ((< b %my-length-null) (pair b (+ at 1)))
        ((= b %my-length-null) (pair () (+ at 1)))
        (#t
          (let ((count (rest (List find (fn (_ w) (= (first w) b)) %my-length-wider))))
            (pair (%my-uint region (+ at 1) count) (+ at 1 count))))))))

; A length-encoded string at AT: (TEXT . NEXT), TEXT nil for a NULL
(def %my-string
  (fn (_ region at)
    (let ((n (%my-length region at)))
      (if (null? (first n)) n
        (pair (sql-link-text (Bytes sub region (rest n) (first n)))
              (+ (rest n) (first n)))))))

; --- packets -----------------------------------------------------------------

; A packet's head: three bytes of length and one of sequence
(def %my-head 4)

; A payload this long goes on in the next packet
(def %my-full 16777215)

; The next packet from the server: (SEQUENCE . PAYLOAD), a payload that
; fills its packet joined to what follows
(def %my-packet
  (fn (self link)
    (let ((head (link take %my-head)))
      (let ((n (%my-uint head 0 3)))
        (let ((payload (link take n)))
          (if (< n %my-full) (pair (Bytes ref head 3) payload)
            (let ((more (self link)))
              (pair (first more) (Bytes join payload (rest more))))))))))

; A packet to the server
(def %my-send
  (fn (_ link sequence payload)
    (let ((w (Bytes writer)))
      (%my-put-uint w (Bytes length payload) 3)
      (Bytes put-u8 w sequence)
      (Bytes put w payload)
      ((link send) (Bytes written w)))))

; The bytes a payload opens with that say what it is
(def %my-ok 0)
(def %my-more-data 1)
(def %my-eof 254)
(def %my-error 255)

; An ERR packet as the mysql client shows one: the code, the state in
; parentheses when the server gives one after a #, and the message
(def %my-report
  (fn (_ payload)
    (let ((code (%my-uint payload 1 2)) (n (Bytes length payload)))
      (if (and (> n 3) (= (Bytes ref payload 3) 35))
        (Str8 str "ERROR " code " (" (sql-link-text (Bytes sub payload 4 5)) "): "
                  (sql-link-text (Bytes sub payload 9 (- n 9))))
        (Str8 str "ERROR " code ": " (sql-link-text (Bytes sub payload 3 (- n 3))))))))

(def %my-error? (fn (_ payload) (= (Bytes ref payload 0) %my-error)))

; An EOF packet: its byte, and shorter than a row that opens with the
; byte of an eight-byte length could be
(def %my-eof?
  (fn (_ payload)
    (and (= (Bytes ref payload 0) %my-eof) (< (Bytes length payload) 9))))

; --- sign-in -----------------------------------------------------------------

; A digest's bytes, from its hex
(def %my-sha1
  (fn (_ region)
    (let ((whole (Bytes copy region)))
      (Bytes of-hex (Sha1 hex-n (first whole) (Bytes length whole))))))

(def %my-sha256
  (fn (_ region)
    (let ((whole (Bytes copy region)))
      (Bytes region (Sha256 bytes-n (first whole) (Bytes length whole)) 0 32))))

(def %my-bytes
  (fn (_ region)
    (List map (fn (_ i) (Bytes ref region i)) (List range 0 (Bytes length region)))))

; Each byte of A with the same byte of B, exclusive or
(def %my-xor
  (fn (_ a b)
    (Bytes of-list
      (List map (fn (_ x y) (- (+ x y) (* 2 (& x y)))) (%my-bytes a) (%my-bytes b)))))

; What a plugin sends for a password and the server's nonce.  A plugin is
; a static method named as the server names it.  An empty password is
; nothing at all.
(def-class MyAuth ()
  (static
    ; SHA1(password) xor SHA1(nonce, SHA1(SHA1(password)))
    (method mysql_native_password (self password nonce)
      (if (= (Str8 length password) 0) (Bytes of "")
        (let ((once (%my-sha1 (Bytes of password))))
          (%my-xor once (%my-sha1 (Bytes join nonce (%my-sha1 once)))))))
    ; SHA256(password) xor SHA256(SHA256(SHA256(password)), nonce)
    (method caching_sha2_password (self password nonce)
      (if (= (Str8 length password) 0) (Bytes of "")
        (let ((once (%my-sha256 (Bytes of password))))
          (%my-xor once (%my-sha256 (Bytes join (%my-sha256 once) nonce))))))
    ; The password and a NUL, when the server asks for it so
    (method mysql_clear_password (self password nonce)
      (Bytes join password %my-nul))))

(def my-auth
  (fn (_ plugin password nonce)
    (let ((answer (class-static-ref MyAuth (Str8 ->sym plugin))))
      (when (null? answer)
        (error (Str8 append "Connection Error: the server asks for a sign-in that is not built, " plugin)))
      (answer MyAuth (if (null? password) "" password) nonce))))

; The capabilities this client has, by MySQL's names for them
(def %my-long-password 1)
(def %my-long-flag 4)
(def %my-connect-with-db 8)
(def %my-protocol-41 512)
(def %my-transactions 8192)
(def %my-secure-connection 32768)
(def %my-multi-statements 65536)
(def %my-multi-results 131072)
(def %my-plugin-auth 524288)
(def %my-ssl 2048)

(def %my-capabilities
  (fn (_ database secure)
    (+ %my-long-password %my-long-flag %my-protocol-41 %my-transactions
       %my-secure-connection %my-multi-statements %my-multi-results
       %my-plugin-auth
       (if (null? database) 0 %my-connect-with-db)
       (if secure %my-ssl 0))))

; The most a packet may hold, and utf8mb4_general_ci, as the handshake's
; answer names them
(def %my-max-packet 16777216)
(def %my-charset 45)

; The nonce's length when the handshake does not give one
(def %my-nonce-length 20)

; The server's handshake: (PLUGIN NONCE TLS), TLS whether the server takes
; it.  The nonce is in two parts, eight bytes after the thread's number and
; the rest after ten bytes reserved, its whole length one less than the
; byte before those says.  The low half of the server's capabilities is
; nine bytes past the thread's number.
(def %my-handshake
  (fn (_ payload)
    (when (%my-error? payload) (error (%my-report payload)))
    (unless (= (Bytes ref payload 0) 10)
      (error (Str8 str "Protocol Error: a handshake of version " (Bytes ref payload 0))))
    (let ((at (rest (%my-cstring payload 1))))
      (let ((given (Bytes ref payload (+ at 20))))
        (let ((n (if (> given 0) (- given 1) %my-nonce-length)))
          (list (first (%my-cstring payload (+ at 31 (if (> (- given 8) 13) (- given 8) 13))))
                (Bytes join (Bytes sub payload (+ at 4) 8)
                            (Bytes sub payload (+ at 31) (- n 8)))
                (not (= (& (%my-uint payload (+ at 13) 2) %my-ssl) 0))))))))

; What every answer to the handshake opens with: the capabilities, the
; most a packet may hold, the character set, and 23 bytes reserved.  Alone
; it is the SSLRequest.
(def %my-preamble
  (fn (_ w database secure)
    (%my-put-uint w (%my-capabilities database secure) 4)
    (%my-put-uint w %my-max-packet 4)
    (Bytes put-u8 w %my-charset)
    (Bytes put w (Bytes of-list (List repeat 23 0)))))

(def %my-ssl-request
  (fn (_ database)
    (let ((w (Bytes writer)))
      (%my-preamble w database #t)
      (Bytes copy (Bytes written w)))))

; The handshake's answer
(def %my-response
  (fn (_ user database plugin answer secure)
    (let ((w (Bytes writer)))
      (%my-preamble w database secure)
      (Bytes put w user) (Bytes put-u8 w 0)
      (Bytes put-u8 w (Bytes length answer))
      (Bytes put w answer)
      (unless (null? database) (Bytes put w database) (Bytes put-u8 w 0))
      (Bytes put w plugin) (Bytes put-u8 w 0)
      (Bytes copy (Bytes written w)))))

; What follows 1 in an AuthMoreData packet of caching_sha2_password: the
; server has the password cached and is satisfied, or wants it whole
(def %my-fast-auth 3)
(def %my-full-auth 4)

; The server's packets after the handshake's answer, until it says OK.  It
; may ask to sign in again by another plugin, with a nonce of its own.
(def %my-signed-in
  (fn (self link password)
    (let ((p (%my-packet link)))
      (let ((payload (rest p)) (kind (Bytes ref (rest p) 0)))
        (match
          ((= kind %my-ok) ())
          ((= kind %my-error) (error (%my-report payload)))
          ((= kind %my-eof)
            (let ((plugin (%my-cstring payload 1)))
              (let ((left (- (Bytes length payload) (rest plugin))))
                (%my-send link (+ (first p) 1)
                  (my-auth (first plugin) password
                    (Bytes sub payload (rest plugin) (if (> left 0) (- left 1) 0))))
                (self link password))))
          ((and (= kind %my-more-data) (= (Bytes ref payload 1) %my-fast-auth))
            (self link password))
          ((and (= kind %my-more-data) (= (Bytes ref payload 1) %my-full-auth))
            (if (link secure)
              (do (%my-send link (+ (first p) 1)
                    (Bytes join (if (null? password) "" password) %my-nul))
                  (self link password))
              (error "Connection Error: the server wants the whole password, which goes only over TLS")))
          (#t (error "Protocol Error: sign-in took a turn that is not read")))))))

; Whether a session takes TLS: MODE as sql/pg reads it, and OFFERED
; whether the server's handshake says it can
(def %my-secure?
  (fn (_ mode offered)
    (match
      ((str=? mode "disable") #f)
      (offered #t)
      ((str=? mode "prefer") #f)
      (#t (error "Connection Error: the server does not take TLS, and sslmode asks for it")))))

; A session on LINK: the handshake, TLS when TLS, a list of a mode and the
; server's name, asks for it and the server has it, the handshake's
; answer, and the server's OK.  DATABASE may be nil.  Answers LINK.
(def my-start
  (fn (_ link user password database . tls)
    (let ((hello (%my-packet link)))
      (let ((shake (%my-handshake (rest hello))))
        (let ((secure (if (null? tls) #f (%my-secure? (first tls) (List third shake)))))
          (when secure
            (%my-send link (+ (first hello) 1) (%my-ssl-request database))
            (link secure! (List second tls) (str=? (first tls) "verify-full")))
          (%my-send link (+ (first hello) (if secure 2 1))
            (%my-response user database (first shake)
                          (my-auth (first shake) password (List second shake))
                          secure))
          (%my-signed-in link password)
          link)))))

; --- queries -----------------------------------------------------------------

; A column's type byte, its name, and whether it is a number
(def %my-types
  (list (list 0 "decimal" #t) (list 1 "tinyint" #t) (list 2 "smallint" #t)
        (list 3 "int" #t) (list 4 "float" #t) (list 5 "double" #t)
        (list 6 "null" #f) (list 7 "timestamp" #f) (list 8 "bigint" #t)
        (list 9 "mediumint" #t) (list 10 "date" #f) (list 11 "time" #f)
        (list 12 "datetime" #f) (list 13 "year" #t) (list 15 "varchar" #f)
        (list 16 "bit" #f) (list 245 "json" #f) (list 246 "decimal" #t)
        (list 249 "tinytext" #f) (list 250 "mediumtext" #f)
        (list 251 "longtext" #f) (list 252 "text" #f) (list 253 "varchar" #f)
        (list 254 "char" #f) (list 255 "geometry" #f)))

; The character set that says a column holds bytes, not text, and what
; the three text types are called then
(def %my-binary 63)
(def %my-binary-names
  (list (pair "text" "blob") (pair "varchar" "varbinary") (pair "char" "binary")))

; A column definition: (NAME TYPE-NAME NUMBER).  Six length-encoded
; strings, the fifth the name; then a byte, the character set in two, a
; length in four, and the type.
(def %my-column
  (fn (_ payload)
    (let ((name ((fn (self at left)
                   (let ((s (%my-string payload at)))
                     (if (<= left 1) s (self (rest s) (- left 1)))))
                 0 5)))
      (let ((at (rest (%my-string payload (rest name)))))
        (let ((row (List find (fn (_ r) (= (first r) (Bytes ref payload (+ at 7)))) %my-types))
              (binary (= (%my-uint payload (+ at 1) 2) %my-binary)))
          (if (null? row)
            (list (first name) (Str8 str "type " (Bytes ref payload (+ at 7))) #f)
            (let ((as-bytes (List find (fn (_ b) (str=? (first b) (List second row)))
                                       %my-binary-names)))
              (list (first name)
                    (if (and binary (not (null? as-bytes))) (rest as-bytes) (List second row))
                    (List third row)))))))))

; A row's cells: ((TEXT . NULL) ...)
(def %my-row
  (fn (_ payload count)
    ((fn (self left at)
       (if (<= left 0) ()
         (let ((s (%my-string payload at)))
           (pair (if (null? (first s)) (pair "NULL" #t) (pair (first s) #f))
                 (self (- left 1) (rest s))))))
     count 0)))

(def %my-packets
  (fn (self link n)
    (if (<= n 0) ()
      (let ((p (rest (%my-packet link))))
        (pair p (self link (- n 1)))))))

; The rows of a result, to the EOF that ends them: (ROWS . STATUS), ROWS
; newest first and STATUS the server's flags
(def %my-rows
  (fn (self link count rows)
    (let ((payload (rest (%my-packet link))))
      (match
        ((%my-error? payload) (error (%my-report payload)))
        ((%my-eof? payload) (pair rows (%my-uint payload 3 2)))
        (#t (self link count (pair (%my-row payload count) rows)))))))

; The flag that says another result follows this one
(def %my-more-results 8)

(def %my-affected
  (fn (_ n) (Str8 str "Query OK, " n (if (= n 1) " row affected" " rows affected"))))

; The server's answers to a query: every statement's result.  DONE holds
; them newest first.
(def %my-answers
  (fn (self link done)
    (let ((payload (rest (%my-packet link))))
      (let ((result
              (match
                ((%my-error? payload) (error (%my-report payload)))
                ((= (Bytes ref payload 0) %my-ok)
                  (let ((affected (%my-length payload 1)))
                    (let ((status (%my-uint payload (rest (%my-length payload (rest affected))) 2)))
                      (pair (list () () () () (%my-affected (first affected))) status))))
                (#t
                  (let ((columns (List map %my-column
                                   (%my-packets link (first (%my-length payload 0))))))
                    (%my-packet link)
                    (let ((rows (%my-rows link (List length columns) ())))
                      (pair (list (List map first columns) (List map (fn (_ c) (List second c)) columns)
                                  (List map (fn (_ c) (List third c)) columns)
                                  (List reverse (first rows)) ())
                            (rest rows))))))))
        (if (= (& (rest result) %my-more-results) 0)
          (List reverse (pair (first result) done))
          (self link (pair (first result) done)))))))

; COM_QUERY and COM_QUIT, the bytes a command packet opens with
(def %my-command-query 3)
(def %my-command-quit 1)

; TEXT run by the server: every statement's result
(def my-query
  (fn (_ link text)
    (%my-send link 0 (Bytes join (Bytes of-list (list %my-command-query)) text))
    (%my-answers link ())))

; The session ended: the server told, where a link can tell it
(def my-finish
  (fn (_ link)
    (guard (_ ()) (%my-send link 0 (Bytes of-list (list %my-command-quit))))))

(provide sql/my my-start my-query my-finish my-auth)

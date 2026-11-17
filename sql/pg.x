; # x-sql -- SQL on x-lang
;
; ## sql/pg.x -- PostgreSQL's wire protocol, the client's end
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Protocol 3.0 (PostgreSQL's "Frontend/Backend Protocol"): the startup
; message, authentication in the clear, by MD5 and by SCRAM-SHA-256
; (RFC 5802, RFC 7677), and the simple query, whose results come as text.
; TLS is asked for ahead of the startup message, with an SSLRequest.
; It speaks over a SqlLink (sql/link).  A message is a type byte, a
; four-byte length that counts itself, and a body.
;
; A query answers a list with an entry for each statement the server ran:
;   (NAMES TYPES ROWS TAG)   NAMES the columns, TYPES their type OIDs,
;                            ROWS lists of (TEXT . NULL) cells, TAG the
;                            server's word for what it did, "SELECT 2"
; and a string for each notice, where it came.

(module sql/pg)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/num/tower)
(import x/codec/bytes)
(import x/codec/hmac)
(import x/codec/sha256)
(import x/codec/md5)
(import x/codec/base64)
(import sql/link sql-link-text)
(import sql/number sql-decimal-read)

; --- bytes -------------------------------------------------------------------

(def %pg-text sql-link-text)

(def %pg-nul (Bytes of-list (list 0)))

; The big-endian integer of N bytes of REGION from AT
(def %pg-uint
  (fn (_ region at n)
    ((fn (self i acc)
       (if (>= i n) acc
         (self (+ i 1) (+ (* acc 256) (Bytes ref region (+ at i))))))
     0 0)))

; The text of REGION from AT to the NUL that ends it, and where the next
; thing starts: (TEXT . NEXT)
(def %pg-cstring
  (fn (_ region at)
    (let ((n (Bytes find (Bytes sub region at (- (Bytes length region) at)) %pg-nul)))
      (when (null? n) (error "Protocol Error: a string with no end in a server message"))
      (pair (%pg-text (Bytes sub region at n)) (+ at n 1)))))

(def %pg-put-cstring
  (fn (_ w text) (Bytes put w text) (Bytes put-u8 w 0)))

; --- messages ----------------------------------------------------------------

; How many bytes a message's type and length take
(def %pg-head 5)

; The next message from the server: (TYPE . BODY), TYPE the byte it opens
; with and BODY a region
(def %pg-message
  (fn (_ link)
    (let ((head (link take %pg-head)))
      (pair (Bytes ref head 0)
            (link take (- (%pg-uint head 1 4) 4))))))

; A message to the server: TYPE, then BODY's length and BODY
(def %pg-put
  (fn (_ link type body)
    (let ((w (Bytes writer)))
      (Bytes put-u8 w type)
      (Bytes put-u32 w (+ (Bytes length body) 4))
      (Bytes put w body)
      ((link send) (Bytes written w)))))

; A body of strings, each ended by a NUL
(def %pg-strings
  (fn (_ texts)
    (let ((w (Bytes writer)))
      (List for-each (fn (_ text) (%pg-put-cstring w text)) texts)
      (Bytes copy (Bytes written w)))))

; --- errors and notices ------------------------------------------------------

; The fields of an ErrorResponse or a NoticeResponse: ((CODE . TEXT) ...),
; CODE the byte that names the field
(def %pg-fields
  (fn (self body at)
    (if (or (>= at (Bytes length body)) (= (Bytes ref body at) 0)) ()
      (let ((text (%pg-cstring body (+ at 1))))
        (pair (pair (Bytes ref body at) (first text))
              (self body (rest text)))))))

(def %pg-field
  (fn (_ fields code)
    (let ((f (List find (fn (_ f) (= (first f) code)) fields)))
      (if (null? f) () (rest f)))))

; The bytes that name the fields shown: Severity, Message, Detail, Hint
(def %pg-field-severity 83)
(def %pg-field-message 77)
(def %pg-field-detail 68)
(def %pg-field-hint 72)

; An error or a notice as psql shows one: the severity and the message,
; then the detail and the hint on lines of their own
(def %pg-report
  (fn (_ body)
    (let ((fields (%pg-fields body 0)))
      (let ((line (fn (_ label code)
                    (let ((text (%pg-field fields code)))
                      (if (null? text) "" (Str8 append "\n" label ":  " text))))))
        (Str8 append (%pg-field fields %pg-field-severity) ":  "
                     (%pg-field fields %pg-field-message)
                     (line "DETAIL" %pg-field-detail)
                     (line "HINT" %pg-field-hint))))))

; --- authentication ----------------------------------------------------------

; What the server asks for by MD5: "md5", then the digest of the digest of
; password and user, in hex, and the salt
(def pg-md5-password
  (fn (_ user password salt)
    (let ((salted (Bytes join (Md5 hex (Str8 append password user)) salt)))
      (Str8 append "md5" (Md5 hex-n (first salted) (Bytes length salted))))))

; SCRAM's digest is SHA-256, 32 bytes
(def %pg-digest-size 32)

(def %pg-hmac
  (fn (_ key message)
    (Bytes region (Hmac mac (lit sha256) key message) 0 %pg-digest-size)))

(def %pg-bytes
  (fn (_ region)
    (List map (fn (_ i) (Bytes ref region i)) (List range 0 (Bytes length region)))))

; Each byte of A with the same byte of B, exclusive or
(def %pg-xor
  (fn (_ a b)
    (List map (fn (_ x y) (- (+ x y) (* 2 (& x y)))) a b)))

; A sweep every this many rounds of the key derivation: a round makes
; some ten thousand objects, and nothing collects unless asked
(def %pg-sweep-every 256)

; Hi of RFC 5802, PBKDF2 with HMAC-SHA-256 and one block: the exclusive
; or of ROUNDS keyed digests, each of the one before, the first of the salt
; and a 1
(def %pg-salted
  (fn (_ password salt rounds)
    (Sha256 jit!)
    (let ((first-round (%pg-hmac password (Bytes join salt (Bytes of-list (list 0 0 0 1))))))
      (Bytes of-list
        ((fn (self u acc left)
           (if (<= left 0) acc
             (let ((next (%pg-hmac password u)))
               (when (= (Num remainder left %pg-sweep-every) 0) (Heap collect))
               (self next (%pg-xor acc (%pg-bytes next)) (- left 1)))))
         first-round (%pg-bytes first-round) (- rounds 1))))))

; An attribute of a SCRAM message, "r=..." among its commas, or nil
(def %pg-attribute
  (fn (_ message key)
    (let ((part (List find (fn (_ p) (Str8 starts? (Str8 append key "=") p))
                           (Str8 split "," message))))
      (if (null? part) () (Str8 sub 2 (Str8 length part) part)))))

(def %pg-base64
  (fn (_ region) (%pg-text (Base64 encode-region region))))

; The client's first SCRAM message without its header: the user is the one
; the startup message named, and NONCE is the client's
(def pg-scram-bare (fn (_ nonce) (Str8 append "n=,r=" nonce)))

; The client's last SCRAM message and the signature the server must
; answer with, as (MESSAGE . SIGNATURE), from the password, the client's
; first message without its header, and the server's first.  "biws" is the
; header "n,," in base64: no channel binding.
(def pg-scram-final
  (fn (_ password bare server-first)
    (let ((nonce (%pg-attribute server-first "r"))
          (salt (%pg-attribute server-first "s"))
          (rounds (%pg-attribute server-first "i")))
      (when (or (null? nonce) (null? salt) (null? rounds)
                (not (Str8 starts? (%pg-attribute bare "r") nonce)))
        (error "Protocol Error: the server's SCRAM message is not one"))
      (let ((salted (%pg-salted password (Base64 decode-region salt)
                                (first (sql-decimal-read rounds))))
            (unproved (Str8 append "c=biws,r=" nonce)))
        (let ((client-key (%pg-hmac salted "Client Key"))
              (auth (Str8 append bare "," server-first "," unproved)))
          (let ((signature (%pg-hmac (Bytes region (Sha256 bytes-n (first client-key) %pg-digest-size)
                                                   0 %pg-digest-size)
                                     auth)))
            (pair (Str8 append unproved ",p="
                    (%pg-base64 (Bytes of-list (%pg-xor (%pg-bytes client-key)
                                                        (%pg-bytes signature)))))
                  (%pg-base64 (%pg-hmac (%pg-hmac salted "Server Key") auth)))))))))

; The codes of an Authentication message
(def %pg-auth-ok 0)
(def %pg-auth-clear 3)
(def %pg-auth-md5 5)
(def %pg-auth-sasl 10)
(def %pg-auth-sasl-continue 11)
(def %pg-auth-sasl-final 12)

; The message types read here, by the byte each opens with
(def %pg-type-auth 82)            ; R
(def %pg-type-error 69)           ; E
(def %pg-type-notice 78)          ; N
(def %pg-type-ready 90)           ; Z
(def %pg-type-columns 84)         ; T
(def %pg-type-row 68)             ; D
(def %pg-type-complete 67)        ; C
(def %pg-type-empty 73)           ; I
; and written
(def %pg-type-password 112)       ; p
(def %pg-type-query 81)           ; Q
(def %pg-type-terminate 88)       ; X

; The next message that is not a notice or a parameter; an error is raised
(def %pg-expect
  (fn (self link)
    (let ((m (%pg-message link)))
      (match
        ((= (first m) %pg-type-error) (error (%pg-report (rest m))))
        ((= (first m) %pg-type-auth) m)
        ((= (first m) %pg-type-ready) m)
        (#t (self link))))))

(def %pg-need-password
  (fn (_ password)
    (when (null? password)
      (error "Connection Error: the server asks for a password and none was given"))))

; The length of the nonce's random bytes, as libpq's
(def %pg-nonce-bytes 18)

; SCRAM-SHA-256 from the server's offer to its last word
(def %pg-scram
  (fn (_ link password body)
    (unless (List includes? "SCRAM-SHA-256" (Str8 split "\x01" (%pg-mechanisms body 4)))
      (error "Connection Error: the server offers no SCRAM-SHA-256"))
    (let ((bare (pg-scram-bare (%pg-base64 (Bytes random %pg-nonce-bytes)))))
      (let ((first-message (Str8 append "n,," bare)) (w (Bytes writer)))
        (%pg-put-cstring w "SCRAM-SHA-256")
        (Bytes put-u32 w (Str8 length first-message))
        (Bytes put w first-message)
        (%pg-put link %pg-type-password (Bytes copy (Bytes written w)))
        (let ((m (%pg-expect link)))
          (unless (= (%pg-uint (rest m) 0 4) %pg-auth-sasl-continue)
            (error "Protocol Error: SCRAM did not continue"))
          (let ((final (pg-scram-final password bare
                         (%pg-text (Bytes sub (rest m) 4 (- (Bytes length (rest m)) 4))))))
            (%pg-put link %pg-type-password (Bytes of (first final)))
            (let ((last (%pg-expect link)))
              (unless (and (= (%pg-uint (rest last) 0 4) %pg-auth-sasl-final)
                           (str=? (%pg-text (Bytes sub (rest last) 4 (- (Bytes length (rest last)) 4)))
                                  (Str8 append "v=" (rest final))))
                (error "Connection Error: the server did not prove it knows the password")))))))))

; The mechanisms a SASL offer names, joined by a byte no name holds
(def %pg-mechanisms
  (fn (self body at)
    (if (or (>= at (Bytes length body)) (= (Bytes ref body at) 0)) ""
      (let ((name (%pg-cstring body at)))
        (Str8 append (first name) "\x01" (self body (rest name)))))))

; The server's Authentication messages answered until it says OK
(def %pg-authenticate
  (fn (self link user password)
    (let ((m (%pg-expect link)))
      (unless (= (first m) %pg-type-auth)
        (error "Protocol Error: the server did not ask who is there"))
      (let ((code (%pg-uint (rest m) 0 4)))
        (match
          ((= code %pg-auth-ok) ())
          ((= code %pg-auth-clear)
            (do (%pg-need-password password)
                (%pg-put link %pg-type-password (%pg-strings (list password)))
                (self link user password)))
          ((= code %pg-auth-md5)
            (do (%pg-need-password password)
                (%pg-put link %pg-type-password
                  (%pg-strings (list (pg-md5-password user password (Bytes sub (rest m) 4 4)))))
                (self link user password)))
          ((= code %pg-auth-sasl)
            (do (%pg-need-password password)
                (%pg-scram link password (rest m))
                (self link user password)))
          (#t (error (Str8 str "Connection Error: the server asks for an authentication that is not built, "
                               code))))))))

; Protocol 3.0, as the startup message names it, and the number an
; SSLRequest carries in a protocol version's place
(def %pg-protocol 196608)
(def %pg-ssl-request 80877103)

; The server's one-byte answers to an SSLRequest: S, it will; N, it will
; not
(def %pg-ssl-yes 83)
(def %pg-ssl-no 78)

; TLS on LINK as MODE asks, for a server named HOST: "disable" leaves the
; link as it is; "prefer" takes TLS when the server has it; "require"
; refuses a server without it; "verify-full" also checks the server's
; certificate for HOST.
(def %pg-secure
  (fn (_ link mode host)
    (unless (str=? mode "disable")
      (let ((w (Bytes writer)))
        (Bytes put-u32 w 8)
        (Bytes put-u32 w %pg-ssl-request)
        ((link send) (Bytes written w))
        (let ((answer (Bytes ref (link take 1) 0)))
          (match
            ((= answer %pg-ssl-yes) (link secure! host (str=? mode "verify-full")))
            ((and (= answer %pg-ssl-no) (str=? mode "prefer")) ())
            ((= answer %pg-ssl-no)
              (error "Connection Error: the server does not take TLS, and sslmode asks for it"))
            (#t (error "Protocol Error: the server's answer to an SSLRequest is not one"))))))))

; A session on LINK: TLS when TLS, a list of a mode and the server's name,
; asks for it; the startup message; authentication; and the server's
; messages up to its first ReadyForQuery.  Answers LINK.
(def pg-start
  (fn (_ link user password database . tls)
    (unless (null? tls) (%pg-secure link (first tls) (List second tls)))
    (let ((body (Bytes writer)) (w (Bytes writer)))
      (Bytes put-u32 body %pg-protocol)
      (List for-each (fn (_ text) (%pg-put-cstring body text))
                     (list "user" user "database" database "client_encoding" "UTF8"))
      (Bytes put-u8 body 0)
      (Bytes put-u32 w (+ (Bytes length (Bytes written body)) 4))
      (Bytes put w (Bytes written body))
      ((link send) (Bytes written w))
      (%pg-authenticate link user password)
      (%pg-expect link)
      link)))

; --- queries -----------------------------------------------------------------

; A RowDescription's columns: ((NAME . TYPE-OID) ...).  After a name come
; a table's OID and a column number, six bytes, then the type's OID, and
; after that its size, modifier and format, eight.
(def %pg-columns
  (fn (_ body)
    ((fn (self left at)
       (if (<= left 0) ()
         (let ((name (%pg-cstring body at)))
           (pair (pair (first name) (%pg-uint body (+ (rest name) 6) 4))
                 (self (- left 1) (+ (rest name) 18))))))
     (%pg-uint body 0 2) 2)))

; A value's length when it is NULL: -1, as four bytes
(def %pg-null-length 4294967295)

; A DataRow's cells: ((TEXT . NULL) ...)
(def %pg-row
  (fn (_ body)
    ((fn (self left at)
       (if (<= left 0) ()
         (let ((n (%pg-uint body at 4)))
           (if (= n %pg-null-length)
             (pair (pair "NULL" #t) (self (- left 1) (+ at 4)))
             (pair (pair (%pg-text (Bytes sub body (+ at 4) n)) #f)
                   (self (- left 1) (+ at 4 n)))))))
     (%pg-uint body 0 2) 2)))

; The server's answers to a query, up to ReadyForQuery.  DONE holds the
; results and notices so far, newest first; COLUMNS and ROWS are those of
; the statement being answered, ROWS newest first; FAILED is an error's
; text once one has come, raised when the server is ready again.
(def %pg-answers
  (fn (self link done columns rows failed)
    (let ((m (%pg-message link)))
      (let ((type (first m)) (body (rest m)))
        (match
          ((= type %pg-type-ready)
            (if (null? failed) (List reverse done) (error failed)))
          ((= type %pg-type-error) (self link done () () (%pg-report body)))
          ((= type %pg-type-notice)
            (self link (pair (%pg-report body) done) columns rows failed))
          ((= type %pg-type-columns) (self link done (%pg-columns body) () failed))
          ((= type %pg-type-row) (self link done columns (pair (%pg-row body) rows) failed))
          ((= type %pg-type-complete)
            (self link
                  (pair (list (List map first columns) (List map rest columns)
                              (List reverse rows) (first (%pg-cstring body 0)))
                        done)
                  () () failed))
          (#t (self link done columns rows failed)))))))

; TEXT run by the server as a simple query: every statement's result
(def pg-query
  (fn (_ link text)
    (%pg-put link %pg-type-query (%pg-strings (list text)))
    (%pg-answers link () () () ())))

; --- the end -----------------------------------------------------------------

; The session ended: the server told, where a link can tell it
(def pg-finish
  (fn (_ link)
    (guard (_ ()) (%pg-put link %pg-type-terminate (Bytes of "")))))

; --- types -------------------------------------------------------------------

; A type's OID in pg_type, its name there, and whether it is a number, for
; the types a result is likely to hold
(def %pg-types
  (list (list 16 "bool" #f) (list 17 "bytea" #f) (list 18 "char" #f)
        (list 19 "name" #f) (list 20 "int8" #t) (list 21 "int2" #t)
        (list 23 "int4" #t) (list 25 "text" #f) (list 26 "oid" #t)
        (list 114 "json" #f) (list 700 "float4" #t) (list 701 "float8" #t)
        (list 1042 "bpchar" #f) (list 1043 "varchar" #f) (list 1082 "date" #f)
        (list 1083 "time" #f) (list 1114 "timestamp" #f)
        (list 1184 "timestamptz" #f) (list 1186 "interval" #f)
        (list 1700 "numeric" #t) (list 2950 "uuid" #f) (list 3802 "jsonb" #f)))

(def %pg-type
  (fn (_ oid) (List find (fn (_ row) (= (first row) oid)) %pg-types)))

; A type's name, or its OID for one that is not listed
(def pg-type-name
  (fn (_ oid)
    (let ((row (%pg-type oid)))
      (if (null? row) (Str8 str "oid " oid) (List second row)))))

(def pg-type-number?
  (fn (_ oid)
    (let ((row (%pg-type oid)))
      (if (null? row) #f (List third row)))))

(provide sql/pg
  pg-start pg-query pg-finish pg-md5-password
  pg-scram-bare pg-scram-final pg-type-name pg-type-number?)

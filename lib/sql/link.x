; # x-sql -- SQL on x-lang
;
; ## lib/sql/link.x -- a byte stream to a server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A SqlLink is the two ends of a byte stream as functions, so a protocol
; is the same over a socket and over bytes a spec supplies.  It starts in
; the clear.  A protocol that has asked its server for TLS, in its own
; way, calls secure!, and the same link then carries TLS 1.3 (x/net/tls13:
; X25519 and ChaCha20-Poly1305).

(module sql/link)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/codec/bytes)
(import x/type/dict)
(import x/sys/socket)
(import x/net/tls13)

(def-class SqlLink ()
  (doc send "A function of a region: every byte of it goes to the server")
  (doc recv "A function of nothing: the next bytes from the server as (STRING . COUNT), nil when it has closed")
  (doc upgrade "A function of a host's name and whether to check the server's certificate for it: TLS begun on the stream, answering (SEND . RECV) for what goes through it; nil for a stream that cannot")
  (doc shut "A function of nothing that closes the stream, or nil")
  (doc (held (Bytes of "")) "The bytes received and not yet taken")
  (doc (secure #f) "Whether the stream is encrypted")

  ; The next N bytes from the server, as a region
  (method take (self n)
    (if (>= (Bytes length (self held)) n)
      (let ((held (self held)))
        (set-field! (lit held) (Bytes sub held n (- (Bytes length held) n)))
        (Bytes sub held 0 n))
      (let ((run ((self recv))))
        (when (null? run)
          (error "Connection Error: the server closed the connection"))
        (set-field! (lit held)
          (Bytes join (self held) (Bytes region (first run) 0 (rest run))))
        (self take n))))

  ; TLS from here on, the server's certificate checked for HOST against
  ; Mozilla's roots when VERIFY.  Bytes the server sent ahead of its side
  ; of the handshake would be read as if they had been encrypted, so they
  ; are an error.
  (method secure! (self host verify)
    (when (null? (self upgrade))
      (error "Connection Error: this connection cannot carry TLS"))
    (when (> (Bytes length (self held)) 0)
      (error "Connection Error: the server sent bytes before TLS began"))
    (let ((ends ((self upgrade) host verify)))
      (set-field! (lit send) (first ends))
      (set-field! (lit recv) (rest ends))
      (set-field! (lit secure) #t)
      ()))

  ; The stream closed, where it can be
  (method close! (self)
    (unless (null? (self shut)) (guard (_ ()) ((self shut))))
    ()))

; A region's bytes as a string.  For text: a NUL among them ends it.
(def sql-link-text (fn (_ region) (first (Bytes copy region))))

; The most bytes one read of the socket takes
(def %sql-read-size 65536)

; A link over a TCP connection to HOST, a name or an address, at PORT.
; The TLS session, once there is one, is held where both ends and the
; close can reach it.
(def sql-socket-link
  (fn (_ host port)
    (let ((fd (Socket tcp-connect (Socket resolve host) port))
          (tls (Dict make)))
      (let ((send (fn (_ region)
                    (let ((whole (Bytes copy region)))
                      (Socket send-run fd (first whole) (Bytes length whole)))))
            (recv (fn (_) (Socket recv-run fd %sql-read-size)))
            (upgrade (fn (_ name verify)
                       (let ((session (Tls13 over fd fd
                                        (if verify (list (pair (lit host) name))
                                          (list (pair (lit host) name) (list (lit insecure)))))))
                         (tls set! (lit session) session)
                         (pair (fn (_ region) (Tls13 send session region))
                               (fn (_) (Tls13 recv-run session %sql-read-size))))))
            (shut (fn (_)
                    (when (tls has? (lit session))
                      (guard (_ ()) (Tls13 close (tls get (lit session)))))
                    (Socket close fd))))
        (new SqlLink send send recv recv upgrade upgrade shut shut)))))

(provide sql/link SqlLink sql-link-text sql-socket-link)

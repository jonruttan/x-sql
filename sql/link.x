; # x-sql -- SQL on x-lang
;
; ## sql/link.x -- a byte stream to a server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A SqlLink is the two ends of a byte stream as functions, so a protocol
; is the same over a socket and over bytes a spec supplies.  The
; connection is not encrypted: there is no TLS here yet.

(module sql/link)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/codec/bytes)
(import x/sys/socket)

(def-class SqlLink ()
  (doc send "A function of a region: every byte of it goes to the server")
  (doc recv "A function of nothing: the next bytes from the server as (STRING . COUNT), nil when it has closed")
  (doc (held (Bytes of "")) "The bytes received and not yet taken")

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
        (self take n)))))

; A region's bytes as a string.  For text: a NUL among them ends it.
(def sql-link-text (fn (_ region) (first (Bytes copy region))))

; The most bytes one read of the socket takes
(def %sql-read-size 65536)

; A link over a TCP connection to HOST, a name or an address, at PORT
(def sql-socket-link
  (fn (_ host port)
    (let ((fd (Socket tcp-connect (Socket resolve host) port)))
      (let ((send (fn (_ region)
                    (let ((whole (Bytes copy region)))
                      (Socket send-run fd (first whole) (Bytes length whole)))))
            (recv (fn (_) (Socket recv-run fd %sql-read-size))))
        (new SqlLink send send recv recv)))))

(provide sql/link SqlLink sql-link-text sql-socket-link)

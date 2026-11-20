; # x-sql -- SQL on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The lang kit's generator writes tests/lib/harness.gen.x: the dialect
; lang.xon declares, the bundle's root on the import path, then this file.
(import sql/lex sql-lex sql-tokenize)
(import sql/parse sql-parse)
(import sql/base sql-version sql-run)
(import sql/repl sql-eval-line)

; A case's statements run, and an error shown as the prompt shows it
(def sql
  (fn (_ text)
    (guard (e (do (display e) (newline)))
      (display (sql-run text)))))
(import x/tool/syntax)
(import sql/syntax)

; A case's text as the grammar reads it: each span's class and its bytes
(def sql-spans
  (fn (_ text)
    (List map (fn (_ span) (list (List third span) (Str8 sub (first span) (List second span) text)))
              ((Syntax named (lit sql)) spans text 0 (Str8 length text)))))
(import sql/repl sql-paint sql-marks sql-complete)

; A line before the cursor, as much of the editor's buffer as Tab asks for
(def-class SqlLine ()
  text
  (method before (self) (self text)))
(import x/type/dict)
(import x/codec/bytes)
(import sql/link SqlLink)
(import sql/pg pg-start pg-query pg-md5-password pg-scram-bare pg-scram-final)
(import sql/my my-start my-query my-auth)
(import sql/base sql-url-parse sql-remote-text sql-pg-results)

; A link whose server is the bytes HEX spells, for a case with no server:
; each read answers the bytes up to the next / in HEX.  What is sent to it
; is shown, a write a line.  Where a protocol begins TLS it shows that,
; with the name and whether the certificate is to be checked, and the
; bytes go on in the clear: a case reads what would be inside.
(def canned-link
  (fn (_ hex)
    (let ((left (Dict from-plist (list (lit runs) (Str8 split "/" hex)))))
      (let ((send (fn (_ region) (display "sent ") (display (Bytes hex region)) (newline)))
            (recv (fn (_)
                    (let ((runs (left get (lit runs))))
                      (if (null? runs) ()
                        (let ((run (Bytes of-hex (first runs))))
                          (left set! (lit runs) (rest runs))
                          (pair (first run) (Bytes length run))))))))
        (let ((upgrade (fn (_ host verify)
                         (display (Str8 append "tls " host (if verify " checked" " unchecked")))
                         (newline)
                         (pair send recv))))
          (new SqlLink send send recv recv upgrade upgrade))))))

; Where the fixture files are, and where a case may write one: both under
; the bundle, wherever it is.  tests/lib is not kept by git.
(def sql-fixtures (Str8 append %lang-root "/tests/fixtures/"))
(def sql-scratch (Str8 append %lang-root "/tests/lib/"))

; A case's statements with {F} and {S} in them as those two directories
(def sql-files
  (fn (_ text)
    (sql (Str8 replace "{S}" sql-scratch (Str8 replace "{F}" sql-fixtures text)))))
(import x/sys/file)
(import sql/repl sql-program)

; A program's lines handed out one at a time, as standard input gives them
(def sql-lines
  (fn (_ lines)
    (let ((held (Dict make)))
      (held set! (lit lines) lines)
      (fn (_)
        (let ((left (held get (lit lines))))
          (if (null? left) ()
            (do (held set! (lit lines) (rest left)) (first left))))))))
(import sql/render sql-value-class)

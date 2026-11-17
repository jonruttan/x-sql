; # x-sql -- SQL on x-lang
;
; ## sql/repl.x -- the prompt
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The line editor reads the lines; this says what they mean.  An entry is
; statements up to a closing semicolon, over as many lines as it takes, or
; one line starting with a dot: a command of the prompt's own.

(module sql/repl)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/repl/line)
(import x/repl/lang)
(import sql/lex sql-lex)
(import sql/base sql-run)
(import sql/exec sql-table-names)

; The last token of TEXT that is not a blank or a comment is a semicolon
(def %sql-closed?
  (fn (_ text)
    (let ((last (List find
                  (fn (_ tok)
                    (not (or (eq? (first tok) (lit blank))
                             (eq? (first tok) (lit comment)))))
                  (List reverse (sql-lex text)))))
      (if (null? last) #f
        (and (eq? (first last) (lit op)) (str=? (List second last) ";"))))))

; TEXT and the lines after it up to a closing semicolon; nil when the
; entry is abandoned.  The end of input closes it with what there is.
(def %sql-entry
  (fn (self text)
    (if (%sql-closed? text) text
      (let ((line (Line read %repl-prompt-more)))
        (match
          ((eq? line (lit cancel)) ())
          ((eq? line (lit eof)) text)
          (#t (self (Str8 append text "\n" line))))))))

(def-class SqlDot ()
  (static
    (method quit (self) (Sys exit 0))
    (method exit (self) (Sys exit 0))
    (method tables (self)
      (List for-each (fn (_ name) (display name) (newline)) (sql-table-names)))
    (method help (self)
      (display "A statement ends with a semicolon and may span lines.\n")
      (display "  .help    this text\n")
      (display "  .tables  the tables there are\n")
      (display "  .quit    leave (.exit and ctrl-d do the same)\n"))))

(def %sql-dot
  (fn (_ word)
    (let ((command (class-static-ref SqlDot (Str8 ->sym word))))
      (if (null? command)
        (do (display (Str8 append "unknown command: ." word "; try .help"))
            (newline))
        (command SqlDot)))))

(def sql-eval-line
  (fn (_ line)
    (let ((text (Str8 trim line)))
      (match
        ((= (Str8 length text) 0) ())
        ((Str8 starts? "." text) (%sql-dot (Str8 sub 1 (Str8 length text) text)))
        (#t
          (let ((entry (%sql-entry line)))
            (unless (null? entry)
              (guard (e (do (display e) (newline)))
                (display (sql-run entry))))))))))

(def sql-repl-register!
  (fn (_)
    (Lang register! "sql"
      (list (pair (lit %repl-prompt) "sql> ")
            (pair (lit %repl-prompt-more) "...> ")
            (pair (lit %repl-paint) ())
            (pair (lit %repl-marks) ())
            (pair (lit %repl-complete) ())
            (pair (lit %repl-eval-line) sql-eval-line)))))

; Whether this lang owns the session: the wrapper names the first -l in
; %lang-lead, and a bundle named by a later one is loaded beside it.  A
; wrapper older than the seam binds nothing, and the answer then is yes.
(def sql-leads?
  (fn (_) (guard (_ #t) (str=? %lang-lead "sql"))))

(provide sql/repl sql-eval-line sql-leads? sql-repl-register!)

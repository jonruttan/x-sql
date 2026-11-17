; # x-sql -- SQL on x-lang
;
; ## sql/base.x -- text in, tables out
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module sql/base)
(import x/type/list)
(import x/type/str)
(import sql/parse sql-parse)
(import sql/exec sql-execute)
(import x/repl/ansi)
(import sql/render sql-render)

(def sql-version "0.1.0")

; Every statement of TEXT run in order: their results, as one text.  A
; statement with nothing to show adds nothing.
(def sql-run
  (fn (_ text)
    (Str8 join ""
      (List map
        (fn (_ s)
          (let ((result (sql-execute s)))
            (if (null? result) "" (sql-render result))))
        (sql-parse text)))))

; An error as it is shown: the kind it opens with, up to "Error:", bold red
; on a terminal that takes colour
(def sql-error-text
  (fn (_ e)
    (let ((text (Str8 str e)))
      (let ((at (Str8 index-of "Error:" text)))
        (if (null? at) text
          (Str8 append (Ansi wrap (Ansi bold-red) (Str8 sub 0 (+ at 6) text))
                       (Str8 sub (+ at 6) (Str8 length text) text)))))))

; The operands after `x -l sql --`: -c SQL, as often as wanted.  An error
; ends the run with status 1.
(def sql-main
  (fn (self ops)
    (match
      ((null? ops) (Sys exit 0))
      ((and (str=? (first ops) "-c") (not (null? (rest ops))))
        (do
          (guard (e (do (display (sql-error-text e)) (newline) (Sys exit 1)))
            (display (sql-run (List second ops))))
          (self (rest (rest ops)))))
      (#t
        (do
          (display "usage: x -l sql -- -c SQL [-c SQL]...\n")
          (Sys exit 2))))))

(provide sql/base sql-version sql-run sql-error-text sql-main)

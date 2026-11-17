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
(import sql/eval sql-execute)
(import sql/render sql-render)

(def sql-version "0.1.0")

; Every statement of TEXT run in order: their results, as one text
(def sql-run
  (fn (_ text)
    (Str8 join ""
      (List map (fn (_ s) (sql-render (sql-execute s))) (sql-parse text)))))

; The operands after `x -l sql --`: -c SQL, as often as wanted.  An error
; ends the run with status 1.
(def sql-main
  (fn (self ops)
    (match
      ((null? ops) (Sys exit 0))
      ((and (str=? (first ops) "-c") (not (null? (rest ops))))
        (do
          (guard (e (do (display e) (newline) (Sys exit 1)))
            (display (sql-run (List second ops))))
          (self (rest (rest ops)))))
      (#t
        (do
          (display "usage: x -l sql -- -c SQL [-c SQL]...\n")
          (Sys exit 2))))))

(provide sql/base sql-version sql-run sql-main)

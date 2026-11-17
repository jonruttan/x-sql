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

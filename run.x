; # x-sql -- SQL on x-lang
;
; ## run.x -- the entry
;
; @description SQL after DuckDB's dialect: `x -l sql` is a prompt, and
;   `x -l sql -- -c SQL` runs statements and exits.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; This file contains no path literals.  x.sh boots the dialect lang.xon
; declares, arms this bundle's root with import-path!, reads this file, and
; appends the launcher when no -f was given.
(import sql/base sql-version sql-main)
(import sql/repl sql-leads? sql-repl-register!)

(sql-repl-register!)

; The prompt is this lang's when it leads the session.
(when (sql-leads?)
  (set! %lang-name "SQL")
  (set! %lang-version sql-version)
  (Lang use! "sql"))

; The operands: what follows the "--" after the launcher's own options.
(let ((ops (rest (Sys args (lit program)))))
  (unless (null? ops) (sql-main ops)))

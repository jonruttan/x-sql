; # x-sql -- SQL on x-lang
;
; ## run.x -- the entry
;
; @description SQL after DuckDB's dialect: `x -l sql` is a prompt, and
;   `x -l sql -- -c SQL` runs statements and exits, and `x -l sql -f FILE`
;   runs a file of them, as it does statements piped to it.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; This file contains no path literals.  x.sh boots the dialect lang.xon
; declares, arms this bundle's root with import-path!, reads this file, and
; appends the launcher when no -f was given.
(import sql/base sql-version sql-main)
(import sql/repl sql-leads? sql-repl-register! sql-program-main
  sql-piped? sql-piped-main)

(sql-repl-register!)

; The prompt is this lang's when it leads the session.
(when (sql-leads?)
  (set! %lang-name "SQL")
  (set! %lang-version sql-version)
  (Lang use! "sql"))

; The operands: what follows the "--" after the launcher's own options.
(let ((ops (rest (Sys args (lit program)))))
  (unless (null? ops) (sql-main ops)))

; A file: x.sh puts the text of -f FILE on standard input after this entry
; and binds %batch?.  Statements piped in: x.sh keeps them on a descriptor
; of their own, and the prompt, which has no terminal to read, gives way to
; them.  The writer of a state image loads this entry with %batch? bound, a
; pipe for its input and no program, and is told by %image-writing.
(when (and (sql-leads?) (not (guard (_ #f) (eval (lit %image-writing)))))
  (match
    (%batch? (sql-program-main))
    ((sql-piped?) (sql-piped-main))))

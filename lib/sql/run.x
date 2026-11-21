; # x-sql -- SQL on x-lang
;
; ## lib/sql/run.x -- the entry
;
; @description SQL after DuckDB's dialect: `x -l sql` is a prompt, and
;   `x -l sql -- -c SQL` runs statements and exits, and `x -l sql -f FILE`
;   runs a file of them, as it does statements piped to it.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; This file contains no path literals.  x.sh boots the dialect bundle.xon
; declares, arms this bundle's lib/ with import-path!, imports this module
; and calls its main, and appends the launcher when no -f was given.
;
; Importing this module sets SQL up and starts nothing: the lang is
; registered, and the prompt is made its own when it leads the session.
; main starts it.

(module sql/run)
(import sql/base sql-version sql-main)
(import sql/repl sql-leads? sql-repl-register! sql-program-main
  sql-piped? sql-piped-main)

(sql-repl-register!)

; The prompt is this lang's when it leads the session.
(when (sql-leads?)
  (set! %lang-name "SQL")
  (set! %lang-version sql-version)
  (Lang use! "sql"))

; The operands are what follows the "--" after the launcher's own options.
;
; A file: x.sh puts the text of -f FILE on standard input after the call of
; main and binds %batch?.  Statements piped in: x.sh keeps them on a
; descriptor of their own, and the prompt, which has no terminal to read,
; gives way to them.
(def main
  (fn (_)
    (let ((ops (rest (Sys args (lit program)))))
      (unless (null? ops) (sql-main ops)))
    (when (sql-leads?)
      (match
        (%batch? (sql-program-main))
        ((sql-piped?) (sql-piped-main))))))

(provide sql/run main)

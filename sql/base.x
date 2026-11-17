; # x-sql -- SQL on x-lang
;
; ## sql/base.x -- text in, tables out, here or at a server
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
(import x/type/dict)
(import sql/render sql-render sql-render-table)
(import sql/pg
  pg-start pg-query pg-finish pg-socket-link pg-type-name pg-type-number?)
(import sql/number sql-decimal-read)

(def sql-version "0.1.0")

; --- where statements go ------------------------------------------------------

; The session's server, when it has one: the link, and how the server is
; named in the prompt.  With neither, statements go to the engine here.
(def %sql-session (Dict make))

(def sql-connection
  (fn (_) (%sql-session get (lit name))))

; A server's address in the words of a URL, as
; (USER PASSWORD HOST PORT DATABASE): postgres://user:password@host:port/db,
; every part but the host optional.  The user is PGUSER or USER when none
; is written, the password PGPASSWORD, the port PostgreSQL's, the database
; the user's name.
(def %sql-postgres-port 5432)

(def %sql-before
  (fn (_ mark text)
    (let ((at (Str8 index-of mark text)))
      (if (null? at) () (Str8 sub 0 at text)))))

(def %sql-after
  (fn (_ mark text)
    (let ((at (Str8 index-of mark text)))
      (if (null? at) ()
        (Str8 sub (+ at (Str8 length mark)) (Str8 length text) text)))))

(def %sql-env
  (fn (_ name)
    (let ((v (Sys getenv name)))
      (if (and (str? v) (> (Str8 length v) 0)) v ()))))

(def sql-url-parse
  (fn (_ url)
    (let ((address (%sql-after "://" url)))
      (when (or (null? address)
                (not (List includes? (%sql-before "://" url) (list "postgres" "postgresql"))))
        (error (Str8 append "Connection Error: not a postgres:// URL, " url)))
      (let ((plain (if (null? (%sql-before "?" address)) address (%sql-before "?" address))))
        (let ((who (%sql-before "@" plain))
              (where (if (null? (%sql-after "@" plain)) plain (%sql-after "@" plain))))
          (let ((user (match
                        ((null? who) (if (null? (%sql-env "PGUSER")) (%sql-env "USER") (%sql-env "PGUSER")))
                        ((null? (%sql-before ":" who)) who)
                        (#t (%sql-before ":" who))))
                (password (if (or (null? who) (null? (%sql-after ":" who)))
                            (%sql-env "PGPASSWORD")
                            (%sql-after ":" who)))
                (place (if (null? (%sql-before "/" where)) where (%sql-before "/" where)))
                (database (%sql-after "/" where)))
            (when (null? user)
              (error "Connection Error: no user in the URL, PGUSER or USER"))
            (list user password
                  (if (null? (%sql-before ":" place)) place (%sql-before ":" place))
                  (if (null? (%sql-after ":" place)) %sql-postgres-port
                    (first (sql-decimal-read (%sql-after ":" place))))
                  (if (or (null? database) (= (Str8 length database) 0)) user database))))))))

(def sql-disconnect!
  (fn (_)
    (when (%sql-session has? (lit link))
      (pg-finish (%sql-session get (lit link))))
    (%sql-session del! (lit link))
    (%sql-session del! (lit name))
    ()))

; Statements go to the server at URL from here on.  Answers its name:
; the database at the host.
(def sql-connect!
  (fn (_ url)
    (let ((at (sql-url-parse url)))
      (sql-disconnect!)
      (let ((link (pg-start (pg-socket-link (List third at) (List ref 3 at))
                            (first at) (List second at) (List ref 4 at))))
        (%sql-session set! (lit link) link)
        (%sql-session set! (lit name) (Str8 append (List ref 4 at) "@" (List third at)))
        (sql-connection)))))

; A server's results as text: a table for a statement that answers rows,
; headed by the names of PostgreSQL's types, the server's word for one
; that does not, and a notice as it came
(def sql-remote-text
  (fn (_ results)
    (Str8 join ""
      (List map
        (fn (_ result)
          (match
            ((str? result) (Str8 append result "\n"))
            ((null? (first result)) (Str8 append (List ref 3 result) "\n"))
            (#t (sql-render-table
                  (first result)
                  (List map pg-type-name (List second result))
                  (List map pg-type-number? (List second result))
                  (List third result)))))
        results))))

; Every statement of TEXT run in order: their results, as one text.  A
; statement of the engine's with nothing to show adds nothing.  With a
; server, TEXT goes to it whole.
(def sql-run
  (fn (_ text)
    (if (%sql-session has? (lit link))
      (sql-remote-text (pg-query (%sql-session get (lit link)) text))
      (Str8 join ""
        (List map
          (fn (_ s)
            (let ((result (sql-execute s)))
              (if (null? result) "" (sql-render result))))
          (sql-parse text))))))

; An error as it is shown: the kind it opens with, up to "Error:", bold red
; on a terminal that takes colour
(def sql-error-text
  (fn (_ e)
    (let ((text (Str8 str e)))
      (let ((at (if (null? (Str8 index-of "Error:" text)) (Str8 index-of "ERROR:" text)
                  (Str8 index-of "Error:" text))))
        (if (null? at) text
          (Str8 append (Ansi wrap (Ansi bold-red) (Str8 sub 0 (+ at 6) text))
                       (Str8 sub (+ at 6) (Str8 length text) text)))))))

; The operands after `x -l sql --`: a postgres:// URL, statements then
; going to that server, and -c SQL, as often as wanted.  An error ends the
; run with status 1.
(def sql-main
  (fn (self ops)
    (match
      ((null? ops) (do (sql-disconnect!) (Sys exit 0)))
      ((and (str=? (first ops) "-c") (not (null? (rest ops))))
        (do
          (guard (e (do (display (sql-error-text e)) (newline) (Sys exit 1)))
            (display (sql-run (List second ops))))
          (self (rest (rest ops)))))
      ((Str8 includes? "://" (first ops))
        (do
          (guard (e (do (display (sql-error-text e)) (newline) (Sys exit 1)))
            (sql-connect! (first ops)))
          (self (rest ops))))
      (#t
        (do
          (display "usage: x -l sql -- [postgres://USER[:PASSWORD]@HOST[:PORT][/DATABASE]] -c SQL [-c SQL]...\n")
          (Sys exit 2))))))

(provide sql/base
  sql-version sql-run sql-error-text sql-main sql-url-parse sql-connect!
  sql-disconnect! sql-connection sql-remote-text)

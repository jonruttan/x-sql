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
(import x/type/class)
(import sql/link sql-socket-link)
(import sql/pg pg-start pg-query pg-finish pg-type-name pg-type-number?)
(import sql/my my-start my-query my-finish)
(import sql/number sql-decimal-read)

(def sql-version "0.1.0")

; --- where statements go ------------------------------------------------------

; The session's server, when it has one: how it is named in the prompt, a
; function that runs a text there and answers its results as text, and one
; that ends the session.  With none, statements go to the engine here.
(def %sql-session (Dict make))

(def sql-connection
  (fn (_) (%sql-session get (lit name))))

; A scheme a URL may have, the server's port, the variable its client
; reads a password from, and whether the database is the user's name when
; none is written
(def %sql-schemes
  (list (list "postgres" 5432 "PGPASSWORD" #t)
        (list "postgresql" 5432 "PGPASSWORD" #t)
        (list "mysql" 3306 "MYSQL_PWD" #f)
        (list "mariadb" 3306 "MYSQL_PWD" #f)))

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

; A server's address in the words of a URL, as
; (USER PASSWORD HOST PORT DATABASE SCHEME):
; scheme://user:password@host:port/database, every part but the scheme and
; the host optional.  The user is PGUSER or USER when none is written, and
; the password, the port and the database what the scheme's row says;
; DATABASE is nil when there is none.
(def sql-url-parse
  (fn (_ url)
    (let ((address (%sql-after "://" url))
          (scheme (List find (fn (_ row) (str=? (first row) (%sql-before "://" url)))
                             %sql-schemes)))
      (when (or (null? address) (null? scheme))
        (error (Str8 append "Connection Error: not a postgres://, mysql:// or mariadb:// URL, " url)))
      (let ((plain (if (null? (%sql-before "?" address)) address (%sql-before "?" address))))
        (let ((who (%sql-before "@" plain))
              (where (if (null? (%sql-after "@" plain)) plain (%sql-after "@" plain))))
          (let ((user (match
                        ((null? who) (if (null? (%sql-env "PGUSER")) (%sql-env "USER") (%sql-env "PGUSER")))
                        ((null? (%sql-before ":" who)) who)
                        (#t (%sql-before ":" who))))
                (password (if (or (null? who) (null? (%sql-after ":" who)))
                            (%sql-env (List third scheme))
                            (%sql-after ":" who)))
                (place (if (null? (%sql-before "/" where)) where (%sql-before "/" where)))
                (database (%sql-after "/" where)))
            (when (null? user)
              (error "Connection Error: no user in the URL, PGUSER or USER"))
            (list user password
                  (if (null? (%sql-before ":" place)) place (%sql-before ":" place))
                  (if (null? (%sql-after ":" place)) (List second scheme)
                    (first (sql-decimal-read (%sql-after ":" place))))
                  (match
                    ((and (not (null? database)) (> (Str8 length database) 0)) database)
                    ((List ref 3 scheme) user)
                    (#t ()))
                  (first scheme))))))))

; A server's results as text.  A result is a string, a notice as it came;
; or (NAMES TYPES RIGHTS ROWS TAG): a table for a statement that answers
; rows, headed by the server's names for its types, and TAG, the server's
; word, for one that does not.
(def sql-remote-text
  (fn (_ results)
    (Str8 join ""
      (List map
        (fn (_ result)
          (match
            ((str? result) (Str8 append result "\n"))
            ((null? (first result)) (Str8 append (List ref 4 result) "\n"))
            (#t (sql-render-table (first result) (List second result)
                                  (List third result) (List ref 3 result)))))
        results))))

; PostgreSQL's results, which name a type by its OID, as sql-remote-text
; takes them
(def sql-pg-results
  (fn (_ results)
    (List map
      (fn (_ result)
        (if (str? result) result
          (list (first result)
                (List map pg-type-name (List second result))
                (List map pg-type-number? (List second result))
                (List third result)
                (List ref 3 result))))
      results)))

; A session with a kind of server: a static method named for the URL's
; scheme, taking a link and the address, and answering (RUN FINISH), a
; function of a text that answers its results as text and a function of
; nothing that ends the session
(def-class SqlServer ()
  (static
    (method postgres (self link at)
      (pg-start link (first at) (List second at) (List ref 4 at))
      (list (fn (_ text) (sql-remote-text (sql-pg-results (pg-query link text))))
            (fn (_) (pg-finish link))))
    (method postgresql (self link at) (SqlServer postgres link at))
    (method mysql (self link at)
      (my-start link (first at) (List second at) (List ref 4 at))
      (list (fn (_ text) (sql-remote-text (my-query link text)))
            (fn (_) (my-finish link))))
    (method mariadb (self link at) (SqlServer mysql link at))))

(def sql-disconnect!
  (fn (_)
    (when (%sql-session has? (lit finish))
      ((%sql-session get (lit finish))))
    (List for-each (fn (_ key) (%sql-session del! key))
                   (list (lit run) (lit finish) (lit name)))
    ()))

; Statements go to the server at URL from here on.  Answers its name: the
; database at the host, or the host alone.
(def sql-connect!
  (fn (_ url)
    (let ((at (sql-url-parse url)))
      (sql-disconnect!)
      (let ((session ((class-static-ref SqlServer (Str8 ->sym (List ref 5 at)))
                      SqlServer (sql-socket-link (List third at) (List ref 3 at)) at)))
        (%sql-session set! (lit run) (first session))
        (%sql-session set! (lit finish) (List second session))
        (%sql-session set! (lit name)
          (if (null? (List ref 4 at)) (List third at)
            (Str8 append (List ref 4 at) "@" (List third at))))
        (sql-connection)))))

; Every statement of TEXT run in order: their results, as one text.  A
; statement of the engine's with nothing to show adds nothing.  With a
; server, TEXT goes to it whole.
(def sql-run
  (fn (_ text)
    (if (%sql-session has? (lit run))
      ((%sql-session get (lit run)) text)
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

; The operands after `x -l sql --`: a server's URL, statements then
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
          (display "usage: x -l sql -- [postgres://|mysql://|mariadb://USER[:PASSWORD]@HOST[:PORT][/DATABASE]] -c SQL [-c SQL]...\n")
          (Sys exit 2))))))

(provide sql/base
  sql-version sql-run sql-error-text sql-main sql-url-parse sql-connect!
  sql-disconnect! sql-connection sql-remote-text sql-pg-results)

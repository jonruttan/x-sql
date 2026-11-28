; # x-sql -- SQL on x-lang
;
; ## lib/sql/base.x -- text in, tables out, here or at a server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module sql/base)
(import x/type/list)
(import x/type/str)
(import sql/parse sql-parse)
(import sql/exec sql-execute sql-open-file!)
(import x/repl/ansi)
(import x/type/dict)
(import sql/render sql-render sql-render-table sql-one-line-rows)
(import x/type/class)
(import sql/link sql-socket-link sql-link-text)
(import sql/pg pg-start pg-query pg-finish pg-type-name pg-type-number?)
(import sql/my my-start my-query my-finish)
(import sql/number sql-decimal-read)
(import x/repl/term)

(def sql-version "0.1.0")

; --- where statements go ------------------------------------------------------

; The session's server, when it has one: how it is named in the prompt, a
; function that runs a text there and answers its results as text, and one
; that ends the session.  With none, statements go to the engine here.
(def %sql-session (Dict make))

(def sql-connection
  (fn (_) (%sql-session get (lit name))))

; Whether the session's connection is encrypted
(def sql-connection-secure?
  (fn (_) (eq? (%sql-session get (lit secure)) #t)))

; A scheme a URL may have, the server's port, the variable its client
; reads a password from, whether the database is the user's name when none
; is written, and the sslmode when none is written.
(def %sql-schemes
  (list (list "postgres" 5432 "PGPASSWORD" #t "prefer")
        (list "postgresql" 5432 "PGPASSWORD" #t "prefer")
        (list "mysql" 3306 "MYSQL_PWD" #f "prefer")
        (list "mariadb" 3306 "MYSQL_PWD" #f "prefer")))

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

; What a URL may ask of TLS with sslmode=: none, TLS when the server has
; it, TLS or no connection, and that with the server's certificate checked
; for its name against Mozilla's roots
(def %sql-ssl-modes (list "disable" "prefer" "require" "verify-full"))

; The sslmode a URL's QUERY names, UNSAID when it names none
(def %sql-ssl-mode
  (fn (_ unsaid query)
    (let ((part (if (null? query) ()
                  (List find (fn (_ p) (Str8 starts? "sslmode=" p)) (Str8 split "&" query)))))
      (if (null? part) unsaid
        (let ((mode (Str8 sub 8 (Str8 length part) part)))
          (if (List includes? mode %sql-ssl-modes) mode
            (error (Str8 append "Connection Error: sslmode is disable, prefer, require or verify-full, not "
                                mode))))))))

; A server's address in the words of a URL, as
; (USER PASSWORD HOST PORT DATABASE SCHEME SSLMODE):
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
                  (first scheme)
                  (%sql-ssl-mode (List ref 4 scheme) (%sql-after "?" address)))))))))

; A server's results as text.  A result is a string, a notice as it came;
; or (NAMES TYPES RIGHTS ROWS TAG): a table for a statement that answers
; rows, headed by the server's names for its types, and TAG, the server's
; word, for one that does not.  A column whose values go to the right is
; coloured as numbers are and any other as text is.
(def sql-remote-text
  (fn (_ results)
    (Str8 join ""
      (List map
        (fn (_ result)
          (match
            ((str? result) (Str8 append result "\n"))
            ((null? (first result)) (Str8 append (List ref 4 result) "\n"))
            (#t (sql-render-table (first result) (List second result)
                                  (List third result)
                                  (sql-one-line-rows (List ref 3 result))
                                  (List map (fn (_ right) (if right (lit number) (lit string)))
                                            (List third result))))))
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

; A name as a string of the server's SQL, a quote in it doubled
(def %sql-quoted
  (fn (_ name) (Str8 append "'" (Str8 join "''" (Str8 split "'" name)) "'")))

; The rows of the first result of RESULTS that has any columns, each a
; list of its values as text; ROWS-AT is where a result keeps its rows
(def %sql-result-rows
  (fn (_ results rows-at)
    (let ((result (List find (fn (_ r) (and (not (str? r)) (not (null? (first r))))) results)))
      (if (null? result) ()
        (List map (fn (_ row) (List map first row)) (List ref rows-at result))))))

; What a server is asked for its catalogue: the tables a bare name reaches,
; a function of a table's name answering the question for its columns,
; each a name and the server's own word for its type, in the table's order,
; and the names of every column of those tables, each once
(def %sql-pg-tables
  "SELECT table_name FROM information_schema.tables WHERE table_schema = ANY (current_schemas(false)) ORDER BY table_name")
(def %sql-pg-columns
  (fn (_ table)
    (Str8 append "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = ANY (current_schemas(false)) AND table_name = "
                 (%sql-quoted table) " ORDER BY ordinal_position")))
(def %sql-pg-names
  "SELECT DISTINCT column_name FROM information_schema.columns WHERE table_schema = ANY (current_schemas(false)) ORDER BY column_name")
(def %sql-my-tables
  "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY table_name")
(def %sql-my-columns
  (fn (_ table)
    (Str8 append "SELECT column_name, column_type FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = "
                 (%sql-quoted table) " ORDER BY ordinal_position")))
(def %sql-my-names
  "SELECT DISTINCT column_name FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY column_name")

; A session with a kind of server: a static method named for the URL's
; scheme, taking a link and the address, and answering (RUN FINISH SECURE
; ROWS TABLES COLUMNS NAMES): a function of a text that answers its results
; as text, a function of nothing that ends the session, whether the session
; is encrypted, a function of a text that answers the rows of its first
; result, and the three questions of the server's catalogue
(def-class SqlServer ()
  (static
    (method postgres (self link at)
      (pg-start link (first at) (List second at) (List ref 4 at)
                (List ref 6 at) (List third at))
      (list (fn (_ text) (sql-remote-text (sql-pg-results (pg-query link text))))
            (fn (_) (pg-finish link) (link close!))
            (link secure)
            (fn (_ text) (%sql-result-rows (pg-query link text) 2))
            %sql-pg-tables %sql-pg-columns %sql-pg-names))
    (method postgresql (self link at) (SqlServer postgres link at))
    (method mysql (self link at)
      (my-start link (first at) (List second at) (List ref 4 at)
                (List ref 6 at) (List third at))
      (list (fn (_ text) (sql-remote-text (my-query link text)))
            (fn (_) (my-finish link) (link close!))
            (link secure)
            (fn (_ text) (%sql-result-rows (my-query link text) 3))
            %sql-my-tables %sql-my-columns %sql-my-names))
    (method mariadb (self link at) (SqlServer mysql link at))))

(def sql-disconnect!
  (fn (_)
    (when (%sql-session has? (lit finish))
      ((%sql-session get (lit finish))))
    (List for-each (fn (_ key) (%sql-session del! key))
                   (list (lit run) (lit finish) (lit name) (lit secure)
                         (lit rows) (lit tables) (lit columns) (lit names)
                         (lit listed) (lit named)))
    ()))

; Whether a session failed, with the text E says, because the server wants
; a password and none was given: Postgres asks for one, MySQL refuses the
; empty one it is sent
(def %sql-wants-password?
  (fn (_ text)
    (or (Str8 includes? "the server asks for a password and none was given" text)
        (Str8 includes? "ERROR 1045" text))))

; The session is with the server of KIND, a URL's scheme, reached by LINK
; at the address AT, as sql-url-parse answers one.  Answers its name: the
; database at the host, or the host alone.  With RELINK and ASK, a server
; that wants a password when AT has none is asked again once: LINK is
; closed, ASK, a function of AT, answers the password or nil for none, and
; RELINK, a function of nothing, a new link to the server.
(def sql-session!
  (fn (self kind link at . again)
    (sql-disconnect!)
    (let ((tried (guard (e (pair (lit failed) (Str8 str e)))
                   (pair (lit started)
                         ((class-static-ref SqlServer (Str8 ->sym kind)) SqlServer link at)))))
      (if (eq? (first tried) (lit started))
        (let ((session (rest tried)))
          (%sql-session set! (lit run) (first session))
          (%sql-session set! (lit finish) (List second session))
          (%sql-session set! (lit secure) (List third session))
          (%sql-session set! (lit rows) (List ref 3 session))
          (%sql-session set! (lit tables) (List ref 4 session))
          (%sql-session set! (lit columns) (List ref 5 session))
          (%sql-session set! (lit names) (List ref 6 session))
          (%sql-session set! (lit name)
            (if (null? (List ref 4 at)) (List third at)
              (Str8 append (List ref 4 at) "@" (List third at))))
          (sql-connection))
        (let ((password (if (or (null? again) (not (null? (List second at)))
                                (not (%sql-wants-password? (rest tried))))
                          ()
                          (do (link close!) ((List second again) at)))))
          (if (null? password) (error (rest tried))
            (self kind ((first again)) (pair (first at) (pair password (rest (rest at)))))))))))

; A password typed at the terminal for the user and host of AT, not shown
; as it is typed: Enter ends it, Backspace takes back a character, and
; ctrl-c, or ctrl-d on nothing typed, answers nil.  Nil when standard input
; is not a terminal.
(def %sql-password-read
  (fn (_ at)
    (let ((saved (Term raw! 0)))
      (if (null? saved) ()
        (let ((typed (guard (e (pair (lit failed) (Str8 str e)))
                       (do (Term emit 1 (Str8 append "Password for " (first at) "@" (List third at) ": "))
                           (pair (lit read) (%sql-password-keys ()))))))
          (Term restore! 0 saved)
          (Term emit 1 "\r\n")
          (when (eq? (first typed) (lit failed)) (error (rest typed)))
          (rest typed))))))

; The bytes of a UTF-8 character's tail
(def %sql-continuation? (fn (_ b) (and (> b 127) (< b 192))))

; HELD, the bytes typed so far newest first, without its last character
(def %sql-unkeyed
  (fn (_ held)
    (if (null? held) ()
      (rest (List drop-while %sql-continuation? held)))))

; The rest of a password read from standard input, HELD the bytes typed so
; far newest first: as a text, or nil when it is given up
(def %sql-password-keys
  (fn (self held)
    (let ((got (Sys fd-read 0 1)))
      (let ((b (if (null? got) 4 (first got))))
        (match
          ((or (= b 13) (= b 10)) (sql-link-text (Bytes of-list (List reverse held))))
          ((= b 3) ())
          ((= b 4) (if (null? held) () (self held)))
          ((or (= b 127) (= b 8)) (self (%sql-unkeyed held)))
          (#t (self (pair b held))))))))

; The server's tables, the ones a bare name reaches, in the order of
; their names; nil with no server.  The server is asked once and the
; answer kept until a statement goes to it, since Tab asks at every press.
(def sql-server-tables
  (fn (_)
    (if (not (%sql-session has? (lit rows))) ()
      (do (unless (%sql-session has? (lit listed))
            (%sql-session set! (lit listed)
              (List map first ((%sql-session get (lit rows)) (%sql-session get (lit tables))))))
          (%sql-session get (lit listed))))))

; The columns of the server's table NAME, each (NAME TYPE) with the
; server's own word for the type; nil when it has no such table
(def sql-server-columns
  (fn (_ name)
    (List map (fn (_ row) (list (first row) (List second row)))
      ((%sql-session get (lit rows)) ((%sql-session get (lit columns)) name)))))

; The names of the columns of the server's tables, the ones a bare name
; reaches, each once and in order; nil with no server.  Kept like the
; tables, until a statement goes to the server.
(def sql-server-column-names
  (fn (_)
    (if (not (%sql-session has? (lit rows))) ()
      (do (unless (%sql-session has? (lit named))
            (%sql-session set! (lit named)
              (List map first ((%sql-session get (lit rows)) (%sql-session get (lit names))))))
          (%sql-session get (lit named))))))

; Statements go to the server at URL from here on.  Answers its name: the
; database at the host, or the host alone.
(def sql-connect!
  (fn (_ url)
    (let ((at (sql-url-parse url)))
      (sql-disconnect!)
      (let ((relink (fn (_) (sql-socket-link (List third at) (List ref 3 at)))))
        (sql-session! (List ref 5 at) (relink) at relink %sql-password-read)))))

; Every statement of TEXT run in order: their results, as one text.  What
; a statement left behind is swept when it is done: the platform sweeps
; when it is asked to.  A
; statement of the engine's with nothing to show adds nothing.  With a
; server, TEXT goes to it whole.
(def sql-run
  (fn (_ text)
    (if (%sql-session has? (lit run))
      (do (List for-each
            (fn (_ key) (when (%sql-session has? key) (%sql-session del! key)))
            (list (lit listed) (lit named)))
          ((%sql-session get (lit run)) text))
      (Str8 join ""
        (List map
          (fn (_ s)
            (let ((result (sql-execute s)))
              (let ((shown (if (null? result) "" (sql-render result))))
                (Heap collect)
                shown)))
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

; The file an operand names, or nil: a path, or a path after sqlite:// or
; sqlite3://.  An operand that starts with a dash, or has another scheme,
; names none.
(def %sql-file-schemes (list "sqlite://" "sqlite3://"))
(def sql-operand-file
  (fn (_ op)
    (let ((scheme (List find (fn (_ s) (Str8 starts? s op)) %sql-file-schemes)))
      (match
        ((not (null? scheme)) (Str8 sub (Str8 length scheme) (Str8 length op) op))
        ((or (Str8 includes? "://" op) (Str8 starts? "-" op) (= (Str8 length op) 0)) ())
        (#t op)))))

; The session is opened on the SQLite file at PATH: statements go to the
; engine here, and the file's tables are read by their names.  Answers the
; name the file is attached under.
(def sql-open!
  (fn (_ path)
    (sql-disconnect!)
    (sql-open-file! path)))

; The operands after `x -l sql --`: a SQLite file, its tables then read by
; their names; a server's URL, statements then
; going to that server, and -c SQL, as often as wanted.  An error ends the
; run with status 1.  With a -c the run ends after the last operand; with
; none, a URL alone, the session stays on its server and the prompt follows.
(def %sql-operands
  (fn (self ops ran)
    (match
      ((null? ops) (when ran (sql-disconnect!) (Sys exit 0)))
      ((and (str=? (first ops) "-c") (not (null? (rest ops))))
        (do
          (guard (e (do (display (sql-error-text e)) (newline) (Sys exit 1)))
            (display (sql-run (List second ops))))
          (self (rest (rest ops)) #t)))
      ((not (null? (sql-operand-file (first ops))))
        (do
          (guard (e (do (display (sql-error-text e)) (newline) (Sys exit 1)))
            (sql-open! (sql-operand-file (first ops))))
          (self (rest ops) ran)))
      ((Str8 includes? "://" (first ops))
        (do
          (guard (e (do (display (sql-error-text e)) (newline) (Sys exit 1)))
            (sql-connect! (first ops)))
          (self (rest ops) ran)))
      (#t
        (do
          (display "usage: x -l sql -- [FILE.sqlite3 | postgres://|mysql://|mariadb://USER[:PASSWORD]@HOST[:PORT][/DATABASE]] [-c SQL]...\n")
          (Sys exit 2))))))

(def sql-main (fn (_ ops) (%sql-operands ops #f)))

(provide sql/base
  sql-version sql-run sql-error-text sql-main sql-url-parse sql-connect! sql-open! sql-operand-file
  sql-disconnect! sql-connection sql-connection-secure? sql-remote-text
  sql-session! sql-server-tables sql-server-columns sql-server-column-names
  sql-pg-results)

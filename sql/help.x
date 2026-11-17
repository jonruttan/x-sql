; # x-sql -- SQL on x-lang
;
; ## sql/help.x -- what .help says
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The topics are data: a name, a line saying what it is, the forms it
; takes, and examples.  A topic is added by adding its row.

(module sql/help)
(import x/type/list)
(import x/type/str)

; (NAME SUMMARY FORMS EXAMPLES), FORMS and EXAMPLES lists of lines
(def sql-help-topics
  (list
    (list "select" "Rows computed from tables, or from nothing."
      (list "SELECT [DISTINCT] item [[AS] alias], ..."
            "  [FROM table [[AS] alias] [join ...]]"
            "  [WHERE condition] [GROUP BY key, ... | ALL] [HAVING condition]"
            "  [ORDER BY term [ASC | DESC] [NULLS FIRST | LAST], ...]"
            "  [LIMIT count] [OFFSET count]"
            "An item is an expression, *, or table.*")
      (list "SELECT 1 + 2 AS three;"
            "SELECT b, count(*) FROM t WHERE a > 1 GROUP BY b ORDER BY 2 DESC;"))
    (list "from" "DuckDB's order: the table first."
      (list "FROM table [SELECT ...] [WHERE ...] ..."
            "FROM alone is every column.")
      (list "FROM t;" "FROM t SELECT b WHERE a > 1;"))
    (list "join" "More than one table in a FROM."
      (list "table [INNER] JOIN table ON condition"
            "table LEFT | RIGHT | FULL [OUTER] JOIN table ON condition"
            "table CROSS JOIN table"
            "table, table"
            "A column two tables have is written table.column.")
      (list "SELECT t.a, c FROM t JOIN u ON t.a = u.a;"
            "SELECT * FROM t LEFT JOIN u ON t.a = u.a WHERE u.a IS NULL;"))
    (list "group" "A row for a group of rows."
      (list "GROUP BY expression | alias | place in the list, ..."
            "GROUP BY ALL    every item that holds no aggregate"
            "HAVING condition    keeps the groups it is true for"
            "Aggregates: count(*) count(x) sum(x) avg(x) min(x) max(x),"
            "and DISTINCT inside a call: count(DISTINCT x).")
      (list "SELECT b, count(*), avg(a) FROM t GROUP BY ALL HAVING count(*) > 1;"))
    (list "order" "The order of a result, and how much of it."
      (list "ORDER BY expression | alias | place in the list [ASC | DESC]"
            "  [NULLS FIRST | NULLS LAST], ..."
            "LIMIT count [OFFSET count]"
            "A NULL is last unless NULLS FIRST says otherwise.")
      (list "SELECT a FROM t ORDER BY a DESC NULLS FIRST LIMIT 10;"))
    (list "create" "A new table, in memory for the life of the session."
      (list "CREATE [OR REPLACE] TABLE [IF NOT EXISTS] name (column type, ...)"
            "See .help types.")
      (list "CREATE TABLE t (a INTEGER, b VARCHAR, price DECIMAL(8,2));"))
    (list "insert" "Rows into a table, each value cast to its column's type."
      (list "INSERT INTO table [(column, ...)] VALUES (value, ...), ..."
            "A column not named is NULL.")
      (list "INSERT INTO t VALUES (1, 'one', 9.99), (2, 'two', NULL);"
            "INSERT INTO t (b) VALUES ('three');"))
    (list "drop" "A table gone."
      (list "DROP TABLE [IF EXISTS] name")
      (list "DROP TABLE IF EXISTS t;"))
    (list "types" "The types of values and columns."
      (list "INTEGER (INT, INT4)    32-bit integer"
            "BIGINT (INT8, LONG)    64-bit integer"
            "HUGEINT                128-bit integer"
            "DECIMAL(width, scale)  exact, NUMERIC its other name; (18, 3) alone"
            "DOUBLE (FLOAT8)        64-bit floating point"
            "VARCHAR (TEXT, STRING) text"
            "BOOLEAN (BOOL)         true or false"
            "A constant: 42 is the narrowest integer that holds it, 1.50 a"
            "DECIMAL(3,2), 1e3 a DOUBLE, 'text' a VARCHAR.")
      (list "SELECT 42, 1.50, 1e3, 'text', true, NULL;"))
    (list "cast" "A value as another type."
      (list "CAST(expression AS type)"
            "expression::type"
            "A DOUBLE's half rounds to the even integer, a DECIMAL's away"
            "from zero.")
      (list "SELECT '12'::INTEGER + 1, 2.5::INTEGER, 7::DOUBLE, 1.239::DECIMAL(4,2);"))
    (list "operators" "What an expression is built with, loosest first."
      (list "OR"
            "AND"
            "NOT"
            "= == <> != < <= > >=    IS NULL    IS NOT NULL"
            "||                      joins text"
            "+ -"
            "* /  // %               / answers a DOUBLE; // and % are for integers"
            "- +                     a sign"
            "::                      a cast"
            "A NULL operand answers NULL, but for AND, OR and IS.")
      (list "SELECT 7 / 2, 7 // 2, 7 % 2, 'n=' || 1 + 2, NULL IS NULL;"))
    (list "connect" "Statements sent to a PostgreSQL, MySQL or MariaDB server."
      (list ".connect postgres://[user[:password]@]host[:port][/database]"
            ".connect mysql://[user[:password]@]host[:port][/database]"
            ".connect mariadb://...    the same protocol as mysql://"
            ".disconnect"
            "The user is PGUSER or USER when none is written.  For PostgreSQL"
            "the password is PGPASSWORD, the port 5432 and the database the"
            "user's name; for MySQL and MariaDB the password is MYSQL_PWD,"
            "the port 3306 and there is no database unless one is written."
            "Once connected a statement is the server's to read: its SQL, its"
            "types, its errors.  .tables, .schema and Tab's tables are still"
            "the engine's here.  The connection is not encrypted.")
      (list ".connect postgres://me@localhost/mydb"
            "x -l sql -- mysql://me@localhost/mydb -c \"SELECT version()\""))
    (list "prompt" "The prompt's own commands, each on a line starting with a dot."
      (list ".help [topic]     this help, or one topic"
            ".connect URL      send statements to a server; .disconnect"
            ".tables           the tables there are"
            ".schema [table]   the columns of every table, or of one"
            ".quit             leave (.exit and ctrl-d do the same)"
            "A statement ends with a semicolon and may span lines."
            "Tab completes a keyword, a type, a function, a table or a column.")
      (list ".schema t"))))

(def sql-help-topic
  (fn (_ name)
    (List find (fn (_ row) (Str8 ci=? (first row) name)) sql-help-topics)))

(def %sql-help-lines
  (fn (_ lines) (List for-each (fn (_ line) (display "  ") (display line) (newline)) lines)))

; One topic, in full
(def sql-help-show
  (fn (_ row)
    (display (first row)) (display ": ") (display (List second row)) (newline)
    (%sql-help-lines (List third row))
    (display "For example:") (newline)
    (%sql-help-lines (List ref 3 row))))

; Every topic, a line each
(def sql-help-index
  (fn (_)
    (display "A statement ends with a semicolon and may span lines.") (newline)
    (display ".help TOPIC says more about one of:") (newline)
    (List for-each
      (fn (_ row)
        (display "  ") (display (Str8 pad-right 10 #\space (first row)))
        (display (List second row)) (newline))
      sql-help-topics)))

(provide sql/help sql-help-topics sql-help-topic sql-help-show sql-help-index)

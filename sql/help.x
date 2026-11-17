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
(import sql/words sql-same-name?)

; (NAME SUMMARY FORMS EXAMPLES), FORMS and EXAMPLES lists of lines
(def sql-help-topics
  (list
    (list "select" "Rows computed from tables, or from nothing."
      (list "SELECT [DISTINCT] item [[AS] alias], ..."
            "  [FROM table | (SELECT ...) [[AS] alias] [join ...]]"
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
            "table [LEFT] JOIN table USING (column, ...)   the columns shown once"
            "table NATURAL [LEFT] JOIN table              on every column both have"
            "table CROSS JOIN table"
            "table, table"
            "A column two tables have is written table.column.")
      (list "SELECT t.a, c FROM t JOIN u ON t.a = u.a;"
            "SELECT * FROM t LEFT JOIN u ON t.a = u.a WHERE u.a IS NULL;"))
    (list "union" "Two select statements as one."
      (list "SELECT ... UNION [ALL] SELECT ...       the rows of both"
            "SELECT ... INTERSECT [ALL] SELECT ...   the rows both have"
            "SELECT ... EXCEPT [ALL] SELECT ...      the first's rows the second has not"
            "Without ALL a row is there once.  The names are the first"
            "statement's, and each column takes a type both sides go into."
            "INTERSECT joins tighter than UNION and EXCEPT.  An ORDER BY, LIMIT"
            "or OFFSET after the last statement is the whole's.")
      (list "SELECT a FROM t UNION SELECT a FROM u ORDER BY a LIMIT 10;"
            "SELECT a FROM t EXCEPT SELECT a FROM u;"))
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
    (list "update" "Rows of a table changed, or removed."
      (list "UPDATE table SET column = value, ... [WHERE condition]"
            "DELETE FROM table [WHERE condition]"
            "With no WHERE it is every row.  Every SET is worked out from the"
            "row as it was, and its value cast to its column's type.")
      (list "UPDATE t SET price = price * 2 WHERE a > 1;"
            "DELETE FROM t WHERE b IS NULL;"))
    (list "subquery" "A select statement inside another."
      (list "(SELECT ...)                   its one value; NULL when no row"
            "value [NOT] IN (SELECT ...)"
            "[NOT] EXISTS (SELECT ...)"
            "FROM (SELECT ...) [[AS] alias]  a table"
            "WITH name AS (SELECT ...), ... SELECT ...   tables by name"
            "INSERT INTO table [(column, ...)] SELECT ..."
            "CREATE [OR REPLACE] TABLE name AS SELECT ..."
            "A subquery reads the row it is answered for: a name none of its"
            "own tables has is the outer statement's.")
      (list "SELECT a, (SELECT count(*) FROM u WHERE u.a > t.a) FROM t;"
            "WITH big AS (SELECT * FROM t WHERE a > 1) SELECT count(*) FROM big;"))
    (list "files" "CSV and JSON files as tables, and tables as files."
      (list "FROM 'people.csv'               a file's name is a table"
            "FROM 'people.json'              an array of objects, or an object a line"
            "read_csv('file')  read_json('file')    the same, whatever the name ends in"
            "COPY table TO 'file' [(FORMAT csv | json, HEADER [true | false])]"
            "COPY (SELECT ...) TO 'file'"
            "COPY table FROM 'file'"
            "A CSV's first row names its columns when it is all text.  A"
            "column's type is found from its values: whole numbers a BIGINT,"
            "a fraction a DOUBLE, true and false a BOOLEAN, dates a DATE, times"
            "a TIMESTAMP, anything else text.  An empty field and a null are"
            "NULL.  A file's columns are qualified by its name without its"
            "ending, or by an alias.  A name ending .json, .ndjson or .jsonl is"
            "JSON, any other CSV, with commas.")
      (list "SELECT name, score FROM 'people.csv' WHERE active ORDER BY score DESC;"
            "COPY (SELECT * FROM t WHERE a > 1) TO 'out.json';"))
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
            "DATE  TIME  TIMESTAMP  INTERVAL     see .help dates"
            "A constant: 42 is the narrowest integer that holds it, 1.50 a"
            "DECIMAL(3,2), 1e3 a DOUBLE, 'text' a VARCHAR.")
      (list "SELECT 42, 1.50, 1e3, 'text', true, NULL;"))
    (list "conditions" "Choosing by a condition, and testing a value against others."
      (list "CASE WHEN condition THEN value ... [ELSE value] END"
            "CASE value WHEN other THEN value ... [ELSE value] END"
            "value [NOT] IN (value, ...)"
            "value [NOT] BETWEEN low AND high        both ends count"
            "text [NOT] LIKE pattern                 % any run, _ any one character"
            "text [NOT] ILIKE pattern                the same, whatever the case")
      (list "SELECT CASE WHEN a < 3 THEN 'low' ELSE 'high' END FROM t;"
            "SELECT * FROM t WHERE a IN (1, 3) OR b LIKE '%an%';"))
    (list "functions" "The functions of one row's values."
      (list "Text:    lower upper length trim ltrim rtrim reverse"
            "         substring(text, start [, count])   substr is the same"
            "         left(text, n)  right(text, n)  repeat(text, n)"
            "         replace(text, from, to)  concat(value, ...)"
            "         starts_with(text, prefix)  contains(text, part)"
            "Numbers: abs floor ceil round sqrt power(x, y)"
            "Choices: coalesce(value, ...)  ifnull(a, b)  nullif(a, b)"
            "         greatest(value, ...)  least(value, ...)  typeof(value)"
            "Text is counted in characters.  A NULL argument answers NULL, but"
            "for concat, coalesce, greatest and least, which leave NULLs out."
            "For the functions of a group of rows, see .help group.")
      (list "SELECT upper(left(b, 1)) || substring(b, 2), length(b) FROM t;"
            "SELECT coalesce(a, 0), round(avg(a)) FROM t GROUP BY ALL;"))
    (list "dates" "Dates, times, and the time between them."
      (list "DATE '2026-11-17'    TIME '12:34:56'    TIMESTAMP '2026-11-17 12:34:56.5'"
            "INTERVAL '1 year 2 months 3 days 04:05:06'    INTERVAL 2 HOUR"
            "date + days, date - date            a date, and a count of days"
            "date or timestamp + interval        a timestamp"
            "timestamp - timestamp               an interval"
            "Parts:  year month day hour minute second quarter dayofweek dayofyear"
            "        date_part('part', value)    EXTRACT(part FROM value)"
            "Units:  date_trunc('unit', value)   date_diff('unit', from, to)"
            "Others: dayname monthname last_day make_date(y, m, d)"
            "        strftime(value, format)     %Y %y %m %d %H %M %S %B %b %A %a %j"
            "        now() current_timestamp current_date today()"
            "A month added keeps the day of the month, or takes the month's last."
            "There is no time zone: now() is UTC.")
      (list "SELECT DATE '2026-01-31' + INTERVAL 1 MONTH, date_diff('day', d, current_date) FROM t;"
            "SELECT date_trunc('month', ts), count(*) FROM t GROUP BY ALL;"))
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
            "the engine's here."
            "?sslmode= after the URL says what to ask of TLS: prefer, TLS when"
            "the server has it, which is what is asked when nothing is said;"
            "require, TLS or no connection; verify-full, that with the"
            "server's certificate checked for its name against Mozilla's"
            "roots; disable, none.  Only verify-full knows who the server is."
            "With MySQL and MariaDB nothing said is disable, and TLS is not"
            "possible yet: their servers ask a client for a certificate.")
      (list ".connect postgres://me@localhost/mydb"
            ".connect postgres://me@db.example/shop?sslmode=verify-full"
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
    (List find (fn (_ row) (sql-same-name? (first row) name)) sql-help-topics)))

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

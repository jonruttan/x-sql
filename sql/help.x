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
            "An item is an expression, *, or table.*"
            "A star takes EXCLUDE (column, ...), REPLACE (expression AS column, ...)"
            "and RENAME (column AS name, ...) after it, in that order.")
      (list "SELECT 1 + 2 AS three;"
            "SELECT b, count(*) FROM t WHERE a > 1 GROUP BY b ORDER BY 2 DESC;"
            "SELECT * EXCLUDE (a) REPLACE (upper(b) AS b) FROM t;"))
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
            "or OFFSET after the last statement is the whole's."
            "A statement in parentheses is a side read before its neighbours,"
            "and keeps its own ORDER BY and LIMIT.")
      (list "SELECT a FROM t UNION SELECT a FROM u ORDER BY a LIMIT 10;"
            "SELECT a FROM t EXCEPT SELECT a FROM u;"
            "SELECT a FROM t UNION ALL (SELECT a FROM u ORDER BY a LIMIT 3);"))
    (list "group" "A row for a group of rows."
      (list "GROUP BY expression | alias | place in the list, ..."
            "GROUP BY ALL    every item that holds no aggregate"
            "HAVING condition    keeps the groups it is true for"
            "Aggregates: count(*) count(x) sum(x) avg(x) min(x) max(x),"
            "and DISTINCT inside a call: count(DISTINCT x).")
      (list "SELECT b, count(*), avg(a) FROM t GROUP BY ALL HAVING count(*) > 1;"))
    (list "window" "A value for a row from the rows around it."
      (list "function(...) OVER ([PARTITION BY expression, ...]"
            "                    [ORDER BY expression [DESC] [NULLS FIRST | LAST], ...]"
            "                    [frame])"
            "function(...) OVER name       a window of the WINDOW clause"
            "row_number()  rank()  dense_rank()    a row's place in its partition"
            "percent_rank()  cume_dist()           its place as a share of the rows"
            "ntile(n)                              its bucket of n"
            "lag(x [, rows [, otherwise]])         x from a row before"
            "lead(x [, rows [, otherwise]])        x from a row after"
            "first_value(x)  last_value(x)         x at an end of the frame"
            "nth_value(x, n)                       x at the frame's nth row"
            "count sum avg min max                 over the frame"
            "A frame is ROWS, RANGE or GROUPS, then BETWEEN end AND end, or one"
            "end, up to the row: UNBOUNDED PRECEDING, x PRECEDING, CURRENT ROW,"
            "x FOLLOWING, UNBOUNDED FOLLOWING.  ROWS counts rows, GROUPS runs of"
            "rows that tie, and RANGE a distance in the one ORDER BY value."
            "EXCLUDE CURRENT ROW | GROUP | TIES after it leaves rows out."
            "With no frame an ordered window runs from its partition's start to"
            "the row and the rows that tie with it, and one with no order is"
            "the whole partition."
            "WINDOW name AS (...), ...    names windows, after HAVING; a window"
            "in parentheses may start with a name and add to it"
            "QUALIFY condition    keeps the rows a window says, after WINDOW"
            "Windows are answered after WHERE, GROUP BY and HAVING.")
      (list "SELECT a, sum(a) OVER (ORDER BY a) FROM t;"
            "SELECT a, rank() OVER w, ntile(4) OVER w FROM t WINDOW w AS (ORDER BY a);"
            "SELECT * FROM t QUALIFY row_number() OVER (PARTITION BY b ORDER BY a) = 1;"))
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
            "WITH name [(column, ...)] AS (SELECT ...), ... SELECT ...   tables by name"
            "WITH RECURSIVE name AS (SELECT ... UNION [ALL] SELECT ... FROM name ...)"
            "    a table that reads itself: the first side once, then the second"
            "    over the rows last added, until none is; UNION adds a row once"
            "INSERT INTO table [(column, ...)] SELECT ..."
            "CREATE [OR REPLACE] TABLE name AS SELECT ..."
            "A subquery reads the row it is answered for: a name none of its"
            "own tables has is the outer statement's.")
      (list "SELECT a, (SELECT count(*) FROM u WHERE u.a > t.a) FROM t;"
            "WITH big AS (SELECT * FROM t WHERE a > 1) SELECT count(*) FROM big;"
            "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 9) FROM n;"))
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
            "NULL.  An array in a JSON file is a list and an object a struct;"
            "COPY writes them back as those.  A file's columns are qualified by its name without its"
            "ending, or by an alias.  A name ending .json, .ndjson or .jsonl is"
            "JSON, any other CSV, with commas.")
      (list "SELECT name, score FROM 'people.csv' WHERE active ORDER BY score DESC;"
            "COPY (SELECT * FROM t WHERE a > 1) TO 'out.json';"))
    (list "drop" "A table gone."
      (list "DROP TABLE [IF EXISTS] name")
      (list "DROP TABLE IF EXISTS t;"))
    (list "lists" "Lists and structs: values that hold values."
      (list "[1, 2, 3]                      a list; type[] is its type"
            "{'a': 1, 'b': 'x'}             a struct; STRUCT(a type, b type) is its type"
            "list[2]  list[-1]              a place, from 1, or from the end"
            "list[2:3]  list[:2]  list[4:]  a run; text takes both too"
            "struct.a  struct['a']          a field"
            "list(x)  array_agg(x)          a group's values as a list"
            "unnest(list)                   a row for each element, in a SELECT's"
            "                               list or as a table: FROM t, unnest(t.l) AS u(x)"
            "unnest(x, recursive := true)   every level of lists and of structs;"
            "                               max_depth := n, keep_parent_names := true"
            "Lists: len list_contains list_position list_concat || list_append"
            "list_prepend list_sort list_reverse_sort list_reverse flatten"
            "list_slice list_extract list_sum list_min list_max list_avg"
            "list_count list_first list_last list_any_value array_to_string"
            "range generate_series string_split list_distinct list_unique"
            "list_has_any && list_has_all @> <@ list_intersect list_resize"
            "list_where list_select list_grade_up array_pop_front"
            "array_pop_back list_product list_string_agg list_bool_and"
            "list_bool_or list_aggregate repeat.  Structs: struct_pack"
            "struct_extract.  Most list_ names are array_ names too."
            "lambda x: x + 1                an expression of a list's element;"
            "lambda x, i: ...               i is the element's place"
            "list_transform(list, lambda)   the expression for each element"
            "list_filter(list, lambda)      the elements it is true of"
            "list_reduce(list, lambda a, x: ... [, start])   folded into one value"
            "[x * 2 for x in list if x > 1] a list comprehension")
      (list "SELECT [1, 2, 3][2], len([1, 2]), list_sort([3, 1]);"
            "CREATE TABLE t (id INTEGER, tags VARCHAR[], s STRUCT(a INTEGER, b VARCHAR));"
            "SELECT id, s.a, tags[1] FROM t WHERE list_contains(tags, 'x');"
            "SELECT b, list(a) FROM t GROUP BY b;"
            "SELECT id, unnest(tags) AS tag FROM t;"
            "SELECT list_transform([1, 2, 3], lambda x: x * 2);"
            "SELECT id, list_filter(tags, lambda t: len(t) > 3) FROM t;"
            "SELECT [upper(t) for t in tags if t <> 'x'] FROM t;"))
    (list "zones" "Moments, and the time zone that shows them."
      (list "TIMESTAMPTZ '2026-11-17 12:34:56+00'    also TIMESTAMP WITH TIME ZONE"
            "A moment is the same everywhere; the session's zone says what clock"
            "shows it.  Text may end in an offset (+02, -05:30, Z) or a zone's"
            "name (Europe/Paris); with neither it is on the session's clock."
            "SET TimeZone = 'Asia/Tokyo'      SET TIME ZONE 'UTC'      RESET TimeZone"
            "current_setting('TimeZone')      the session's zone, the system's at first"
            "timestamp AT TIME ZONE 'zone'    the moment that zone's clock shows it"
            "moment AT TIME ZONE 'zone'       the timestamp that zone's clock shows"
            "A timestamp or a date beside a moment is read on the session's clock."
            "moment + INTERVAL 1 DAY is the same time on the clock the next day,"
            "whatever the clock did between; hours are time gone by."
            "The zones are the system's, under /usr/share/zoneinfo.")
      (list "SET TimeZone = 'America/New_York'; SELECT now();"
            "SELECT TIMESTAMP '2026-07-15 09:00:00' AT TIME ZONE 'Asia/Tokyo';"))
    (list "types" "The types of values and columns."
      (list "TINYINT (INT1)         8-bit integer"
            "SMALLINT (INT2, SHORT) 16-bit integer"
            "INTEGER (INT, INT4)    32-bit integer"
            "BIGINT (INT8, LONG)    64-bit integer"
            "HUGEINT                128-bit integer"
            "UTINYINT USMALLINT UINTEGER UBIGINT UHUGEINT   the same five, unsigned;"
            "                       also UINT8 UINT16 UINT32 UINT64 UINT128"
            "DECIMAL(width, scale)  exact, NUMERIC its other name; (18, 3) alone"
            "DOUBLE (FLOAT8)        64-bit floating point"
            "REAL (FLOAT, FLOAT4)   32-bit floating point"
            "VARCHAR (TEXT, STRING) text"
            "BOOLEAN (BOOL)         true or false"
            "DATE  TIME  TIMESTAMP  INTERVAL     see .help dates"
            "TIMESTAMPTZ            a moment with a time zone; see .help zones"
            "A constant: 42 is an INTEGER or the wider type that holds it, and"
            "beside a TINYINT or SMALLINT one of those when it fits; 1.50 is a"
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
            "now() is a moment with a time zone: see .help zones.")
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
            "roots; disable, none.  Only verify-full knows who the server is.")
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
            "Tab completes a keyword, a type, a function, a table or a column."
            "x -l sql -f FILE runs a file of statements and commands, and"
            "stops at the first statement that fails.  Statements piped in"
            "are run too, every one of them.")
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

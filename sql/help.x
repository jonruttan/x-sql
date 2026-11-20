; # x-sql -- SQL on x-lang
;
; ## sql/help.x -- what .help says
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The topics are data: a name, a line saying what it is, the forms it
; takes, and examples.  A topic is added by adding its row.  The functions
; are data too, a row each, and a topic lists the ones that are under it.

(module sql/help)
(import x/type/list)
(import x/type/str)
(import sql/words sql-same-name? sql-lower)

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
            "An aggregate takes DISTINCT inside its call: count(DISTINCT x).")
      (list "SELECT b, count(*), avg(a) FROM t GROUP BY ALL HAVING count(*) > 1;"))
    (list "window" "A value for a row from the rows around it."
      (list "function(...) OVER ([PARTITION BY expression, ...]"
            "                    [ORDER BY expression [DESC] [NULLS FIRST | LAST], ...]"
            "                    [frame])"
            "function(...) OVER name       a window of the WINDOW clause"
            "count sum avg min max list            over the frame, after OVER"
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
            "read_csv('file', delim = ';')   the separator said; found when not: , ; tab |"
            "  header = false, skip = 2, nullstr = 'NA', names = ['a', 'b'],"
            "  types = {'a': 'DOUBLE'}, columns = {...}, all_varchar = true"
            "COPY table TO 'file' [(FORMAT csv | json, HEADER [true | false],"
            "                       DELIMITER ';', NULLSTR 'NA')]"
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
            "(1, 'a')  row(1, 'a')          a tuple, its members read by place: t[1]"
            "FROM t, unnest(t.l) AS u(x)    unnest as a table, read for each row of t"
            "unnest(x, recursive := true)   every level of lists and of structs;"
            "                               max_depth := n, keep_parent_names := true"
            "list && list  list @> list  list <@ list   a value shared, every value"
            "                               held, and that the other way round"
            "lambda x: x + 1                an expression of a list's element;"
            "lambda x, i: ...               i is the element's place"
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
      (list "Text is counted in characters.  A NULL argument answers NULL, but"
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
            "EXTRACT(part FROM value)            one part: year, month, day, hour, ..."
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
            ".maxrows N        the most rows of a result that are shown: 40 on a"
            "                  terminal, the first and last with dots between;"
            "                  every row to a file or a pipe"
            ".quit             leave (.exit and ctrl-d do the same)"
            "A statement ends with a semicolon and may span lines."
            "Tab completes a keyword, a type, a function, a table or a column."
            "x -l sql -f FILE runs a file of statements and commands, and"
            "stops at the first statement that fails.  Statements piped in"
            "are run too, every one of them.")
      (list ".schema t"))))

; A function: (NAME SIGNATURE SUMMARY TOPIC ALIASES), TOPIC the topic it
; is listed under and ALIASES its other names.  A function is added by
; adding its row; the names and the order of the arguments are DuckDB's.
(def sql-help-functions
  (list
    (list "lower" "lower(text)"
          "the text in lower case"
          "functions" (list))
    (list "upper" "upper(text)"
          "the text in upper case"
          "functions" (list))
    (list "length" "length(text)"
          "how many characters a text has; of a list, how many elements"
          "functions" (list))
    (list "trim" "trim(text [, characters])"
          "the text without the blanks, or the characters named, at both ends"
          "functions" (list))
    (list "ltrim" "ltrim(text [, characters])"
          "the same at the start alone"
          "functions" (list))
    (list "rtrim" "rtrim(text [, characters])"
          "the same at the end alone"
          "functions" (list))
    (list "reverse" "reverse(text)"
          "the text's characters last first"
          "functions" (list))
    (list "substring" "substring(text, start [, count])"
          "the characters from a place on, the first at 1, as many as the count says"
          "functions" (list "substr"))
    (list "left" "left(text, n)"
          "the first n characters; without the last, when n is below zero"
          "functions" (list))
    (list "right" "right(text, n)"
          "the last n characters; without the first, when n is below zero"
          "functions" (list))
    (list "repeat" "repeat(text, n)"
          "the text n times over; a list likewise"
          "functions" (list))
    (list "replace" "replace(text, from, to)"
          "the text with every from changed for to"
          "functions" (list))
    (list "concat" "concat(value, ...)"
          "the values as one text, NULLs left out"
          "functions" (list))
    (list "starts_with" "starts_with(text, prefix)"
          "whether the text begins with the prefix"
          "functions" (list))
    (list "contains" "contains(text, part)"
          "whether the text holds the part"
          "functions" (list))
    (list "string_split" "string_split(text, separator)"
          "the pieces of the text between the separators, a list"
          "functions" (list "split" "str_split" "string_to_array"))
    (list "abs" "abs(number)"
          "the number without its sign"
          "functions" (list))
    (list "floor" "floor(number)"
          "the whole number at or below"
          "functions" (list))
    (list "ceil" "ceil(number)"
          "the whole number at or above"
          "functions" (list "ceiling"))
    (list "round" "round(number [, places])"
          "the nearest whole number, or the nearest with so many places"
          "functions" (list))
    (list "sqrt" "sqrt(number)"
          "the square root, a DOUBLE"
          "functions" (list))
    (list "power" "power(x, y)"
          "x to the power y, a DOUBLE"
          "functions" (list "pow"))
    (list "coalesce" "coalesce(value, ...)"
          "the first value that is not NULL"
          "functions" (list))
    (list "ifnull" "ifnull(a, b)"
          "a, or b when a is NULL"
          "functions" (list))
    (list "nullif" "nullif(a, b)"
          "a, or NULL when a equals b"
          "functions" (list))
    (list "greatest" "greatest(value, ...)"
          "the largest of the values, NULLs left out"
          "functions" (list))
    (list "least" "least(value, ...)"
          "the smallest of the values, NULLs left out"
          "functions" (list))
    (list "typeof" "typeof(value)"
          "the name of the value's type"
          "functions" (list))
    (list "current_setting" "current_setting('name')"
          "what a setting is: TimeZone"
          "zones" (list))
    (list "timezone" "timezone('zone', value)"
          "value AT TIME ZONE 'zone'"
          "zones" (list))
    (list "count" "count(*)  count([DISTINCT] x)"
          "how many rows a group has, or how many values that are not NULL"
          "group" (list))
    (list "sum" "sum([DISTINCT] x)"
          "a group's values added"
          "group" (list))
    (list "min" "min(x)"
          "the smallest of a group's values"
          "group" (list))
    (list "max" "max(x)"
          "the largest of a group's values"
          "group" (list))
    (list "avg" "avg([DISTINCT] x)"
          "the mean of a group's values, a DOUBLE"
          "group" (list))
    (list "list" "list(x)"
          "a group's values as a list"
          "group" (list "array_agg"))
    (list "row_number" "row_number() OVER (...)"
          "a row's place in its partition, from 1"
          "window" (list))
    (list "rank" "rank() OVER (... ORDER BY ...)"
          "a row's place in its partition, rows that tie sharing one and the places after them skipped"
          "window" (list))
    (list "dense_rank" "dense_rank() OVER (... ORDER BY ...)"
          "the same with no place skipped"
          "window" (list))
    (list "percent_rank" "percent_rank() OVER (... ORDER BY ...)"
          "a row's place as a share of the rows, from 0 to 1"
          "window" (list))
    (list "cume_dist" "cume_dist() OVER (... ORDER BY ...)"
          "the share of the rows at or before the row"
          "window" (list))
    (list "ntile" "ntile(n) OVER (... ORDER BY ...)"
          "a row's bucket of n"
          "window" (list))
    (list "lag" "lag(x [, rows [, otherwise]]) OVER (...)"
          "x from a row before, one before when rows is not said"
          "window" (list))
    (list "lead" "lead(x [, rows [, otherwise]]) OVER (...)"
          "x from a row after"
          "window" (list))
    (list "first_value" "first_value(x) OVER (...)"
          "x at the start of the frame"
          "window" (list))
    (list "last_value" "last_value(x) OVER (...)"
          "x at the end of the frame"
          "window" (list))
    (list "nth_value" "nth_value(x, n) OVER (...)"
          "x at the frame's nth row"
          "window" (list))
    (list "year" "year(value)"
          "the year of a date or a timestamp"
          "dates" (list))
    (list "month" "month(value)"
          "the month, from 1"
          "dates" (list))
    (list "day" "day(value)"
          "the day of the month"
          "dates" (list))
    (list "hour" "hour(value)"
          "the hour"
          "dates" (list))
    (list "minute" "minute(value)"
          "the minute"
          "dates" (list))
    (list "second" "second(value)"
          "the second"
          "dates" (list))
    (list "quarter" "quarter(value)"
          "the quarter of the year, from 1"
          "dates" (list))
    (list "dayofweek" "dayofweek(value)"
          "the day of the week, Sunday 0"
          "dates" (list))
    (list "dayofyear" "dayofyear(value)"
          "the day of the year, from 1"
          "dates" (list))
    (list "date_part" "date_part('part', value)"
          "one part of a date, a time or an interval; EXTRACT(part FROM value) is the same"
          "dates" (list))
    (list "date_trunc" "date_trunc('unit', value)"
          "the value with everything smaller than the unit at its start"
          "dates" (list))
    (list "date_diff" "date_diff('unit', from, to)"
          "how many of the unit's edges lie between two values"
          "dates" (list "datediff"))
    (list "dayname" "dayname(value)"
          "the day's name"
          "dates" (list))
    (list "monthname" "monthname(value)"
          "the month's name"
          "dates" (list))
    (list "last_day" "last_day(value)"
          "the last day of the value's month"
          "dates" (list))
    (list "make_date" "make_date(year, month, day)"
          "the date of three numbers"
          "dates" (list))
    (list "strftime" "strftime(value, format)"
          "the value written as the format says: %Y %y %m %d %H %M %S %B %b %A %a %j"
          "dates" (list))
    (list "now" "now()"
          "this moment, with a time zone"
          "dates" (list "current_timestamp"))
    (list "current_date" "current_date"
          "today's date on the session's clock"
          "dates" (list "today"))
    (list "len" "len(list)"
          "how many elements a list has; of a text, how many characters"
          "lists" (list "array_length"))
    (list "list_value" "list_value(value, ...)"
          "the values as a list, which [value, ...] writes"
          "lists" (list "list_pack"))
    (list "list_contains" "list_contains(list, value)"
          "whether the list holds the value"
          "lists" (list "list_has" "array_contains" "array_has"))
    (list "list_position" "list_position(list, value)"
          "the place of the value in the list, from 1; 0 when it is not there"
          "lists" (list "list_indexof" "array_position" "array_indexof"))
    (list "list_concat" "list_concat(list, list, ...)"
          "the lists end to end, which || also writes"
          "lists" (list "list_cat" "array_concat" "array_cat"))
    (list "list_append" "list_append(list, value)"
          "the list with the value after its last"
          "lists" (list "array_append" "array_push_back"))
    (list "list_prepend" "list_prepend(value, list)"
          "the list with the value before its first"
          "lists" (list "array_prepend"))
    (list "array_push_front" "array_push_front(list, value)"
          "the same, the list written first"
          "lists" (list))
    (list "list_sort" "list_sort(list [, 'ASC' | 'DESC' [, 'NULLS FIRST' | 'NULLS LAST']])"
          "the list in order"
          "lists" (list "array_sort"))
    (list "list_reverse_sort" "list_reverse_sort(list [, 'NULLS FIRST' | 'NULLS LAST'])"
          "the list in order, largest first"
          "lists" (list "array_reverse_sort"))
    (list "list_reverse" "list_reverse(list)"
          "the list last first"
          "lists" (list "array_reverse"))
    (list "flatten" "flatten(list of lists)"
          "the lists inside as one list"
          "lists" (list))
    (list "list_slice" "list_slice(list, from, to [, step])"
          "a run of the list, which list[from:to] writes"
          "lists" (list "array_slice"))
    (list "list_extract" "list_extract(list, place)"
          "the element at a place, which list[place] writes"
          "lists" (list "list_element" "array_extract"))
    (list "list_sum" "list_sum(list)"
          "the elements added"
          "lists" (list))
    (list "list_min" "list_min(list)"
          "the smallest element"
          "lists" (list))
    (list "list_max" "list_max(list)"
          "the largest element"
          "lists" (list))
    (list "list_avg" "list_avg(list)"
          "the mean of the elements, a DOUBLE"
          "lists" (list))
    (list "list_count" "list_count(list)"
          "how many elements are not NULL"
          "lists" (list))
    (list "list_product" "list_product(list)"
          "the elements multiplied, a DOUBLE"
          "lists" (list))
    (list "list_first" "list_first(list)"
          "the first element"
          "lists" (list))
    (list "list_last" "list_last(list)"
          "the last element"
          "lists" (list))
    (list "list_any_value" "list_any_value(list)"
          "the first element that is not NULL"
          "lists" (list))
    (list "list_string_agg" "list_string_agg(list)"
          "the elements as text with commas between"
          "lists" (list))
    (list "list_bool_and" "list_bool_and(list)"
          "whether every element is true"
          "lists" (list))
    (list "list_bool_or" "list_bool_or(list)"
          "whether any element is true"
          "lists" (list))
    (list "list_aggregate" "list_aggregate(list, 'aggregate' [, argument])"
          "the aggregate a text names, over the elements"
          "lists" (list "list_aggr" "array_aggregate" "array_aggr"))
    (list "array_to_string" "array_to_string(list, separator)"
          "the elements as text with the separator between"
          "lists" (list))
    (list "range" "range([from,] to [, step])"
          "the whole numbers from one to before another, a list"
          "lists" (list))
    (list "generate_series" "generate_series([from,] to [, step])"
          "the same with the last number in it"
          "lists" (list))
    (list "list_distinct" "list_distinct(list)"
          "the list's values once each, NULLs left out"
          "lists" (list "array_distinct"))
    (list "list_unique" "list_unique(list)"
          "how many different values the list has"
          "lists" (list "array_unique"))
    (list "list_has_any" "list_has_any(list, list)"
          "whether two lists share a value, which && writes"
          "lists" (list "array_has_any"))
    (list "list_has_all" "list_has_all(list, list)"
          "whether the first holds every value of the second, which @> writes"
          "lists" (list "array_has_all"))
    (list "list_intersect" "list_intersect(list, list)"
          "the values of the first that the second holds, once each"
          "lists" (list "array_intersect"))
    (list "list_resize" "list_resize(list, length [, value])"
          "the list cut to a length or filled out to it, with NULLs or with the value"
          "lists" (list "array_resize"))
    (list "array_pop_front" "array_pop_front(list)"
          "the list without its first element"
          "lists" (list))
    (list "array_pop_back" "array_pop_back(list)"
          "the list without its last element"
          "lists" (list))
    (list "list_where" "list_where(list, truths)"
          "the elements a list of truths is true beside"
          "lists" (list "array_where"))
    (list "list_select" "list_select(list, places)"
          "the elements at a list of places"
          "lists" (list "array_select"))
    (list "list_grade_up" "list_grade_up(list [, 'ASC' | 'DESC' [, 'NULLS FIRST' | 'NULLS LAST']])"
          "the places list_sort would take the elements from"
          "lists" (list "array_grade_up"))
    (list "list_zip" "list_zip(list, ... [, truth])"
          "a list of tuples, the lists' first elements and then their second; a true last cuts to the shortest list"
          "lists" (list "array_zip"))
    (list "list_transform" "list_transform(list, lambda)"
          "the lambda's value for each element"
          "lists" (list "list_apply" "array_transform" "array_apply" "apply"))
    (list "list_filter" "list_filter(list, lambda)"
          "the elements the lambda is true of"
          "lists" (list "array_filter" "filter"))
    (list "list_reduce" "list_reduce(list, lambda [, start])"
          "the elements folded into one value, two at a time"
          "lists" (list "array_reduce" "reduce"))
    (list "unnest" "unnest(list [, recursive := true] [, max_depth := n])"
          "a row for each element, in a SELECT's list or as a table of a FROM"
          "lists" (list))
    (list "row" "row(value, ...)"
          "a tuple, a struct whose fields have no names, which (value, ...) writes"
          "lists" (list))
    (list "struct_pack" "struct_pack(name := value, ...)"
          "a struct, which {'name': value, ...} writes"
          "lists" (list))
    (list "struct_extract" "struct_extract(struct, 'name')"
          "a struct's field, which struct.name writes; a tuple's member by its place"
          "lists" (list))
    (list "read_csv" "read_csv('file' [, delim = ';', header = false, ...])"
          "a CSV file as a table, whatever its name ends in"
          "files" (list "read_csv_auto"))
    (list "read_json" "read_json('file')"
          "a JSON file as a table, whatever its name ends in"
          "files" (list "read_json_auto" "read_ndjson"))))

; The function NAME names, by its own name or another of its names.  The
; rows' names are in lower case, so NAME is folded once and compared as it
; is.
(def sql-help-function
  (fn (_ name)
    (let ((key (sql-lower name)))
      (List find
        (fn (_ row)
          (or (str=? (first row) key)
              (List any? (fn (_ other) (str=? other key)) (List ref 4 row))))
        sql-help-functions))))

; How wide a line of names is let run
(def %sql-help-width 72)

; NAMES as lines of them with a blank between, none past %sql-help-width
(def %sql-help-wrapped
  (fn (_ names)
    (List reverse
      (List fold
        (fn (_ lines name)
          (if (and (not (null? lines))
                   (< (+ (Str8 length (first lines)) 1 (Str8 length name)) %sql-help-width))
            (pair (Str8 append (first lines) " " name) (rest lines))
            (pair name lines)))
        () names))))

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
    (let ((names (List map first
                   (List filter (fn (_ f) (str=? (List ref 3 f) (first row)))
                                sql-help-functions))))
      (unless (null? names)
        (do (display "Functions, each with .help NAME:") (newline)
            (%sql-help-lines (%sql-help-wrapped names)))))
    (display "For example:") (newline)
    (%sql-help-lines (List ref 3 row))))

; One function: how it is written, what it answers, its other names, and
; the topic it is under.  ASKED is the name it was asked for by, said when
; that is another of its names.
(def sql-help-function-show
  (fn (_ row asked)
    (unless (sql-same-name? (first row) asked)
      (do (display asked) (display " is another name of ") (display (first row)) (newline)))
    (display (List second row)) (newline)
    (%sql-help-lines (list (List third row)))
    (unless (null? (List ref 4 row))
      (%sql-help-lines (list (Str8 append "Also " (Str8 join ", " (List ref 4 row))))))
    (%sql-help-lines (list (Str8 append "See .help " (List ref 3 row))))))

; Every topic, a line each
(def sql-help-index
  (fn (_)
    (display "A statement ends with a semicolon and may span lines.") (newline)
    (display ".help NAME says what a function is; .help TOPIC says more about one of:") (newline)
    (List for-each
      (fn (_ row)
        (display "  ") (display (Str8 pad-right 10 #\space (first row)))
        (display (List second row)) (newline))
      sql-help-topics)))

(provide sql/help sql-help-topics sql-help-topic sql-help-show sql-help-index
  sql-help-functions sql-help-function sql-help-function-show)

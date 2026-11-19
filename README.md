# x-sql — SQL on x-lang

<p align="center"><img src="docs/bitwise-banner.svg" alt="x-sql, with Bitwise the owl" width="100%"></p>

A database language on [x-lang](https://github.com/jonruttan/x-lang),
loaded as a lang, following [DuckDB](https://duckdb.org/)'s dialect and
its way of showing a result.

    x -l sql                                  # a prompt
    x -l sql -- -c "SELECT 1 + 2 AS three"    # run and exit
    x -l sql -- postgres://me@localhost/shop -c "SELECT version()"
    x -l sql -- mysql://me@localhost/shop -c "SELECT version()"

    ┌───────┐
    │ three │
    │ int32 │
    ├───────┤
    │     3 │
    └───────┘

## Status

Pre-release: no release has been cut. Paired with x-lang v0.57.0
(`lang.xon` is the checkable row).

What is built:

- **Values.** TINYINT, SMALLINT, INTEGER, BIGINT and HUGEINT, and the
  unsigned UTINYINT to UHUGEINT; an integer constant is the narrowest of
  INTEGER, BIGINT, HUGEINT and UHUGEINT that holds it; DECIMAL, exact,
  a constant with a point taking the width and scale it is written with;
  DOUBLE and the 32-bit REAL, each shown in the fewest digits that read
  back as it; VARCHAR; BOOLEAN; NULL.
- **Dates and times.** DATE, TIME, TIMESTAMP to the microsecond, and
  INTERVAL. A date and a count of days, a moment and
  an interval, two moments apart; a month added keeps the day or takes
  the month's last. `year month day hour minute second quarter
  dayofweek dayofyear date_part EXTRACT date_trunc date_diff dayname
  monthname last_day make_date strftime now current_date today`.
- **Time zones.** TIMESTAMP WITH TIME ZONE, or TIMESTAMPTZ: a moment,
  shown on the session's clock with its offset. Text may end in an
  offset or a zone's name. `SET TimeZone = 'Europe/Paris'` names the
  session's zone, the system's to begin with; `AT TIME ZONE` reads a
  timestamp on a zone's clock or shows a moment on one. A day added is
  the same time on the clock the next day. `now()` is a moment. The
  zones are the system's, read from `/usr/share/zoneinfo` by the
  platform's `x/sys/zone`.
- **Lists and structs.** `[1, 2, 3]` and `{'a': 1, 'b': 'x'}`, inside one
  another to any depth, as values and as columns: `INTEGER[]`,
  `STRUCT(a INTEGER, b VARCHAR)`. `list[2]`, `list[-1]` and the runs
  `list[2:3]`, `list[:2]`, `list[4:]`, which text takes too; `struct.a`
  and `struct['a']`. Compared, sorted and grouped element by element.
  `list(x)` and `array_agg(x)` gather a group. Functions: `len
  list_contains list_position list_concat list_append list_prepend
  list_sort list_reverse_sort list_reverse flatten list_slice
  list_extract list_sum list_min list_max list_avg list_count list_first
  list_last list_any_value array_to_string range generate_series
  string_split struct_pack struct_extract`, and the `array_` names of
  the `list_` ones. Not yet: `unnest`, `list_distinct`, lambdas, maps,
  and text read as a list (`'[1, 2]'::INT[]`).
- **Operators.** `+ - *` on any numbers: integers in the wider type with
  an overflow an error, decimals exactly with DuckDB's widths and scales,
  a double when either is one, a REAL when either is one and neither a
  double. `/` answers a DOUBLE, or a REAL of REALs. `// %` on integers.
  `= == <> != < <= > >=` across the numeric types; `AND OR NOT` in three
  values; `IS [NOT] NULL`; `||`.
- **Conditions.** `CASE` in both forms, its answers going into one
  type; `[NOT] IN (...)`; `[NOT] BETWEEN`; `[NOT] LIKE` and `ILIKE` with
  `%` and `_`.
- **Functions.** Text: `lower upper length trim ltrim rtrim substring
  substr left right replace reverse repeat concat starts_with contains`,
  counting characters, not bytes. Numbers: `abs floor ceil round sqrt
  power`. Choices: `coalesce ifnull nullif greatest least typeof`.
- **Casts.** `CAST(x AS type)` and `x::type` among the numbers, text and
  booleans, rounding as DuckDB does: a double's half to the even integer,
  a decimal's away from zero.
- **Tables.** In memory, for the life of the process: `CREATE [OR
  REPLACE] TABLE [IF NOT EXISTS]`, with columns or `AS` a select
  statement; `INSERT INTO ... VALUES` or from a `SELECT`, with or without
  a column list; `UPDATE ... SET ... [WHERE]`; `DELETE FROM ... [WHERE]`;
  `DROP TABLE [IF EXISTS]`. A value is cast to its column's type as it
  goes in.
- **Queries.** `SELECT [DISTINCT]` with `*` and `t.*`, table aliases,
  `WHERE`, `ORDER BY` with `ASC`, `DESC` and `NULLS FIRST` or `LAST`,
  `LIMIT` and `OFFSET`; and DuckDB's order, `FROM t` alone or
  `FROM t SELECT ...`.
- **Star lists.** After `*` or `t.*`: `EXCLUDE (column, ...)` leaves
  columns out, `REPLACE (expression AS column, ...)` puts an expression in
  a column's place, and `RENAME (column AS name, ...)` shows a column
  under another name, in that order when there is more than one.
- **Joins.** `JOIN ... ON`, `LEFT`, `RIGHT` and `FULL [OUTER] JOIN`,
  `CROSS JOIN`, and tables listed with commas; `JOIN ... USING (...)` and
  `NATURAL JOIN`, inner and left, the shared columns shown once; a table
  joined to itself under two aliases.
- **Set operations.** `UNION`, `INTERSECT` and `EXCEPT`, each with or
  without `ALL`; a trailing `ORDER BY` and `LIMIT` are the whole's. A
  select statement in parentheses is a side, with an `ORDER BY` and
  `LIMIT` of its own.
- **Files.** `FROM 'people.csv'` and `FROM 'people.json'`: a CSV or JSON
  file is a table, its columns' types found from its values as DuckDB
  finds them. An array in a JSON file is a list and an object a struct,
  its fields in the order the file first has them; values that are not
  all one of those are text, where DuckDB has a JSON type. `read_csv` and
  `read_json`. `COPY table TO 'file'`, `COPY
  (SELECT ...) TO 'file'` and `COPY table FROM 'file'`, as CSV or as
  JSON, an object a line, a list written as an array and a struct as an
  object.
- **Subqueries.** A select statement in parentheses for its one value,
  after `[NOT] IN`, after `[NOT] EXISTS`, and as a table of a `FROM`;
  `WITH name AS (...)`, with the columns named after the name if
  wanted. A subquery reads the row it is answered for.
- **Recursion.** `WITH RECURSIVE`: a table that is a `UNION` or `UNION
  ALL` whose second side reads the table itself, answered over the rows
  last added until none is. Nothing stops a recursion that never ends
  but the memory it is given.
- **Groups.** `count`, `sum`, `avg`, `min` and `max`, with `DISTINCT` inside a
  call; `GROUP BY` an expression, an alias, a place in the list, or
  `ALL`; `HAVING`.
- **Windows.** `row_number`, `rank`, `dense_rank`, `percent_rank`,
  `cume_dist`, `ntile`, `lag`, `lead`, `first_value`, `last_value`,
  `nth_value` and the aggregates, each `OVER` a window with `PARTITION
  BY`, `ORDER BY` and a `ROWS`, `RANGE` or `GROUPS` frame, with
  `EXCLUDE`; a `WINDOW` clause names windows; `QUALIFY` keeps the rows
  a window says. A window is answered for each row from the rows of its
  frame, so a long partition is slow.
- **Results.** DuckDB's box, a column as wide as its widest text in
  terminal cells, headed by the alias, the column's name, or the
  expression spelled out. On a terminal the box and the types are dim,
  the names bold and a NULL dim.
- **The prompt.** A statement ends at a semicolon and may span lines.
  A line is coloured as it is typed, by the grammar `sql/syntax.x`, in
  the colours of x-lang's theme; brackets take their depth's colour and
  the pair beside the cursor is inverse. Tab completes a keyword, a
  type, a function, a table or a column. `.help` and `.help TOPIC`,
  `.tables`, `.schema [table]` and `.quit`.
- **Servers.** `.connect URL` at the prompt, or the URL as an operand,
  sends statements to a server and shows what it answers in the same
  box, headed by the server's own names for its types; an error, a
  notice and what a statement did are in the server's client's words.
  `.disconnect` comes back to the engine here.
  - `postgres://user:password@host:port/database`: PostgreSQL's wire
    protocol (`sql/pg.x`), the simple query, with sign-in by trust, a
    password in the clear, MD5 and SCRAM-SHA-256.
  - `mysql://` and `mariadb://`: the protocol MySQL and MariaDB share
    (`sql/my.x`), with sign-in by `mysql_native_password`, and by
    `caching_sha2_password` where the server has the password cached.
- **TLS.** `?sslmode=` after a URL: `disable`; `prefer`, TLS when the
  server has it; `require`, TLS or no connection; `verify-full`, that
  with the server's certificate checked for its name against Mozilla's
  roots. Only `verify-full` knows who the server is. It is TLS 1.3, the
  platform's (`x/net/tls13`). Nothing said is `prefer`. Over TLS a
  MySQL server may be given the whole password, which
  `caching_sha2_password` asks for when it has not the password cached.
- **Files.** `lang.xon` declares the grammar, so x-lang's tools colour a
  `.sql` file with it.

Anything else is refused by name (`Not implemented Error: the type BLOB`) and not
answered differently.

## Planned

In this order:

1. DuckDB's friendlier forms: `unnest` and the rest of the list
   functions; a CSV's separator and its other options; Parquet.
2. The prompt: coloured values in a result, paging a long one, a help
   topic for every function, `-f FILE` and statements on standard input.
3. The servers the rest of the way: a certificate authority of one's own for
   `verify-full`; a password asked for at the prompt; the server's tables
   and columns in `.tables`, `.schema` and Tab; a query cancelled with
   ctrl-c.

## Tests

    make test       # the spec suite
    make check      # the suite against tests/contract/known-failures.txt

The specs under `tests/specs/` take their expected output from DuckDB
itself (`duckdb -no-agent -c`), version 2.0.0, except where a case says
it differs and why. The two wire protocols' specs need no server: the
bytes of both sides are spelled in the cases.

    X=/path/to/x.sh sh tests/oracle/postgres.sh
    X=/path/to/x.sh sh tests/oracle/mariadb.sh

run the drivers against a real PostgreSQL and a real MariaDB, each one
the script starts in a scratch directory with a user for each way of
signing in, and stops again. They need the servers' programs (`PG_BIN`
and `MY_BIN` name their directories) and are not part of `make check`.
No script runs against Oracle's MySQL.

## Differences from DuckDB

- A parser error names the place in one line; DuckDB's second line, the
  statement with a caret under the place, is not built.
- A statement that stops short is `syntax error at end of input`; DuckDB
  names the last token it read.
- Every row of a result is shown; DuckDB cuts a long one to forty rows.
- `//` and `%` take integers only; DuckDB's `//` on a decimal or a double
  is its `/`.
- A time's minutes and seconds past 59 are not refused.
- A time zone is one the system has a file for; DuckDB carries its own.
  `strftime` has no `%Z`, and there is no TIME WITH TIME ZONE.
- `round` takes one argument; `LIKE` has no `ESCAPE`; `ILIKE` folds
  ASCII letters only.
- Groups come in the order their keys first appear; DuckDB promises no
  order.
- A file is read whole into memory, and its types are found from every
  row: it is for files of thousands of rows, not millions. A CSV is
  separated by commas only. A JSON value that is a list or an object is
  refused.
- `USING` and `NATURAL` are not built for RIGHT and FULL joins, where
  DuckDB shows the shared column as whichever side has a row.
- A join compares every pair of rows, and a subquery is run again for
  every row it is asked of, whether or not it reads that row.
- A subquery's heading is the statement spelled back, as DuckDB's is, but
  not in every detail of its spelling.
- A table lasts as long as the process: there is no database file.
- A division by zero is an error, as in DuckDB 2.0, without its hint
  about `TRY` and `error_on_division_by_zero`.

## Install

    make install    # into <share>/langs/sql, where `x -l sql` looks

<p align="center"><img src="docs/bitwise-mark.svg" alt="Bitwise" width="96"></p>

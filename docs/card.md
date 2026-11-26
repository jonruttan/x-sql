# x-sql card

## Run

```sh
x -l sql                                  # a prompt; a statement ends at ;
x -l sql -- -c "SQL"                      # run and exit
x -l sql -f FILE.sql                      # a file of statements
echo "SELECT 42;" | x -l sql              # statements piped in
x -l sql -- FILE.sqlite3                  # the prompt, on a SQLite file
x -l sql -- postgres://USER@HOST/DB       # on a PostgreSQL server
x -l sql -- mysql://USER@HOST/DB          # on a MySQL or MariaDB server
x -l sql -f FILE.sql -- postgres://USER@HOST/DB
x -l sql -- -c "SELECT 1 + 2 AS three" | sed -n 5p -> │     3 │
echo "SELECT 42 AS answer;" | x -l sql | sed -n 5p -> │     42 │
```

```text
┌───────┐
│ three │
│ int32 │
├───────┤
│     3 │
└───────┘
```

```sql
SELECT 1 + 2 AS three;                                        -- -> 3
SELECT 42, 'text', true, NULL;    -- -> 42 | text | true | NULL
```

| On this page           | Is                                               |
|------------------------|--------------------------------------------------|
| a result               | DuckDB's box: the names, the types, the rows     |
| after `-- ->`          | a row of the box, ` \| ` between its values      |
| a program              | run as `x -l sql -f FILE`, from the project's root |
| the first error        | ends a file's run, with status 1                 |

## Values

```sql
SELECT typeof(42), typeof(9999999999);         -- -> INTEGER | BIGINT
SELECT typeof(3.14), typeof(1e3);              -- -> DECIMAL(3,2) | DOUBLE
SELECT typeof('a'), typeof(true);              -- -> VARCHAR | BOOLEAN
SELECT typeof(DATE '2026-01-31'), typeof([1, 2]);   -- -> DATE | INTEGER[]
SELECT CAST('42' AS INTEGER), 42::VARCHAR;     -- -> 42 | 42
SELECT 3.7::INTEGER, 2.5::INTEGER;             -- -> 4 | 3
```

| Type                               | Holds                                 |
|------------------------------------|---------------------------------------|
| `TINYINT` `SMALLINT` `INTEGER` `BIGINT` `HUGEINT` | integers, 8 to 128 bits |
| `UTINYINT` to `UHUGEINT`           | the unsigned ones                     |
| `DECIMAL(W,S)`                     | exact: W digits, S after the point    |
| `DOUBLE` `REAL`                    | 64-bit and 32-bit floating point      |
| `VARCHAR` `BLOB` `BOOLEAN`         | text; bytes; true or false            |
| `DATE` `TIME` `TIMESTAMP` `INTERVAL` | a day; a time; a moment; a span     |
| `TIMESTAMPTZ`                      | a moment, shown on the session's clock |
| `T[]` `STRUCT(a T, ...)`           | a list; a struct                      |
| `NULL`                             | no value                              |
| `CAST(x AS T)` `x::T`              | x as a T                              |

## Operators

```sql
SELECT 7 / 2, 7 // 2, 7 % 2, 2 * 3.5;          -- -> 3.5 | 3 | 1 | 7.0
SELECT 'a' || 'b', 1 = 1, 1 <> 2;              -- -> ab | true | true
SELECT NULL IS NULL, NULL = NULL;              -- -> true | NULL
SELECT true AND NULL, false AND NULL;          -- -> NULL | false
SELECT true OR NULL, NOT true;                 -- -> true | false
SELECT 3 IN (1, 2, 3), 5 BETWEEN 1 AND 9;      -- -> true | true
SELECT 'hello' LIKE 'h%', 'Hello' ILIKE 'h_llo';    -- -> true | true
SELECT CASE WHEN 2 > 1 THEN 'yes' ELSE 'no' END;    -- -> yes
SELECT coalesce(NULL, 'x'), nullif(1, 1);      -- -> x | NULL
SELECT greatest(1, 5, 3), least(1, 5, 3);      -- -> 5 | 1
```

| Operator                           | Is                                    |
|------------------------------------|---------------------------------------|
| `+` `-` `*`                        | in the wider type; overflow an error  |
| `/`                                | a DOUBLE                              |
| `//` `%`                           | integer division; its remainder       |
| `=` `==` `<>` `!=` `<` `<=` `>` `>=` | comparisons, NULL when either is    |
| `AND` `OR` `NOT`                   | in three values: true, false, NULL    |
| `IS NULL` `IS NOT NULL`            | never NULL                            |
| `\|\|`                             | text joined                           |
| `IN (...)` `BETWEEN a AND b`       | one of; from a to b                   |
| `LIKE` `ILIKE`                     | `%` any run, `_` one character        |
| `CASE WHEN c THEN a ELSE b END`    | a choice; `CASE x WHEN v THEN ...` too |

## Functions

```sql
SELECT upper('abc'), length('héllo');          -- -> ABC | 5
SELECT substring('hello', 2, 3), left('hello', 2);  -- -> ell | he
SELECT replace('aXa', 'X', '-'), reverse('abc');    -- -> a-a | cba
SELECT trim('  a  '), concat('a', 1);          -- -> a | a1
SELECT contains('abc', 'b');                   -- -> true
SELECT abs(-3), round(2.5), floor(2.7), ceil(2.1);  -- -> 3 | 3 | 2 | 3
SELECT sqrt(16), power(2, 10);                 -- -> 4.0 | 1024.0
```

| Kind                 | Functions                                           |
|----------------------|-----------------------------------------------------|
| text                 | `lower` `upper` `length` `trim` `ltrim` `rtrim`     |
| text                 | `substring` `left` `right` `replace` `reverse`      |
| text                 | `concat` `starts_with` `contains` `string_split`    |
| numbers              | `abs` `floor` `ceil` `round` `sqrt` `power`         |
| choices              | `coalesce` `ifnull` `nullif` `greatest` `least`     |
| `.help NAME`         | says what a function does                           |

## Tables

```sql
CREATE TABLE t (id INTEGER, name VARCHAR, score DOUBLE);
INSERT INTO t VALUES (1, 'Ada', 9.5), (2, 'Grace', 7), (3, 'Lin', NULL);
SELECT * FROM t WHERE score > 8;               -- -> 1 | Ada | 9.5
SELECT name FROM t ORDER BY score DESC NULLS LAST LIMIT 2;    -- -> Ada
                                               -- -> Grace
UPDATE t SET score = 8 WHERE id = 3;
DELETE FROM t WHERE id = 2;
SELECT id, score FROM t;                       -- -> 1 | 9.5
                                               -- -> 3 | 8.0
SELECT * EXCLUDE (score) FROM t WHERE id = 3;  -- -> 3 | Lin
.tables                                        -- -> t
DROP TABLE t;
```

| Statement                          | Does                                  |
|------------------------------------|---------------------------------------|
| `CREATE TABLE t (c T, ...)`        | a table, in memory for the process    |
| `CREATE TABLE t AS SELECT ...`     | one made of a result                  |
| `CREATE OR REPLACE TABLE` `IF NOT EXISTS` | over an old one; only when new |
| `INSERT INTO t VALUES (...), (...)` | rows; `INSERT INTO t SELECT ...` too |
| `UPDATE t SET c = x WHERE ...`     | change rows                           |
| `DELETE FROM t WHERE ...`          | remove rows                           |
| `DROP TABLE t` `DROP TABLE IF EXISTS t` | forget it                        |
| `SELECT DISTINCT` `*` `t.*`        | the columns                           |
| `* EXCLUDE (c)` `* REPLACE (x AS c)` `* RENAME (c AS n)` | a star, changed |
| `WHERE` `ORDER BY c DESC NULLS LAST` | which rows; in what order           |
| `LIMIT n` `OFFSET n`               | how many; after how many              |
| `FROM t` `FROM t SELECT ...`       | DuckDB's order                        |

## Joins and sets

```sql
CREATE TABLE t AS SELECT 1 AS id, 'Ada' AS name UNION ALL SELECT 3, 'Lin';
CREATE TABLE u AS SELECT 1 AS id, 'x' AS tag UNION ALL SELECT 4, 'y';
SELECT t.name, u.tag FROM t JOIN u ON t.id = u.id;            -- -> Ada | x
SELECT name, tag FROM t LEFT JOIN u USING (id) ORDER BY id;   -- -> Ada | x
                                                              -- -> Lin | NULL
SELECT id FROM t EXCEPT SELECT id FROM u;                     -- -> 3
SELECT count(*) FROM (SELECT id FROM t UNION SELECT id FROM u);    -- -> 3
SELECT name FROM t WHERE id IN (SELECT id FROM u);            -- -> Ada
WITH big AS (SELECT * FROM t WHERE id > 1) SELECT name FROM big;   -- -> Lin
WITH RECURSIVE n(i) AS (
  SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 5)
SELECT sum(i) FROM n;                                         -- -> 15
```

| Form                               | Is                                    |
|------------------------------------|---------------------------------------|
| `JOIN ... ON` `LEFT` `RIGHT` `FULL` `CROSS` | joins; tables after commas too |
| `JOIN ... USING (c)` `NATURAL JOIN` | inner and left, the shared column once |
| `UNION` `INTERSECT` `EXCEPT`, each with `ALL` | set operations              |
| `(SELECT ...)`                     | one value, or a table of a `FROM`     |
| `IN (SELECT ...)` `EXISTS (SELECT ...)` | a test against a result          |
| `WITH name AS (...)`               | a named result                        |
| `WITH RECURSIVE`                   | one that reads itself until none is new |

## Groups and windows

```sql
CREATE TABLE t AS SELECT 1 AS id, 9.5 AS score
  UNION ALL SELECT 2, 7 UNION ALL SELECT 3, NULL;
SELECT count(*), sum(score), max(id) FROM t;                  -- -> 3 | 16.5 | 3
SELECT score IS NULL AS missing, count(*) FROM t GROUP BY ALL;  -- -> false | 2
                                                              -- -> true | 1
SELECT id FROM t GROUP BY id HAVING sum(score) > 8;           -- -> 1
SELECT id, row_number() OVER (ORDER BY id DESC) FROM t WHERE id < 3
  ORDER BY id;                                                -- -> 1 | 2
                                                              -- -> 2 | 1
SELECT id FROM t QUALIFY row_number() OVER (ORDER BY id) = 2;      -- -> 2
```

| Form                               | Is                                    |
|------------------------------------|---------------------------------------|
| `count` `sum` `avg` `min` `max`    | over a group; `count(DISTINCT c)`     |
| `list(c)` `array_agg(c)`           | a group as a list                     |
| `GROUP BY c` `GROUP BY 1` `GROUP BY ALL` | an expression; a place; all  |
| `HAVING`                           | which groups                          |
| `f() OVER (PARTITION BY a ORDER BY b)` | a window                          |
| `row_number` `rank` `dense_rank` `ntile` | a row's place in its window     |
| `lag` `lead` `first_value` `last_value` `nth_value` | another row's value |
| `ROWS` `RANGE` `GROUPS` `BETWEEN ... AND ...` | a frame                    |
| `WINDOW w AS (...)` `QUALIFY`      | a named window; rows kept by one      |

## Dates

```sql
SELECT DATE '2026-01-31' + 1;                  -- -> 2026-02-01
SELECT DATE '2026-01-31' + INTERVAL 1 MONTH;   -- -> 2026-02-28 00:00:00
SELECT year(DATE '2026-11-25');                -- -> 2026
SELECT dayname(DATE '2026-11-25');             -- -> Wednesday
SELECT date_diff('day', DATE '2026-01-01', DATE '2026-11-25');     -- -> 328
SELECT date_trunc('month', DATE '2026-11-25'); -- -> 2026-11-01 00:00:00
SELECT strftime(TIMESTAMP '2026-11-25 14:30:00', '%Y/%m/%d %H:%M');
                                               -- -> 2026/11/25 14:30
```

| Function                           | Is                                    |
|------------------------------------|---------------------------------------|
| `year` `month` `day` `hour` `minute` `second` | a part                     |
| `quarter` `dayofweek` `dayofyear` `dayname` `monthname` | more parts       |
| `date_part('p', d)` `EXTRACT(p FROM d)` | a part, by name                  |
| `date_trunc('p', d)` `last_day(d)` | a part's start; the month's last day |
| `date_diff('p', a, b)`             | parts from a to b                     |
| `make_date(y, m, d)` `strftime(d, 'F')` | a date made; one written out     |
| `now()` `current_date` `today()`   | this moment; this day                 |
| `SET TimeZone = 'Europe/Paris'`    | the session's zone                    |
| `ts AT TIME ZONE 'Z'`              | a timestamp on a zone's clock         |

## Lists and structs

```sql
SELECT [1, 2, 3][2], len([1, 2, 3]), [1, 2, 3][2:3];  -- -> 2 | 3 | [2, 3]
SELECT {'a': 1, 'b': 'x'}.b, list_sum([1, 2, 3]);             -- -> x | 6
SELECT [x * 2 for x in [1, 2, 3] if x > 1];                   -- -> [4, 6]
SELECT list_transform([1, 2], lambda x: x + 1);               -- -> [2, 3]
SELECT list_filter([1, 2, 3], lambda x: x > 1);               -- -> [2, 3]
SELECT range(3), string_split('a,b', ',');     -- -> [0, 1, 2] | [a, b]
SELECT list_contains([1, 2], 2);               -- -> true
SELECT unnest([10, 20]);                       -- -> 10
                                               -- -> 20
```

| Form                               | Is                                    |
|------------------------------------|---------------------------------------|
| `[1, 2, 3]` `{'a': 1, 'b': 'x'}`   | a list; a struct                      |
| `l[2]` `l[-1]` `l[2:3]`            | an element, from 1; the last; a run   |
| `s.a` `s['a']`                     | a field                               |
| `len` `list_contains` `list_position` `list_concat` | about a list         |
| `list_sort` `list_reverse` `list_distinct` `flatten` | a list, changed     |
| `list_sum` `list_min` `list_max` `list_avg` | over its elements            |
| `list_transform(l, lambda x: ...)` | each element changed                  |
| `list_filter` `list_reduce`        | the ones kept; all folded to one      |
| `[x * 2 for x in l if x > 1]`      | a list comprehension                  |
| `unnest(l)`                        | a row for each element                |
| `range(n)` `generate_series(a, b)` | lists of numbers                      |

## Files

```sql
SELECT name, score FROM 'tests/fixtures/people.csv' WHERE active;
                                               -- -> Ada | 9.5
                                               -- -> Lin "Q" Wu | NULL
SELECT count(*) FROM read_csv('tests/fixtures/semi.csv', delim = ';');  -- -> 2
SELECT name FROM 'tests/fixtures/people.json' WHERE id = 2;   -- -> Grace
ATTACH 'tests/fixtures/shop.sqlite3' AS shop;
SELECT count(*) FROM shop.customers;           -- -> 5
SELECT count(*) FROM sqlite_scan('tests/fixtures/shop.sqlite3', 'orders');
                                               -- -> 4
DETACH shop;
```

| Form                               | Is                                    |
|------------------------------------|---------------------------------------|
| `FROM 'f.csv'` `FROM 'f.json'`     | a file as a table, its types found    |
| `read_csv('f', delim = ';', header = false)` | with options; `read_json` too |
| `ATTACH 'f.db' AS s` `DETACH s`    | a SQLite file's tables, as `s.table`  |
| `sqlite_scan('f.db', 'table')`     | one of its tables, nothing attached   |
| `COPY t TO 'f.csv'` `COPY (SELECT ...) TO 'f'` | write a file              |
| `COPY t FROM 'f.csv'`              | read one into a table                 |
| `(FORMAT json, HEADER, DELIMITER ';')` | `COPY`'s options                  |

## Prompt

| At the prompt                      | Does                                  |
|------------------------------------|---------------------------------------|
| `.help` `.help TOPIC` `.help NAME` | the help; a topic; a function         |
| `.tables` `.schema [TABLE]`        | the tables; how one was made          |
| `.open FILE`                       | a SQLite file, its tables by bare name |
| `.connect URL` `.disconnect`       | a server; back to the engine here     |
| `.maxrows N`                       | the most rows a terminal is shown (40) |
| `.quit` `.exit`                    | leave                                 |
| Tab                                | complete a word, a table or a column  |
| `?sslmode=` on a URL               | TLS: `prefer`, `require`, `verify-full` |

## Differs

```sql
SELECT CAST('x' AS UUID);            -- -> Not implemented Error: the type UUID
```

```sql
SELECT 1 +;                 -- -> Parser Error: syntax error at or near ";"
```

| Here                                        | In DuckDB                     |
|---------------------------------------------|-------------------------------|
| what is not built is refused by name        | built                         |
| a parser error is one line                  | two, a caret under the place  |
| `//` and `%` take integers only             | decimals and doubles too      |
| `round` takes one argument                  | a count of places too         |
| `LIKE` has no `ESCAPE`; `ILIKE` folds ASCII only | both                     |
| groups come in the order their keys appear  | no order promised             |
| a table lasts as long as the process        | a database file               |
| a file is read whole into memory            | streamed                      |
| `USING` and `NATURAL` on inner and left joins | on right and full too       |
| a time zone is one the system has a file for | its own                      |

## More

| Where                          | What                                     |
|--------------------------------|------------------------------------------|
| `.help` at the prompt          | the topics, and every function           |
| `README.md`                    | what is built, planned, and each difference |
| `tests/specs/`                 | each form, held to DuckDB 2.0.0          |
| `tests/card-run.sh`            | runs a program of this page              |

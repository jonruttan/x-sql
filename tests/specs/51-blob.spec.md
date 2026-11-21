The BLOB type (`lib/sql/eval.x`), and what of a SQLite file needs it or a
statement run: its BLOB columns and its views (`lib/sql/sqlite.x`,
`lib/sql/exec.x`).

Expected output is DuckDB 2.0.0's own with its sqlite extension, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## a BLOB

### text cast to a BLOB: a character is its byte, and \x with two digits a byte

```x
(sql-files "SELECT 'ab\\x00\\xFF'::BLOB AS b, typeof('a'::BLOB) AS t")
```
---
```output
┌────────────┬─────────┐
│     b      │    t    │
│    blob    │ varchar │
├────────────┼─────────┤
│ ab\x00\xFF │ BLOB    │
└────────────┴─────────┘
```

### a byte that is no plain character is shown by its digits, and so are the backslash and both quotes

```x
(sql-files "SELECT '\\x5C\\x27\\x22~ \\x7F'::BLOB AS b")
```
---
```output
┌────────────────────┐
│         b          │
│        blob        │
├────────────────────┤
│ \x5C\x27\x22~ \x7F │
└────────────────────┘
```

### BYTEA, BINARY and VARBINARY are its other names

```x
(sql-files "SELECT typeof('a'::BYTEA) AS a, typeof('a'::BINARY) AS b, typeof(CAST('a' AS VARBINARY)) AS c")
```
---
```output
┌─────────┬─────────┬─────────┐
│    a    │    b    │    c    │
│ varchar │ varchar │ varchar │
├─────────┼─────────┼─────────┤
│ BLOB    │ BLOB    │ BLOB    │
└─────────┴─────────┴─────────┘
```

### cast to text it is what it is shown as

```x
(sql-files "SELECT '\\x00a'::BLOB::VARCHAR AS t, typeof('\\x00a'::BLOB::VARCHAR) AS type")
```
---
```output
┌─────────┬─────────┐
│    t    │  type   │
│ varchar │ varchar │
├─────────┼─────────┤
│ \x00a   │ VARCHAR │
└─────────┴─────────┘
```

### BLOBs stand in the order of their bytes

```x
(sql-files "SELECT 'ab'::BLOB < 'abc'::BLOB AS shorter, 'b'::BLOB > 'abc'::BLOB AS later, '\\xFF'::BLOB > 'a'::BLOB AS high, '\\x61'::BLOB = 'a'::BLOB AS same")
```
---
```output
┌─────────┬─────────┬─────────┬─────────┐
│ shorter │  later  │  high   │  same   │
│ boolean │ boolean │ boolean │ boolean │
├─────────┼─────────┼─────────┼─────────┤
│ true    │ true    │ true    │ true    │
└─────────┴─────────┴─────────┴─────────┘
```

### text beside a BLOB is read as one

```x
(sql-files "SELECT 'a'::BLOB = 'a' AS same, 'a'::BLOB < '\\xFF' AS below")
```
---
```output
┌─────────┬─────────┐
│  same   │  below  │
│ boolean │ boolean │
├─────────┼─────────┤
│ true    │ true    │
└─────────┴─────────┘
```

### two BLOBs joined are one

```x
(sql-files "SELECT 'a'::BLOB || '\\x00'::BLOB AS b, typeof('a'::BLOB || 'b'::BLOB) AS t")
```
---
```output
┌───────┬─────────┐
│   b   │    t    │
│ blob  │ varchar │
├───────┼─────────┤
│ a\x00 │ BLOB    │
└───────┴─────────┘
```

### octet_length is how many bytes

```x
(sql-files "SELECT octet_length('a\\x00\\xFF'::BLOB) AS n, octet_length(''::BLOB) AS none, octet_length(NULL::BLOB) AS nothing")
```
---
```output
┌───────┬───────┬─────────┐
│   n   │ none  │ nothing │
│ int64 │ int64 │  int64  │
├───────┼───────┼─────────┤
│     3 │     0 │    NULL │
└───────┴───────┴─────────┘
```

### hex is the bytes as digits, of a BLOB or of text

```x
(sql-files "SELECT hex('\\x00\\xff'::BLOB) AS b, hex('ab') AS t")
```
---
```output
┌─────────┬─────────┐
│    b    │    t    │
│ varchar │ varchar │
├─────────┼─────────┤
│ 00FF    │ 6162    │
└─────────┴─────────┘
```

### unhex and from_hex are the BLOB digits say, a lone first digit a byte

```x
(sql-files "SELECT unhex('6162') AS a, from_hex('4a') AS b, unhex('616') AS c, typeof(unhex('61')) AS t")
```
---
```output
┌──────┬──────┬──────────┬─────────┐
│  a   │  b   │    c     │    t    │
│ blob │ blob │   blob   │ varchar │
├──────┼──────┼──────────┼─────────┤
│ ab   │ J    │ \x06\x16 │ BLOB    │
└──────┴──────┴──────────┴─────────┘
```

### encode is text as the BLOB of its bytes

```x
(sql-files "SELECT encode('é') AS b, hex(encode('é')) AS h")
```
---
```output
┌──────────┬─────────┐
│    b     │    h    │
│   blob   │ varchar │
├──────────┼─────────┤
│ \xC3\xA9 │ C3A9    │
└──────────┴─────────┘
```

### a column of BLOBs: kept, ordered, grouped

```x
(sql-files "CREATE OR REPLACE TABLE b (a BLOB); INSERT INTO b VALUES ('ab'), ('\\x00'), ('ab'), (NULL); SELECT a, count(*) AS n FROM b GROUP BY a ORDER BY a")
```
---
```output
┌──────┬───────┐
│  a   │   n   │
│ blob │ int64 │
├──────┼───────┤
│ \x00 │     1 │
│ ab   │     2 │
│ NULL │     1 │
└──────┴───────┘
```

### DISTINCT, min and max

```x
(sql-files "CREATE OR REPLACE TABLE b (a BLOB); INSERT INTO b VALUES ('ab'), ('\\x00'), ('ab'), (NULL); SELECT count(DISTINCT a) AS n, min(a) AS least, max(a) AS most FROM b")
```
---
```output
┌───────┬───────┬──────┐
│   n   │ least │ most │
│ int64 │ blob  │ blob │
├───────┼───────┼──────┤
│     2 │ \x00  │ ab   │
└───────┴───────┴──────┘
```

### a BLOB in a list

```x
(sql-files "SELECT ['a'::BLOB, '\\x01'::BLOB] AS l")
```
---
```output
┌──────────────┐
│      l       │
│    blob[]    │
├──────────────┤
│ [a, '\\x01'] │
└──────────────┘
```

## BLOB errors

### a character above 127

```x
(sql-files "SELECT 'é'::BLOB")
```
---
```output
Conversion Error: Invalid byte encountered in STRING -> BLOB conversion of string "é". All non-ascii characters must be escaped with hex codes (e.g. \xAA)
```

### a backslash with no digits after it

```x
(sql-files "SELECT 'a\\x'::BLOB")
```
---
```output
Conversion Error: Invalid hex escape code encountered in string -> blob conversion of string "a\x": unterminated escape code at end of blob
```

### digits that are none

```x
(sql-files "SELECT '\\xZZ'::BLOB")
```
---
```output
Conversion Error: Invalid hex escape code encountered in string -> blob conversion of string "\xZZ": \xZZ
```

### a number is no BLOB

```x
(sql-files "SELECT 1::BLOB")
```
---
```output
Conversion Error: Unimplemented type for cast (INTEGER -> BLOB)
```

### and a BLOB no number

```x
(sql-files "SELECT 'a'::BLOB::INTEGER")
```
---
```output
Conversion Error: Unimplemented type for cast (BLOB -> INTEGER)
```

### unhex of what is no digit

```x
(sql-files "SELECT unhex('zz')")
```
---
```output
Invalid Input Error: Invalid input for hex digit: z
```

## a BLOB of a SQLite file

### a BLOB column: no bytes, a zero byte, bytes above 127, a NULL; a text and a number kept in it are the bytes they are written with

```x
(sql-files "SELECT * FROM sqlite_scan('{F}shop.sqlite3', 'files') ORDER BY id")
```
---
```output
┌───────┬──────────────────┬──────────────────────────┐
│  id   │       name       │           body           │
│ int64 │     varchar      │           blob           │
├───────┼──────────────────┼──────────────────────────┤
│     1 │ empty            │                          │
│     2 │ text             │ hello                    │
│     3 │ bytes            │ \x00\xFF\x10\x27\x5C\x22 │
│     4 │ none             │ NULL                     │
│     5 │ kept as text     │ plain                    │
│     6 │ kept as a number │ 42                       │
└───────┴──────────────────┴──────────────────────────┘
```

### its type, its bytes counted and as digits

```x
(sql-files "SELECT typeof(body) AS t, octet_length(body) AS n, hex(body) AS h FROM sqlite_scan('{F}shop.sqlite3', 'files') ORDER BY id")
```
---
```output
┌─────────┬───────┬──────────────┐
│    t    │   n   │      h       │
│ varchar │ int64 │   varchar    │
├─────────┼───────┼──────────────┤
│ BLOB    │     0 │              │
│ BLOB    │     5 │ 68656C6C6F   │
│ BLOB    │     6 │ 00FF10275C22 │
│ BLOB    │  NULL │ NULL         │
│ BLOB    │     5 │ 706C61696E   │
│ BLOB    │     2 │ 3432         │
└─────────┴───────┴──────────────┘
```

### compared, and in order

```x
(sql-files "SELECT name FROM sqlite_scan('{F}shop.sqlite3', 'files') WHERE body = 'hello'; SELECT name FROM sqlite_scan('{F}shop.sqlite3', 'files') WHERE body > '\\x00'::BLOB ORDER BY body")
```
---
```output
┌─────────┐
│  name   │
│ varchar │
├─────────┤
│ text    │
└─────────┘
┌──────────────────┐
│       name       │
│     varchar      │
├──────────────────┤
│ bytes            │
│ kept as a number │
│ text             │
│ kept as text     │
└──────────────────┘
```

### columns with no declared type are BLOBs

```x
(sql-files "SELECT a, b, typeof(a) AS t FROM sqlite_scan('{F}shop.sqlite3', 'loose') ORDER BY a")
```
---
```output
┌─────────────────┬─────────────────────┬─────────┐
│        a        │          b          │    t    │
│      blob       │        blob         │ varchar │
├─────────────────┼─────────────────────┼─────────┤
│ -1              │ 127                 │ BLOB    │
│ 0               │ 1                   │ BLOB    │
│ 1               │ one                 │ BLOB    │
│ 128             │ 32767               │ BLOB    │
│ 140737488355328 │ 9223372036854775807 │ BLOB    │
│ 2.5             │ two and a half      │ BLOB    │
│ 2147483648      │ 140737488355327     │ BLOB    │
│ 32768           │ 8388607             │ BLOB    │
│ 8388608         │ 2147483647          │ BLOB    │
│ three           │ 3                   │ BLOB    │
│ NULL            │ NULL                │ BLOB    │
└─────────────────┴─────────────────────┴─────────┘
  11 rows                               3 columns
```

### attached

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT name, body FROM shop.files WHERE body IS NOT NULL ORDER BY body DESC LIMIT 2")
```
---
```output
┌──────────────┬───────┐
│     name     │ body  │
│   varchar    │ blob  │
├──────────────┼───────┤
│ kept as text │ plain │
│ text         │ hello │
└──────────────┴───────┘
```

## a view of a SQLite file

### a view is the rows its statement selects from the file's tables

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'big_spenders')")
```
---
```output
┌───────────┐
│   name    │
│  varchar  │
├───────────┤
│ Ida       │
│ Åsa Öberg │
└───────────┘
```

### attached, under its name or an alias

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT big_spenders.name FROM shop.big_spenders ORDER BY 1; SELECT v.name FROM shop.big_spenders v WHERE v.name LIKE 'I%'")
```
---
```output
┌───────────┐
│   name    │
│  varchar  │
├───────────┤
│ Ida       │
│ Åsa Öberg │
└───────────┘
┌─────────┐
│  name   │
│ varchar │
├─────────┤
│ Ida     │
└─────────┘
```

### a view that names its columns, over a join and groups

DuckDB hands a view to SQLite's own engine and reads every column the view computes as a BLOB. x-sql runs the view's statement itself, so its columns have the types of what they compute; the output here is DuckDB's for the view's statement over the attached tables.

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT * FROM shop.order_totals ORDER BY customer")
```
---
```output
┌───────────┬────────┬────────┐
│ customer  │ orders │ pieces │
│  varchar  │ int64  │ int128 │
├───────────┼────────┼────────┤
│ Ida       │      2 │      7 │
│ Zoë       │      1 │      1 │
│ Åsa Öberg │      1 │      2 │
└───────────┴────────┴────────┘
```

### a view of a view

DuckDB hands a view to SQLite's own engine and reads every column the view computes as a BLOB. x-sql runs the view's statement itself, so its columns have the types of what they compute; the output here is DuckDB's for the view's statement over the attached tables.

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'shouted') ORDER BY loud")
```
---
```output
┌───────────┐
│   loud    │
│  varchar  │
├───────────┤
│ IDA       │
│ ÅSA ÖBERG │
└───────────┘
```

### a view joined to a table

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT c.id, v.name FROM shop.big_spenders v JOIN shop.customers c ON c.name = v.name ORDER BY c.id")
```
---
```output
┌───────┬───────────┐
│  id   │   name    │
│ int64 │  varchar  │
├───────┼───────────┤
│     1 │ Ida       │
│     5 │ Åsa Öberg │
└───────┴───────────┘
```

### the tables a view names are the file's, whatever the session has of the name

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; CREATE OR REPLACE TABLE customers AS SELECT 'mine' AS name, 500 AS balance; WITH orders AS (SELECT 1) SELECT * FROM shop.big_spenders ORDER BY name; DROP TABLE customers")
```
---
```output
┌───────────┐
│   name    │
│  varchar  │
├───────────┤
│ Ida       │
│ Åsa Öberg │
└───────────┘
```

### .schema shows a view as the statement the file keeps

```x
(%seq (sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; DROP TABLE IF EXISTS vips") (sql-eval-line ".schema shop.big_spenders"))
```
---
```output
CREATE VIEW big_spenders AS SELECT name FROM customers WHERE balance > 100;
```

A table of a SQLite database file (`lib/sql/sqlite.x`), read with
`sqlite_scan('file', 'table')` as DuckDB's sqlite extension reads one.
The file is `tests/fixtures/shop.sqlite3`, which
`tests/fixtures/make-shop.sh` makes.

Expected output is DuckDB 2.0.0's own with its sqlite extension, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## sqlite tables

### a table of a SQLite file: its columns in their declared types as DuckDB reads them, NULLs, an empty text, and text of more than one byte a letter

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'customers')")
```
---
```output
┌───────┬───────────┬──────────────────┬────────────┬───────┬──────────┐
│  id   │   name    │      email       │   joined   │  vip  │ balance  │
│ int64 │  varchar  │     varchar      │    date    │ int64 │  double  │
├───────┼───────────┼──────────────────┼────────────┼───────┼──────────┤
│     1 │ Ida       │ ida@example.com  │ 2024-03-04 │     1 │    120.5 │
│     2 │ Bo        │ NULL             │ 2023-11-30 │     0 │      0.0 │
│     3 │ Zoë       │ zoe@example.com  │ NULL       │     1 │   -15.25 │
│     4 │           │ none@example.com │ 2025-01-01 │     0 │     NULL │
│     5 │ Åsa Öberg │ asa@example.com  │ 2022-06-15 │     1 │ 99999.99 │
└───────┴───────────┴──────────────────┴────────────┴───────┴──────────┘
```

### the types by name

```x
(sql-files "SELECT typeof(id), typeof(name), typeof(email), typeof(joined), typeof(vip), typeof(balance) FROM sqlite_scan('{F}shop.sqlite3', 'customers') LIMIT 1")
```
---
```output
┌────────────┬────────────────┬───────────────┬────────────────┬─────────────┬─────────────────┐
│ typeof(id) │ typeof("name") │ typeof(email) │ typeof(joined) │ typeof(vip) │ typeof(balance) │
│  varchar   │    varchar     │    varchar    │    varchar     │   varchar   │     varchar     │
├────────────┼────────────────┼───────────────┼────────────────┼─────────────┼─────────────────┤
│ BIGINT     │ VARCHAR        │ VARCHAR       │ DATE           │ BIGINT      │ DOUBLE          │
└────────────┴────────────────┴───────────────┴────────────────┴─────────────┴─────────────────┘
```

### a timestamp, and rows that were deleted are not there

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'orders')")
```
---
```output
┌───────┬─────────────┬─────────────────────┬─────────┐
│  id   │ customer_id │       placed        │  note   │
│ int64 │    int64    │      timestamp      │ varchar │
├───────┼─────────────┼─────────────────────┼─────────┤
│    10 │           1 │ 2025-02-01 09:30:00 │ first   │
│    11 │           1 │ 2025-02-03 17:45:10 │ NULL    │
│    12 │           3 │ 2025-02-04 08:00:00 │ gift    │
│    14 │           5 │ 2025-02-06 23:59:59 │ late    │
└───────┴─────────────┴─────────────────────┴─────────┘
```

### a primary key of two columns

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'order_lines') ORDER BY order_id, sku")
```
---
```output
┌──────────┬─────────┬───────┐
│ order_id │   sku   │  qty  │
│  int64   │ varchar │ int64 │
├──────────┼─────────┼───────┤
│       10 │ A-1     │     1 │
│       10 │ C-3     │     4 │
│       11 │ B-2     │     2 │
│       12 │ C-3     │     1 │
│       14 │ A-1     │     2 │
└──────────┴─────────┴───────┘
```

### queried like any table, under an alias

```x
(sql-files "SELECT c.name, c.balance * 2 AS twice FROM sqlite_scan('{F}shop.sqlite3', 'customers') AS c WHERE c.vip = 1 AND c.joined > DATE '2023-01-01' ORDER BY c.name")
```
---
```output
┌─────────┬────────┐
│  name   │ twice  │
│ varchar │ double │
├─────────┼────────┤
│ Ida     │  241.0 │
└─────────┴────────┘
```

### with no alias its columns are qualified by the function's name

```x
(sql-files "SELECT sqlite_scan.id FROM sqlite_scan('{F}shop.sqlite3', 'customers') ORDER BY 1 LIMIT 2")
```
---
```output
┌───────┐
│  id   │
│ int64 │
├───────┤
│     1 │
│     2 │
└───────┘
```

### two tables of the file joined, and grouped

```x
(sql-files "SELECT c.name, count(*) AS orders FROM sqlite_scan('{F}shop.sqlite3', 'customers') c JOIN sqlite_scan('{F}shop.sqlite3', 'orders') o ON o.customer_id = c.id GROUP BY ALL ORDER BY 1")
```
---
```output
┌───────────┬────────┐
│   name    │ orders │
│  varchar  │ int64  │
├───────────┼────────┤
│ Ida       │      2 │
│ Zoë       │      1 │
│ Åsa Öberg │      1 │
└───────────┴────────┘
```

### a table's name in any case

```x
(sql-files "SELECT count(*) AS n FROM sqlite_scan('{F}shop.sqlite3', 'CUSTOMERS')")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│     5 │
└───────┘
```

## sqlite pages

### a text too long for its page goes on through overflow pages

```x
(sql-files "SELECT id, title, length(body) AS n, left(body, 13) AS head, right(body, 8) AS tail FROM sqlite_scan('{F}shop.sqlite3', 'documents') ORDER BY id")
```
---
```output
┌───────┬─────────┬───────┬────────────────┬──────────┐
│  id   │  title  │   n   │      head      │   tail   │
│ int64 │ varchar │ int64 │    varchar     │ varchar  │
├───────┼─────────┼───────┼────────────────┼──────────┤
│     1 │ short   │    11 │ a few words    │ ew words │
│     2 │ long    │  3491 │ line 1\nline 2 │ line 400 │
└───────┴─────────┴───────┴────────────────┴──────────┘
```

### a table of many rows is a tree of pages, read in the order of its rows

```x
(sql-files "SELECT n, reading, label FROM sqlite_scan('{F}shop.sqlite3', 'measurements') WHERE n IN (1, 2, 199, 200, 399, 400) ORDER BY n")
```
---
```output
┌───────┬─────────┬─────────────┐
│   n   │ reading │    label    │
│ int64 │ double  │   varchar   │
├───────┼─────────┼─────────────┤
│     1 │     0.5 │ reading 1   │
│     2 │     1.0 │ reading 2   │
│   199 │    99.5 │ reading 199 │
│   200 │   100.0 │ reading 200 │
│   399 │   199.5 │ reading 399 │
│   400 │   200.0 │ reading 400 │
└───────┴─────────┴─────────────┘
```

### every row of them has the text it was written with

```x
(sql-files "SELECT count(*) AS wrong FROM sqlite_scan('{F}shop.sqlite3', 'measurements') WHERE label <> 'reading ' || n OR n < 1 OR n > 400")
```
---
```output
┌───────┐
│ wrong │
│ int64 │
├───────┤
│     0 │
└───────┘
```

### and the last hundred are the last hundred

```x
(sql-files "SELECT count(*) AS n, min(n) AS low, max(n) AS high FROM sqlite_scan('{F}shop.sqlite3', 'measurements') WHERE n > 300")
```
---
```output
┌───────┬───────┬───────┐
│   n   │  low  │ high  │
│ int64 │ int64 │ int64 │
├───────┼───────┼───────┤
│   100 │   301 │   400 │
└───────┴───────┴───────┘
```

## sqlite without rowid

### a table made WITHOUT ROWID keeps its rows in an index, in the order of its key

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'products')")
```
---
```output
┌─────────┬─────────┬────────┬───────┐
│   sku   │  title  │ price  │ stock │
│ varchar │ varchar │ double │ int64 │
├─────────┼─────────┼────────┼───────┤
│ A-1     │ Anvil   │   49.5 │     3 │
│ B-2     │ Bellows │   12.0 │     0 │
│ C-3     │ Chisel  │   7.25 │    40 │
└─────────┴─────────┴────────┴───────┘
```

### a key of two columns that are not the table's first: the columns come back in the table's order

```x
(sql-files "SELECT * FROM sqlite_scan('{F}shop.sqlite3', 'shelves') WHERE place <= 4 ORDER BY place")
```
---
```output
┌─────────────────────────────────────────┬───────┬─────────┬───────┐
│                  note                   │ place │   sku   │ held  │
│                 varchar                 │ int64 │ varchar │ int64 │
├─────────────────────────────────────────┼───────┼─────────┼───────┤
│ shelf 1 of the back room, counted twice │     1 │ B-2     │     2 │
│ shelf 2 of the back room, counted twice │     2 │ C-3     │     4 │
│ shelf 3 of the back room, counted twice │     3 │ A-1     │     6 │
│ shelf 4 of the back room, counted twice │     4 │ B-2     │     8 │
└─────────────────────────────────────────┴───────┴─────────┴───────┘
```

### its rows are in the key's order, through the pages of the index

DuckDB reads the rows in this order too; the case has no ORDER BY so that it shows the file's.

```x
(sql-files "SELECT sku, place, held FROM sqlite_scan('{F}shop.sqlite3', 'shelves') LIMIT 5")
```
---
```output
┌─────────┬───────┬───────┐
│   sku   │ place │ held  │
│ varchar │ int64 │ int64 │
├─────────┼───────┼───────┤
│ A-1     │     3 │     6 │
│ A-1     │     6 │    12 │
│ A-1     │     9 │    18 │
│ A-1     │    12 │    24 │
│ A-1     │    15 │    30 │
└─────────┴───────┴───────┘
```

### every row of it

```x
(sql-files "SELECT sku, count(*) AS n, sum(held) AS total, min(place) AS low, max(place) AS high FROM sqlite_scan('{F}shop.sqlite3', 'shelves') GROUP BY sku ORDER BY sku")
```
---
```output
┌─────────┬───────┬────────┬───────┬───────┐
│   sku   │   n   │ total  │  low  │ high  │
│ varchar │ int64 │ int128 │ int64 │ int64 │
├─────────┼───────┼────────┼───────┼───────┤
│ A-1     │    40 │   4920 │     3 │   120 │
│ B-2     │    40 │   4760 │     1 │   118 │
│ C-3     │    40 │   4840 │     2 │   119 │
└─────────┴───────┴────────┴───────┴───────┘
```

## sqlite errors

### a file that is not there

```x
(sql-files "FROM sqlite_scan('nope.sqlite3', 'customers')")
```
---
```output
Invalid Error: Unable to open database "nope.sqlite3": unable to open database file
```

### a file that is no SQLite file

DuckDB says the file is not a database, in SQLite's own words.

```x
(sql-files "FROM sqlite_scan('{F}people.csv', 'customers')")
```
---
```output
Invalid Input Error: the file is not a SQLite database
```

### a table the file has not

DuckDB's own is an internal error; this is what x-sql says of any table there is not.

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'nope')")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

### a view is not read

DuckDB runs the view with SQLite's own engine.

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'big_spenders')")
```
---
```output
Not implemented Error: a view of a SQLite file
```

### columns with no declared type are DuckDB's BLOB, which is not built

```x
(sql-files "FROM sqlite_scan('{F}shop.sqlite3', 'loose')")
```
---
```output
Not implemented Error: the type BLOB
```

CSV and JSON files as tables, and tables written as files.  `sql-files`
is the harness's: a case's statements with `{F}` in them as the bundle's
`tests/fixtures/` and `{S}` as a directory a case may write in.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## files csv

### a file's name in a FROM is a table: its first row the names, each column the type its values are

```x
(sql-files "FROM '{F}people.csv'")
```
---
```output
┌───────┬────────────┬────────┬────────────┬─────────┬───────────────┐
│  id   │    name    │ score  │   joined   │ active  │     note      │
│ int64 │  varchar   │ double │    date    │ boolean │    varchar    │
├───────┼────────────┼────────┼────────────┼─────────┼───────────────┤
│     1 │ Ada        │    9.5 │ 2026-01-31 │ true    │ likes, commas │
│     2 │ Grace      │    7.0 │ 2024-02-29 │ false   │ NULL          │
│     3 │ Lin "Q" Wu │   NULL │ 2025-12-01 │ true    │ plain         │
└───────┴────────────┴────────┴────────────┴─────────┴───────────────┘
```

### with numbers in its first row a file has no names of its own

```x
(sql-files "FROM '{F}plain.csv'")
```
---
```output
┌─────────┬─────────┬─────────┐
│ column0 │ column1 │ column2 │
│  int64  │ double  │ varchar │
├─────────┼─────────┼─────────┤
│       1 │     2.5 │ x       │
│       2 │     3.5 │ y       │
│       3 │    NULL │ z       │
└─────────┴─────────┴─────────┘
```

### a file of nothing but text has its first row for names

```x
(sql-files "FROM '{F}words.csv'")
```
---
```output
┌─────────┬─────────┐
│  city   │ country │
│ varchar │ varchar │
├─────────┼─────────┤
│ Paris   │ France  │
│ Lima    │ Peru    │
└─────────┴─────────┘
```

### a file is queried like any table, under its name or an alias

```x
(sql-files "SELECT people.name, score * 2 AS twice FROM '{F}people.csv' WHERE active ORDER BY id DESC; SELECT p.id FROM '{F}people.csv' p WHERE p.note IS NULL")
```
---
```output
┌────────────┬────────┐
│    name    │ twice  │
│  varchar   │ double │
├────────────┼────────┤
│ Lin "Q" Wu │   NULL │
│ Ada        │   19.0 │
└────────────┴────────┘
┌───────┐
│  id   │
│ int64 │
├───────┤
│     2 │
└───────┘
```

### grouped, and joined to another file

```x
(sql-files "SELECT active, count(*), max(joined) FROM '{F}people.csv' GROUP BY active ORDER BY active; SELECT p.name, w.city FROM '{F}people.csv' p JOIN '{F}words.csv' w ON length(w.city) = p.id + 3 ORDER BY 1")
```
---
```output
┌─────────┬──────────────┬─────────────┐
│ active  │ count_star() │ max(joined) │
│ boolean │    int64     │    date     │
├─────────┼──────────────┼─────────────┤
│ false   │            1 │ 2024-02-29  │
│ true    │            2 │ 2026-01-31  │
└─────────┴──────────────┴─────────────┘
┌─────────┬─────────┐
│  name   │  city   │
│ varchar │ varchar │
├─────────┼─────────┤
│ Ada     │ Lima    │
│ Grace   │ Paris   │
└─────────┴─────────┘
```

### read_csv is the same table

```x
(sql-files "SELECT count(*), sum(score) FROM read_csv('{F}people.csv')")
```
---
```output
┌──────────────┬────────────┐
│ count_star() │ sum(score) │
│    int64     │   double   │
├──────────────┼────────────┤
│            3 │       16.5 │
└──────────────┴────────────┘
```

### a file that is not there

```x
(sql-files "FROM 'nope.csv'")
```
---
```output
IO Error: No files found that match the pattern "nope.csv"
```

## files json

### an array of objects is a table: the keys in the order they first come, a key an object has not NULL

```x
(sql-files "FROM '{F}people.json'")
```
---
```output
┌───────┬────────────┬────────┬─────────┬────────────┬─────────┐
│  id   │    name    │ score  │ active  │   joined   │  extra  │
│ int64 │  varchar   │ double │ boolean │    date    │ varchar │
├───────┼────────────┼────────┼─────────┼────────────┼─────────┤
│     1 │ Ada        │    9.5 │ true    │ 2026-01-31 │ NULL    │
│     2 │ Grace      │    7.0 │ false   │ 2024-02-29 │ x       │
│     3 │ Lin "Q" Wu │   NULL │ true    │ 2025-12-01 │ NULL    │
└───────┴────────────┴────────┴─────────┴────────────┴─────────┘
```

### an object a line

```x
(sql-files "FROM '{F}events.ndjson'; SELECT kind, n FROM read_json('{F}events.ndjson') WHERE ts > '2026-11-17 12:01:00'")
```
---
```output
┌─────────────────────┬─────────┬───────┐
│         ts          │  kind   │   n   │
│      timestamp      │ varchar │ int64 │
├─────────────────────┼─────────┼───────┤
│ 2026-11-17 12:00:00 │ start   │     1 │
│ 2026-11-17 12:05:30 │ stop    │     2 │
└─────────────────────┴─────────┴───────┘
┌─────────┬───────┐
│  kind   │   n   │
│ varchar │ int64 │
├─────────┼───────┤
│ stop    │     2 │
└─────────┴───────┘
```

### a list or an object for a value is not built

DuckDB makes the column a STRUCT or a LIST.

```x
(sql-files "FROM '{F}nested.json'")
```
---
```output
Not implemented Error: a list or an object as a value, in the column "b"
```

## files written

### COPY writes a statement's rows as CSV: a line of names, a field quoted when it must be, a NULL empty

```x
(%seq (sql-files "COPY (SELECT 1 AS a, 'x,y' AS b, NULL AS c, DATE '2026-01-01' AS d, true AS e, 1.50 AS f, 'say \"hi\"' AS g) TO '{S}26-a.csv'") (display (File read-all (Str8 append sql-scratch "26-a.csv"))))
```
---
```output
a,b,c,d,e,f,g
1,"x,y",,2026-01-01,true,1.50,"say ""hi"""
```

### and as JSON, an object a line

```x
(%seq (sql-files "COPY (SELECT 1 AS a, 'x\"y' AS b, NULL AS c, 1.5 AS f, true AS e, DATE '2026-01-01' AS d) TO '{S}26-b.json'") (display (File read-all (Str8 append sql-scratch "26-b.json"))))
```
---
```output
{"a":1,"b":"x\"y","c":null,"f":1.5,"e":true,"d":"2026-01-01"}
```

### a table is written by its name, and read back as it was

```x
(sql-files "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, d DATE); INSERT INTO t VALUES (1, 'one', '2026-01-31'), (2, NULL, NULL); COPY t TO '{S}26-c.csv'; FROM '{S}26-c.csv'")
```
---
```output
┌───────┬─────────┬────────────┐
│   a   │    b    │     d      │
│ int64 │ varchar │    date    │
├───────┼─────────┼────────────┤
│     1 │ one     │ 2026-01-31 │
│     2 │ NULL    │ NULL       │
└───────┴─────────┴────────────┘
```

### HEADER false leaves the names out, and FORMAT names the format whatever the file is called

```x
(sql-files "COPY (SELECT 1 AS a, 'x' AS b) TO '{S}26-d.csv' (HEADER false); FROM '{S}26-d.csv'; COPY (SELECT 1 AS a, 'x' AS b) TO '{S}26-e.txt' (FORMAT json); FROM read_json('{S}26-e.txt')")
```
---
```output
┌─────────┬─────────┐
│ column0 │ column1 │
│  int64  │ varchar │
├─────────┼─────────┤
│       1 │ x       │
└─────────┴─────────┘
┌───────┬─────────┐
│   a   │    b    │
│ int64 │ varchar │
├───────┼─────────┤
│     1 │ x       │
└───────┴─────────┘
```

### COPY ... FROM adds a file's rows to a table, each value cast to its column

```x
(sql-files "CREATE OR REPLACE TABLE t (id BIGINT, name VARCHAR, score DOUBLE, joined DATE, active BOOLEAN, note VARCHAR); COPY t FROM '{F}people.csv'; COPY t FROM '{F}people.csv'; SELECT count(*), max(joined), sum(score) FROM t")
```
---
```output
┌──────────────┬─────────────┬────────────┐
│ count_star() │ max(joined) │ sum(score) │
│    int64     │    date     │   double   │
├──────────────┼─────────────┼────────────┤
│            6 │ 2026-01-31  │       33.0 │
└──────────────┴─────────────┴────────────┘
```

### CREATE TABLE AS from a file

```x
(sql-files "CREATE OR REPLACE TABLE c AS SELECT id, name FROM '{F}people.json' WHERE active; FROM c ORDER BY id")
```
---
```output
┌───────┬────────────┐
│  id   │    name    │
│ int64 │  varchar   │
├───────┼────────────┤
│     1 │ Ada        │
│     3 │ Lin "Q" Wu │
└───────┴────────────┘
```

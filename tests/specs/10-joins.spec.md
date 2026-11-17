More than one table: the joins, and tables listed with commas.  Rows are
sorted wherever DuckDB gives them no order.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## joins inner

### JOIN keeps the pairs of rows its ON is true for

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, b, c FROM t JOIN u ON t.a = u.a ORDER BY 1")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     1 │ x       │ one     │
│     3 │ y       │ three   │
└───────┴─────────┴─────────┘
```

### INNER JOIN is the same

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, c FROM t INNER JOIN u ON t.a = u.a ORDER BY 1")
```
---
```output
┌───────┬─────────┐
│   a   │    c    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ one     │
│     3 │ three   │
└───────┴─────────┘
```

### * is every column of every table, in order

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT * FROM t JOIN u ON t.a = u.a ORDER BY t.a")
```
---
```output
┌───────┬─────────┬───────┬─────────┐
│   a   │    b    │   a   │    c    │
│ int32 │ varchar │ int32 │ varchar │
├───────┼─────────┼───────┼─────────┤
│     1 │ x       │     1 │ one     │
│     3 │ y       │     3 │ three   │
└───────┴─────────┴───────┴─────────┘
```

### t.* is one table's

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT u.*, t.b FROM t JOIN u ON t.a = u.a ORDER BY 1")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    c    │    b    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     1 │ one     │ x       │
│     3 │ three   │ y       │
└───────┴─────────┴─────────┘
```

### ON is any condition

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, u.a FROM t JOIN u ON t.a < u.a AND u.a < 4 ORDER BY 1, 2")
```
---
```output
┌───────┬───────┐
│   a   │   a   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     3 │
│     2 │     3 │
└───────┴───────┘
```

### a table joined to itself, under two aliases

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT x.a, y.a FROM t x JOIN t AS y ON x.a = y.a + 1 ORDER BY 1")
```
---
```output
┌───────┬───────┐
│   a   │   a   │
│ int32 │ int32 │
├───────┼───────┤
│     2 │     1 │
│     3 │     2 │
└───────┴───────┘
```

### three tables

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, u.c, v.b FROM t JOIN u ON t.a = u.a JOIN t v ON v.a = u.a ORDER BY 1")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    c    │    b    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     1 │ one     │ x       │
│     3 │ three   │ y       │
└───────┴─────────┴─────────┘
```

## joins outer

### LEFT JOIN keeps a left row with no match, beside NULLs

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT * FROM t LEFT JOIN u ON t.a = u.a ORDER BY t.a, b")
```
---
```output
┌───────┬─────────┬───────┬─────────┐
│   a   │    b    │   a   │    c    │
│ int32 │ varchar │ int32 │ varchar │
├───────┼─────────┼───────┼─────────┤
│     1 │ x       │     1 │ one     │
│     2 │ x       │  NULL │ NULL    │
│     3 │ y       │     3 │ three   │
│  NULL │ y       │  NULL │ NULL    │
│  NULL │ NULL    │  NULL │ NULL    │
└───────┴─────────┴───────┴─────────┘
```

### RIGHT JOIN keeps a right row with no match

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, u.a, c FROM t RIGHT JOIN u ON t.a = u.a ORDER BY u.a")
```
---
```output
┌───────┬───────┬─────────┐
│   a   │   a   │    c    │
│ int32 │ int32 │ varchar │
├───────┼───────┼─────────┤
│     1 │     1 │ one     │
│     3 │     3 │ three   │
│  NULL │     4 │ four    │
└───────┴───────┴─────────┘
```

### FULL JOIN keeps both

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, u.a FROM t FULL JOIN u ON t.a = u.a ORDER BY 1, 2")
```
---
```output
┌───────┬───────┐
│   a   │   a   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     1 │
│     2 │  NULL │
│     3 │     3 │
│  NULL │     4 │
│  NULL │  NULL │
│  NULL │  NULL │
└───────┴───────┘
```

### OUTER says nothing more

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT count(*) FROM t LEFT OUTER JOIN u ON t.a = u.a; SELECT count(*) FROM t FULL OUTER JOIN u ON t.a = u.a")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            5 │
└──────────────┘
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            6 │
└──────────────┘
```

### WHERE is after the join, so it can ask for the rows with no match

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT t.a, b FROM t LEFT JOIN u ON t.a = u.a WHERE u.a IS NULL ORDER BY t.a, b")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ x       │
│  NULL │ y       │
│  NULL │ NULL    │
└───────┴─────────┘
```

## joins cross

### CROSS JOIN is every pair

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT count(*) FROM t CROSS JOIN u")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│           15 │
└──────────────┘
```

### and so is a comma

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT count(*) FROM t, u; SELECT t.a, c FROM t, u WHERE t.a = u.a ORDER BY 1")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│           15 │
└──────────────┘
┌───────┬─────────┐
│   a   │    c    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ one     │
│     3 │ three   │
└───────┴─────────┘
```

## joins with groups

### a join is grouped like a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT c, count(*), sum(t.a) FROM t JOIN u ON t.a <= u.a GROUP BY c ORDER BY c")
```
---
```output
┌─────────┬──────────────┬──────────┐
│    c    │ count_star() │ sum(t.a) │
│ varchar │    int64     │  int128  │
├─────────┼──────────────┼──────────┤
│ four    │            3 │        6 │
│ one     │            1 │        1 │
│ three   │            3 │        6 │
└─────────┴──────────────┴──────────┘
```

### FROM first

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); FROM t JOIN u ON t.a = u.a SELECT c ORDER BY c")
```
---
```output
┌─────────┐
│    c    │
│ varchar │
├─────────┤
│ one     │
│ three   │
└─────────┘
```

## joins errors

### a name two tables have must say which

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT a FROM t JOIN u ON t.a = u.a")
```
---
```output
Binder Error: Ambiguous reference to column name "a" (use: 't.a' or 'u.a')
```

### a table that is not in the FROM

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT v.a FROM t JOIN u ON t.a = u.a")
```
---
```output
Binder Error: Referenced table "v" not found!
```

### JOIN with no ON

DuckDB names the last token it read, "u".

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (1,'one'),(3,'three'),(4,'four'); SELECT * FROM t JOIN u")
```
---
```output
Parser Error: syntax error at end of input
```

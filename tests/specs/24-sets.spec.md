Two select statements as one: UNION, INTERSECT and EXCEPT.  DuckDB gives
their rows no order, so every case sorts them.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## sets union

### UNION is the rows of both, each once

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t UNION SELECT a FROM u ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
│     4 │
│  NULL │
└───────┘
```

### UNION ALL keeps every row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t UNION ALL SELECT a FROM u ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     2 │
│     2 │
│     3 │
│     3 │
│     4 │
│  NULL │
└───────┘
```

### the names are the first statement's

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a AS n, b AS word FROM t UNION SELECT a, c FROM u ORDER BY n, word")
```
---
```output
┌───────┬─────────┐
│   n   │  word   │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ two     │
│     2 │ y       │
│     3 │ three   │
│     3 │ z       │
│     4 │ four    │
│  NULL │ none    │
└───────┴─────────┘
```

### an ORDER BY and a LIMIT after the last statement are the whole's

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t UNION ALL SELECT a FROM u ORDER BY 1 DESC LIMIT 3; SELECT a FROM t UNION SELECT a FROM u ORDER BY a LIMIT 2 OFFSET 1")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     4 │
│     3 │
│     3 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
└───────┘
```

### three statements

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT 1 AS x UNION SELECT 2 UNION SELECT 1 ORDER BY x; SELECT a FROM t UNION ALL SELECT a FROM t UNION SELECT 9 ORDER BY a")
```
---
```output
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
│     9 │
└───────┘
```

### a column of both sides goes into one type

```x
(sql "SELECT 1 AS x UNION SELECT 2.5 UNION SELECT 3 ORDER BY x; SELECT 1 AS x UNION ALL SELECT 2147483648 ORDER BY x; SELECT 1 AS x UNION SELECT 1e0 ORDER BY x")
```
---
```output
┌───────────────┐
│       x       │
│ decimal(11,1) │
├───────────────┤
│           1.0 │
│           2.5 │
│           3.0 │
└───────────────┘
┌────────────┐
│     x      │
│   int64    │
├────────────┤
│          1 │
│ 2147483648 │
└────────────┘
┌────────┐
│   x    │
│ double │
├────────┤
│    1.0 │
└────────┘
```

### text on either side makes the column text

```x
(sql "SELECT 1 AS x UNION SELECT 'x' ORDER BY x")
```
---
```output
┌─────────┐
│    x    │
│ varchar │
├─────────┤
│ 1       │
│ x       │
└─────────┘
```

### NULL is one row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT NULL UNION SELECT NULL; SELECT a FROM u UNION SELECT NULL ORDER BY a")
```
---
```output
┌────────┐
│  NULL  │
│ "null" │
├────────┤
│ NULL   │
└────────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
│     4 │
│  NULL │
└───────┘
```

## sets intersect and except

### INTERSECT is the rows both have, each once

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t INTERSECT SELECT a FROM u ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
└───────┘
```

### EXCEPT is the rows of the first the second has not

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t EXCEPT SELECT a FROM u ORDER BY a; SELECT a FROM u EXCEPT SELECT a FROM t ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     4 │
│  NULL │
└───────┘
```

### with ALL a row of the second answers for one of the first

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t EXCEPT ALL SELECT a FROM u ORDER BY a; SELECT a FROM t INTERSECT ALL SELECT a FROM u ORDER BY a; SELECT a FROM t INTERSECT ALL SELECT a FROM t ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     2 │
│     3 │
└───────┘
```

### a row is every column together

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a, b FROM t INTERSECT SELECT 2, 'y'; SELECT a, b FROM t EXCEPT SELECT 2, 'y' ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ y       │
└───────┴─────────┘
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     3 │ z       │
└───────┴─────────┘
```

### INTERSECT joins tighter than UNION

```x
(sql "SELECT 1 AS x UNION SELECT 2 INTERSECT SELECT 2 ORDER BY x; SELECT 1 AS x INTERSECT SELECT 2 UNION SELECT 3 ORDER BY x")
```
---
```output
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     3 │
└───────┘
```

### UNION and EXCEPT join left to right

```x
(sql "SELECT 1 AS x UNION SELECT 2 EXCEPT SELECT 1 ORDER BY x; SELECT 1 AS x EXCEPT SELECT 1 UNION SELECT 1 ORDER BY x")
```
---
```output
┌───────┐
│   x   │
│ int32 │
├───────┤
│     2 │
└───────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

## sets elsewhere

### as a table of a FROM

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT x FROM (SELECT a AS x FROM t UNION SELECT a FROM u) ORDER BY x; SELECT count(*) FROM (SELECT a FROM t UNION ALL SELECT a FROM u)")
```
---
```output
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
│     4 │
│  NULL │
└───────┘
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            8 │
└──────────────┘
```

### in a subquery, and after IN

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a FROM t WHERE a IN (SELECT a FROM u EXCEPT SELECT 3) ORDER BY a; SELECT (SELECT max(a) FROM (SELECT a FROM t UNION SELECT a FROM u)) AS top")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     2 │
└───────┘
┌───────┐
│  top  │
│ int32 │
├───────┤
│     4 │
└───────┘
```

### under WITH, and filling a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); WITH w AS (SELECT a FROM t UNION SELECT a FROM u) SELECT count(*) FROM w; CREATE OR REPLACE TABLE c AS SELECT a FROM t INTERSECT SELECT a FROM u; FROM c ORDER BY a")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            5 │
└──────────────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
└───────┘
```

### each side its own WHERE and GROUP BY

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT b AS k, count(*) AS n FROM t GROUP BY b UNION ALL SELECT 'u', count(*) FROM u WHERE a > 2 ORDER BY k")
```
---
```output
┌─────────┬───────┐
│    k    │   n   │
│ varchar │ int64 │
├─────────┼───────┤
│ u       │     2 │
│ x       │     1 │
│ y       │     2 │
│ z       │     1 │
└─────────┴───────┘
```

### sides of unlike widths

```x
(sql "SELECT 1, 2 UNION SELECT 1")
```
---
```output
Binder Error: Set operations can only apply to expressions with the same number of result columns
```

Rows changed and removed, and tables filled from a query: UPDATE, DELETE,
INSERT from a SELECT, and CREATE TABLE AS.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## changes update

### UPDATE sets a column in the rows its WHERE is true for

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); UPDATE t SET b = 'q' WHERE a > 1; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ q       │
│     3 │ q       │
└───────┴─────────┘
```

### with no WHERE it is every row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); UPDATE t SET b = 'q'; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ q       │
│     2 │ q       │
│     3 │ q       │
└───────┴─────────┘
```

### every SET is worked out from the row as it was

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); UPDATE t SET a = a + 1, b = b || a; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ x1      │
│     3 │ y2      │
│     4 │ z3      │
└───────┴─────────┘
```

### a value is cast to its column

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); UPDATE t SET a = '7', b = 5 WHERE a = 1; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ y       │
│     3 │ z       │
│     7 │ 5       │
└───────┴─────────┘
```

### a row whose WHERE is NULL is left

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); UPDATE t SET a = 0 WHERE NULL; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ y       │
│     3 │ z       │
└───────┴─────────┘
```

### a SET may hold a subquery

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); UPDATE t SET a = (SELECT max(a) FROM u) WHERE a = 1; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ y       │
│     3 │ z       │
│     4 │ x       │
└───────┴─────────┘
```

### a column the table does not have

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); UPDATE t SET zz = 1")
```
---
```output
Binder Error: Referenced update column zz not found in table!
```

### a value that does not fit leaves the table as it was

The expectation is written by hand: a failed statement ends a run in DuckDB.

```x
(%seq (sql "CREATE OR REPLACE TABLE t (a INTEGER); INSERT INTO t VALUES (1), (2); UPDATE t SET a = 'x' WHERE a = 2") (sql "FROM t ORDER BY a"))
```
---
```output
Conversion Error: Could not convert string 'x' to INT32
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
```

## changes delete

### DELETE removes the rows its WHERE is true for

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); DELETE FROM t WHERE a = 1 OR b = 'z'; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ y       │
└───────┴─────────┘
```

### with no WHERE it is every row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); DELETE FROM t; FROM t")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
└───────┴─────────┘
      0 rows     
```

### a WHERE may hold a subquery

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); DELETE FROM t WHERE a IN (SELECT a FROM u); FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
└───────┴─────────┘
```

### a table that is not there

```x
(sql "DELETE FROM nope")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

## changes from a query

### INSERT takes the rows of a SELECT

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); INSERT INTO u SELECT a + 10 FROM t; FROM u ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
│     4 │
│    11 │
│    12 │
│    13 │
└───────┘
```

### into columns named, each value cast to its column

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); INSERT INTO t (b, a) SELECT 'n' || a, a * 10 FROM t WHERE a < 3; FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ y       │
│     3 │ z       │
│    10 │ n1      │
│    20 │ n2      │
└───────┴─────────┘
```

### CREATE TABLE AS makes a table of a result, with its names and its types

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE c AS SELECT a, b, a * 1.5 AS p, a > 1 AS big FROM t; FROM c ORDER BY a")
```
---
```output
┌───────┬─────────┬───────────────┬─────────┐
│   a   │    b    │       p       │   big   │
│ int32 │ varchar │ decimal(12,1) │ boolean │
├───────┼─────────┼───────────────┼─────────┤
│     1 │ x       │           1.5 │ false   │
│     2 │ y       │           3.0 │ true    │
│     3 │ z       │           4.5 │ true    │
└───────┴─────────┴───────────────┴─────────┘
```

### the table is a table like any other

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE c AS SELECT a FROM t WHERE a > 1; INSERT INTO c VALUES (9); UPDATE c SET a = a * 2; FROM c ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     4 │
│     6 │
│    18 │
└───────┘
```

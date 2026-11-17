JOIN ... USING and NATURAL JOIN: a join on the columns two tables share,
shown once.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## using

### USING joins on a column both sides have, and * shows it once

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT * FROM t JOIN u USING (a) ORDER BY a")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     2 │ y       │ two     │
│     2 │ y       │ two     │
│     3 │ z       │ three   │
└───────┴─────────┴─────────┘
```

### with no qualifier the column is the left's, and each side's is still there by name

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a, t.a, u.a FROM t JOIN u USING (a) ORDER BY 1")
```
---
```output
┌───────┬───────┬───────┐
│   a   │   a   │   a   │
│ int32 │ int32 │ int32 │
├───────┼───────┼───────┤
│     2 │     2 │     2 │
│     2 │     2 │     2 │
│     3 │     3 │     3 │
└───────┴───────┴───────┘
```

### LEFT JOIN ... USING

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT * FROM t LEFT JOIN u USING (a) ORDER BY a, b")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     1 │ x       │ NULL    │
│     2 │ y       │ two     │
│     2 │ y       │ two     │
│     3 │ z       │ three   │
└───────┴─────────┴─────────┘
```

### u.* is still every column of u

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT u.* FROM t JOIN u USING (a) ORDER BY 1")
```
---
```output
┌───────┬─────────┐
│   a   │    c    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ two     │
│     2 │ two     │
│     3 │ three   │
└───────┴─────────┘
```

### more than one column

```x
(sql "CREATE OR REPLACE TABLE p (k INTEGER, m INTEGER, v VARCHAR); INSERT INTO p VALUES (1,1,'a'),(1,2,'b'),(2,1,'c'); CREATE OR REPLACE TABLE q (k INTEGER, m INTEGER, w VARCHAR); INSERT INTO q VALUES (1,2,'B'),(2,1,'C'),(2,2,'D'); SELECT * FROM p JOIN q USING (k, m) ORDER BY k, m")
```
---
```output
┌───────┬───────┬─────────┬─────────┐
│   k   │   m   │    v    │    w    │
│ int32 │ int32 │ varchar │ varchar │
├───────┼───────┼─────────┼─────────┤
│     1 │     2 │ b       │ B       │
│     2 │     1 │ c       │ C       │
└───────┴───────┴─────────┴─────────┘
```

### NATURAL JOIN joins on every column the two share

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT * FROM t NATURAL JOIN u ORDER BY a; SELECT * FROM t NATURAL LEFT JOIN u ORDER BY a, b")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     2 │ y       │ two     │
│     2 │ y       │ two     │
│     3 │ z       │ three   │
└───────┴─────────┴─────────┘
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ varchar │
├───────┼─────────┼─────────┤
│     1 │ x       │ NULL    │
│     2 │ y       │ two     │
│     2 │ y       │ two     │
│     3 │ z       │ three   │
└───────┴─────────┴─────────┘
```

### grouped and filtered like any join

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT a, count(*) FROM t JOIN u USING (a) WHERE a > 2 GROUP BY a")
```
---
```output
┌───────┬──────────────┐
│   a   │ count_star() │
│ int32 │    int64     │
├───────┼──────────────┤
│     3 │            1 │
└───────┴──────────────┘
```

### a column the left has not

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT * FROM t JOIN u USING (zz)")
```
---
```output
Binder Error: Column "zz" does not exist on left side of join!
```

### a column only the left has

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT * FROM t JOIN u USING (b)")
```
---
```output
Binder Error: Column "b" does not exist on right side of join!
```

### RIGHT and FULL joins with USING are not built

DuckDB shows the column once, the left's value or, where the left has no row, the right's.

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER, c VARCHAR); INSERT INTO u VALUES (2,'two'),(3,'three'),(4,'four'),(NULL,'none'); SELECT * FROM t FULL JOIN u USING (a)")
```
---
```output
Not implemented Error: USING or NATURAL with a RIGHT or FULL JOIN
```

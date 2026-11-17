A select statement inside another: for one value, for a list to be IN, for
EXISTS, and as a table of a FROM, in parentheses or named by WITH.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## subqueries values

### a select statement in parentheses is its one value, headed as DuckDB spells it back

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT (SELECT 1), (SELECT max(a) FROM u), 10 + (SELECT count(*) FROM u) AS n")
```
---
```output
┌────────────┬────────────────────────┬───────┐
│ (SELECT 1) │ (SELECT max(a) FROM u) │   n   │
│   int32    │         int32          │ int64 │
├────────────┼────────────────────────┼───────┤
│          1 │                      4 │    13 │
└────────────┴────────────────────────┴───────┘
```

### no row is NULL, of the column's type

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT (SELECT a FROM u WHERE a > 9) AS none, (SELECT b FROM t WHERE a > 9) AS nothing")
```
---
```output
┌───────┬─────────┐
│ none  │ nothing │
│ int32 │ varchar │
├───────┼─────────┤
│  NULL │ NULL    │
└───────┴─────────┘
```

### it may read the row it is answered for

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a, (SELECT count(*) FROM u WHERE u.a > t.a) AS above FROM t ORDER BY a")
```
---
```output
┌───────┬───────┐
│   a   │ above │
│ int32 │ int64 │
├───────┼───────┤
│     1 │     3 │
│     2 │     2 │
│     3 │     1 │
└───────┴───────┘
```

### a name the subquery has is its own, and one it has not is the outer row's

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a, (SELECT min(a) FROM u) AS least, (SELECT min(u.a + t.a) FROM u) AS sum FROM t ORDER BY a")
```
---
```output
┌───────┬───────┬───────┐
│   a   │ least │  sum  │
│ int32 │ int32 │ int32 │
├───────┼───────┼───────┤
│     1 │     2 │     3 │
│     2 │     2 │     4 │
│     3 │     2 │     5 │
└───────┴───────┴───────┘
```

### in WHERE

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a FROM t WHERE a > (SELECT min(a) FROM u) ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     3 │
└───────┘
```

### an aggregate in a subquery does not group the statement around it

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a, (SELECT max(a) FROM u) AS top FROM t ORDER BY a")
```
---
```output
┌───────┬───────┐
│   a   │  top  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     4 │
│     2 │     4 │
│     3 │     4 │
└───────┴───────┘
```

### more than one row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT (SELECT a FROM u)")
```
---
```output
Invalid Input Error: More than one row returned by a subquery used as an expression - scalar subqueries can only return a single row.
```

### more than one column

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT (SELECT a, a FROM u LIMIT 1)")
```
---
```output
Binder Error: Subquery returns 2 columns - expected 1
```

## subqueries in and exists

### IN a select statement

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a, a IN (SELECT a FROM u) AS shared FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │ shared  │
│ int32 │ boolean │
├───────┼─────────┤
│     1 │ false   │
│     2 │ true    │
│     3 │ true    │
└───────┴─────────┘
```

### NOT IN

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a FROM t WHERE a NOT IN (SELECT a FROM u) ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

### a NULL among the rows makes a miss NULL

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT 1 IN (SELECT a FROM u) AS a, 1 IN (SELECT NULL) AS b")
```
---
```output
┌─────────┬─────────┐
│    a    │    b    │
│ boolean │ boolean │
├─────────┼─────────┤
│ false   │ NULL    │
└─────────┴─────────┘
```

### EXISTS is whether there is a row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT EXISTS (SELECT 1 FROM u) AS some, EXISTS (SELECT 1 FROM u WHERE a > 9) AS none")
```
---
```output
┌─────────┬─────────┐
│  some   │  none   │
│ boolean │ boolean │
├─────────┼─────────┤
│ true    │ false   │
└─────────┴─────────┘
```

### EXISTS for each row, and NOT EXISTS

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT a FROM t WHERE EXISTS (SELECT * FROM u WHERE u.a = t.a) ORDER BY a; SELECT a FROM t WHERE NOT EXISTS (SELECT * FROM u WHERE u.a = t.a)")
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
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

### the headings of IN and EXISTS

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT 1 IN (SELECT a FROM u), EXISTS (SELECT 1 FROM u WHERE (a > 2))")
```
---
```output
┌────────────────────────────┬───────────────────────────────────────┐
│ (1 = ANY(SELECT a FROM u)) │ EXISTS(SELECT 1 FROM u WHERE (a > 2)) │
│          boolean           │                boolean                │
├────────────────────────────┼───────────────────────────────────────┤
│ false                      │ true                                  │
└────────────────────────────┴───────────────────────────────────────┘
```

## subqueries tables

### a select statement in a FROM is a table, under its alias

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); SELECT s.n, n * 2 FROM (SELECT a + 1 AS n FROM t) AS s WHERE n > 2 ORDER BY n")
```
---
```output
┌───────┬─────────┐
│   n   │ (n * 2) │
│ int32 │  int32  │
├───────┼─────────┤
│     3 │       6 │
│     4 │       8 │
└───────┴─────────┘
```

### with no alias, and with no FROM of its own

```x
(sql "SELECT n FROM (SELECT 7 AS n); SELECT * FROM (SELECT 1 AS a, 'x' AS b)")
```
---
```output
┌───────┐
│   n   │
│ int32 │
├───────┤
│     7 │
└───────┘
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
└───────┴─────────┘
```

### joined to a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); CREATE OR REPLACE TABLE u (a INTEGER); INSERT INTO u VALUES (2),(3),(4); SELECT t.a, s.m FROM t JOIN (SELECT a, a * 10 AS m FROM u) s ON t.a = s.a ORDER BY 1")
```
---
```output
┌───────┬───────┐
│   a   │   m   │
│ int32 │ int32 │
├───────┼───────┤
│     2 │    20 │
│     3 │    30 │
└───────┴───────┘
```

### grouped, and a group's result read again

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); SELECT max(n) FROM (SELECT b, count(*) AS n FROM t GROUP BY b) g")
```
---
```output
┌────────┐
│ max(n) │
│ int64  │
├────────┤
│      1 │
└────────┘
```

### one inside another

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); SELECT * FROM (SELECT * FROM (SELECT a FROM t WHERE a > 1) x WHERE a < 3) y")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
└───────┘
```

### FROM first

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); FROM (SELECT a FROM t ORDER BY a DESC LIMIT 2) SELECT a ORDER BY a")
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

## subqueries with

### WITH names a select statement for the one that follows

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); WITH w AS (SELECT a FROM t WHERE a > 1) SELECT * FROM w ORDER BY a")
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

### each name is there for the next

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); WITH w AS (SELECT a FROM t WHERE a > 1), v AS (SELECT a * 2 AS d FROM w) SELECT * FROM v ORDER BY d")
```
---
```output
┌───────┐
│   d   │
│ int32 │
├───────┤
│     4 │
│     6 │
└───────┘
```

### a name may be read more than once, and joined to itself

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); WITH w AS (SELECT a FROM t) SELECT x.a, y.a FROM w x JOIN w y ON x.a = y.a + 1 ORDER BY 1")
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

### a name hides a table until the statement is done

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); WITH t AS (SELECT 'other' AS b) SELECT b FROM t; SELECT count(*) FROM t")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ other   │
└─────────┘
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            3 │
└──────────────┘
```

### in a subquery, and filling a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'y'),(3,'z'); SELECT (WITH w AS (SELECT 5 AS n) SELECT n FROM w) AS five; CREATE OR REPLACE TABLE c AS WITH w AS (SELECT a FROM t) SELECT a * 2 AS d FROM w; FROM c ORDER BY d")
```
---
```output
┌───────┐
│ five  │
│ int32 │
├───────┤
│     5 │
└───────┘
┌───────┐
│   d   │
│ int32 │
├───────┤
│     2 │
│     4 │
│     6 │
└───────┘
```

A WITH whose table reads itself, a WITH's column names, and select
statements in parentheses.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## recursive counting

### a table of WITH RECURSIVE reads itself: its left side once, then its right side over the rows last added, until none is

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 4) SELECT * FROM n")
```
---
```output
┌───────┐
│   i   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
│     4 │
└───────┘
```

### a step reads only the step before

```x
(sql "WITH RECURSIVE f(a, b) AS (SELECT 0, 1 UNION ALL SELECT b, a + b FROM f WHERE b < 30) SELECT a FROM f")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     0 │
│     1 │
│     1 │
│     2 │
│     3 │
│     5 │
│     8 │
│    13 │
│    21 │
└───────┘
```

### under UNION a row is added once, and so a loop ends

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION SELECT (i % 3) + 1 FROM n) SELECT * FROM n")
```
---
```output
┌───────┐
│   i   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
```

### the columns may be named by the left side

```x
(sql "WITH RECURSIVE n AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT sum(i) FROM n")
```
---
```output
┌────────┐
│ sum(i) │
│ int128 │
├────────┤
│      6 │
└────────┘
```

### the types are the left side's, and a step's values are cast to them

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 0.5 FROM n WHERE i < 2) SELECT i, typeof(i) FROM n")
```
---
```output
┌───────┬───────────┐
│   i   │ typeof(i) │
│ int32 │  varchar  │
├───────┼───────────┤
│     1 │ INTEGER   │
│     2 │ INTEGER   │
└───────┴───────────┘
```

### the table is a table to the statement after: sorted, cut, joined to itself, read in a subquery

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT * FROM n ORDER BY i DESC LIMIT 2; WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT a.i, b.i FROM n a JOIN n b ON b.i = a.i + 1; WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT (SELECT max(i) FROM n), i FROM n")
```
---
```output
┌───────┐
│   i   │
│ int32 │
├───────┤
│     3 │
│     2 │
└───────┘
┌───────┬───────┐
│   i   │   i   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
│     2 │     3 │
└───────┴───────┘
┌────────────────────────┬───────┐
│ (SELECT max(i) FROM n) │   i   │
│         int32          │ int32 │
├────────────────────────┼───────┤
│                      3 │     1 │
│                      3 │     2 │
│                      3 │     3 │
└────────────────────────┴───────┘
```

### and to the tables after it, as are the ones before it

```x
(sql "WITH RECURSIVE a AS (SELECT 1 AS i), n(i) AS (SELECT i FROM a UNION ALL SELECT i + 1 FROM n WHERE i < 3), m AS (SELECT i * 2 AS j FROM n) SELECT * FROM m")
```
---
```output
┌───────┐
│   j   │
│ int32 │
├───────┤
│     2 │
│     4 │
│     6 │
└───────┘
```

## recursive steps

### a step joins the table to another: a tree walked from its root

```x
(sql "CREATE OR REPLACE TABLE e (p VARCHAR, c VARCHAR); INSERT INTO e VALUES ('a','b'),('b','c'),('a','d'),('d','e'); WITH RECURSIVE r(node, depth, path) AS (SELECT 'a', 0, 'a' UNION ALL SELECT e.c, depth + 1, path || '>' || e.c FROM r JOIN e ON e.p = r.node) SELECT * FROM r ORDER BY path")
```
---
```output
┌─────────┬───────┬─────────┐
│  node   │ depth │  path   │
│ varchar │ int32 │ varchar │
├─────────┼───────┼─────────┤
│ a       │     0 │ a       │
│ b       │     1 │ a>b     │
│ c       │     2 │ a>b>c   │
│ d       │     1 │ a>d     │
│ e       │     2 │ a>d>e   │
└─────────┴───────┴─────────┘
```

### a step may group

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT max(i) + 1 FROM n HAVING max(i) < 3) SELECT * FROM n")
```
---
```output
┌───────┐
│   i   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
```

### read the table twice, or in a derived table, or in a subquery

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT a.i + 1 FROM n a JOIN n b ON a.i = b.i WHERE a.i < 3) SELECT * FROM n; WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM (SELECT i FROM n) WHERE i < 3) SELECT * FROM n; WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT 2 WHERE (SELECT max(i) FROM n) < 2) SELECT * FROM n")
```
---
```output
┌───────┐
│   i   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
┌───────┐
│   i   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
┌───────┐
│   i   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
```

### or be a statement in parentheses with its own ORDER BY and LIMIT

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL (SELECT i + 1 FROM n WHERE i < 5 ORDER BY i LIMIT 1)) SELECT count(*) FROM n")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            5 │
└──────────────┘
```

### a recursive table fills a new table, and stands in a derived one

```x
(sql "CREATE OR REPLACE TABLE s AS WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT * FROM n; SELECT sum(i) FROM s; SELECT * FROM (WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT i FROM n) WHERE i > 1")
```
---
```output
┌────────┐
│ sum(i) │
│ int128 │
├────────┤
│      6 │
└────────┘
┌───────┐
│   i   │
│ int32 │
├───────┤
│     2 │
│     3 │
└───────┘
```

## recursive errors

### without RECURSIVE a table cannot read itself

```x
(sql "WITH n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT * FROM n")
```
---
```output
Binder Error: Circular reference to CTE "n", use WITH RECURSIVE to use recursive CTEs.
```

### nor with it when it is no UNION

```x
(sql "WITH RECURSIVE n(i) AS (SELECT i FROM n) SELECT * FROM n")
```
---
```output
Binder Error: Circular reference to CTE "n", use WITH RECURSIVE to use recursive CTEs.
```

### nor when the side that reads it is not the last

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3 UNION ALL SELECT 9) SELECT * FROM n")
```
---
```output
Binder Error: Circular reference to CTE "n", use WITH RECURSIVE to use recursive CTEs.
```

### INTERSECT is no step

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 INTERSECT SELECT i FROM n) SELECT * FROM n")
```
---
```output
Binder Error: Circular reference to CTE "n", use WITH RECURSIVE to use recursive CTEs.
```

### a step has the left side's count of columns

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1, 2 FROM n WHERE i < 3) SELECT * FROM n")
```
---
```output
Binder Error: Set operations can only apply to expressions with the same number of result columns
```

### and values that go into its types

```x
(sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT 'x' FROM n WHERE i < 3) SELECT * FROM n")
```
---
```output
Conversion Error: Could not convert string 'x' to INT32
```

## with columns

### names in parentheses after a table's name are its columns'

```x
(sql "WITH n(x, y) AS (SELECT 1, 2) SELECT y, x FROM n")
```
---
```output
┌───────┬───────┐
│   y   │   x   │
│ int32 │ int32 │
├───────┼───────┤
│     2 │     1 │
└───────┴───────┘
```

### fewer names than columns name the first, and more than there are go unused

```x
(sql "WITH n(x) AS (SELECT 1, 2) SELECT * FROM n; WITH n(x, y, z) AS (SELECT 1, 2) SELECT * FROM n")
```
---
```output
┌───────┬───────┐
│   x   │   2   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
┌───────┬───────┐
│   x   │   y   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
```

## parentheses

### a select statement in parentheses is a side of a set operation, read before its neighbours

```x
(sql "SELECT 1 UNION ALL (SELECT 2 UNION ALL SELECT 3) EXCEPT (SELECT 2); SELECT 1 AS a UNION (SELECT 2 INTERSECT SELECT 2) ORDER BY a")
```
---
```output
┌───────┐
│   1   │
│ int32 │
├───────┤
│     1 │
│     3 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
```

### its ORDER BY and LIMIT are its own, and one after the last parenthesis is the whole's

```x
(sql "(SELECT 1 AS a UNION ALL SELECT 2 ORDER BY a DESC LIMIT 1) UNION ALL (SELECT 5 ORDER BY 1) ORDER BY 1 DESC; SELECT 9 AS a UNION ALL (SELECT 1 UNION ALL SELECT 2 ORDER BY 1 DESC LIMIT 1) ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     5 │
│     2 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     9 │
└───────┘
```

### a statement may be in parentheses alone

```x
(sql "(SELECT 1 AS a, 'x' AS b); ((SELECT 2 AS a)) ORDER BY a LIMIT 1")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
└───────┴─────────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
└───────┘
```

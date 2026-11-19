The lists after a star: EXCLUDE leaves columns out of it, REPLACE puts an
expression in a column's place, and RENAME shows a column under another
name.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## star exclude

### EXCLUDE leaves columns out of a star

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (b) FROM t")
```
---
```output
┌───────┬────────┐
│   a   │   c    │
│ int32 │ double │
├───────┼────────┤
│     1 │    1.5 │
│     2 │    2.5 │
└───────┴────────┘
```

### one column needs no parentheses, and a name is found in any case

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE b FROM t; SELECT * EXCLUDE (a, C) FROM t; SELECT * EXCLUDE (\"A\") FROM t")
```
---
```output
┌───────┬────────┐
│   a   │   c    │
│ int32 │ double │
├───────┼────────┤
│     1 │    1.5 │
│     2 │    2.5 │
└───────┴────────┘
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ x       │
│ y       │
└─────────┘
┌─────────┬────────┐
│    b    │   c    │
│ varchar │ double │
├─────────┼────────┤
│ x       │    1.5 │
│ y       │    2.5 │
└─────────┴────────┘
```

### EXCEPT is the same word

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCEPT (b) FROM t; SELECT * EXCEPT b FROM t")
```
---
```output
┌───────┬────────┐
│   a   │   c    │
│ int32 │ double │
├───────┼────────┤
│     1 │    1.5 │
│     2 │    2.5 │
└───────┴────────┘
┌───────┬────────┐
│   a   │   c    │
│ int32 │ double │
├───────┼────────┤
│     1 │    1.5 │
│     2 │    2.5 │
└───────┴────────┘
```

### items after it are items still

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * EXCLUDE (d), d * 2 AS e FROM t JOIN u USING (a); SELECT * EXCLUDE a, b FROM t")
```
---
```output
┌───────┬─────────┬────────┬───────┐
│   a   │    b    │   c    │   e   │
│ int32 │ varchar │ double │ int32 │
├───────┼─────────┼────────┼───────┤
│     1 │ x       │    1.5 │    20 │
│     2 │ y       │    2.5 │    40 │
└───────┴─────────┴────────┴───────┘
┌─────────┬────────┬─────────┐
│    b    │   c    │    b    │
│ varchar │ double │ varchar │
├─────────┼────────┼─────────┤
│ x       │    1.5 │ x       │
│ y       │    2.5 │ y       │
└─────────┴────────┴─────────┘
```

### a star of one table excludes among its own columns

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT t.* EXCLUDE (a), u.* FROM t JOIN u ON t.a = u.a")
```
---
```output
┌─────────┬────────┬───────┬───────┐
│    b    │   c    │   a   │   d   │
│ varchar │ double │ int32 │ int32 │
├─────────┼────────┼───────┼───────┤
│ x       │    1.5 │     1 │    10 │
│ y       │    2.5 │     2 │    20 │
└─────────┴────────┴───────┴───────┘
```

### a bare name leaves out that column of every table, a qualified one of its table

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * EXCLUDE (a) FROM t JOIN u ON t.a = u.a; SELECT * EXCLUDE (t.a) FROM t JOIN u ON t.a = u.a; SELECT * EXCLUDE (u.d) FROM t JOIN u ON t.a = u.a")
```
---
```output
┌─────────┬────────┬───────┐
│    b    │   c    │   d   │
│ varchar │ double │ int32 │
├─────────┼────────┼───────┤
│ x       │    1.5 │    10 │
│ y       │    2.5 │    20 │
└─────────┴────────┴───────┘
┌─────────┬────────┬───────┬───────┐
│    b    │   c    │   a   │   d   │
│ varchar │ double │ int32 │ int32 │
├─────────┼────────┼───────┼───────┤
│ x       │    1.5 │     1 │    10 │
│ y       │    2.5 │     2 │    20 │
└─────────┴────────┴───────┴───────┘
┌───────┬─────────┬────────┬───────┐
│   a   │    b    │   c    │   a   │
│ int32 │ varchar │ double │ int32 │
├───────┼─────────┼────────┼───────┤
│     1 │ x       │    1.5 │     1 │
│     2 │ y       │    2.5 │     2 │
└───────┴─────────┴────────┴───────┘
```

### the column a USING joined on goes out under its bare name

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * EXCLUDE (a) FROM t JOIN u USING (a)")
```
---
```output
┌─────────┬────────┬───────┐
│    b    │   c    │   d   │
│ varchar │ double │ int32 │
├─────────┼────────┼───────┤
│ x       │    1.5 │    10 │
│ y       │    2.5 │    20 │
└─────────┴────────┴───────┘
```

### leaving out the side that stands for it shows the other side

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * EXCLUDE (t.a) FROM t JOIN u USING (a); SELECT * EXCLUDE (u.a) FROM t JOIN u USING (a)")
```
---
```output
┌─────────┬────────┬───────┬───────┐
│    b    │   c    │   a   │   d   │
│ varchar │ double │ int32 │ int32 │
├─────────┼────────┼───────┼───────┤
│ x       │    1.5 │     1 │    10 │
│ y       │    2.5 │     2 │    20 │
└─────────┴────────┴───────┴───────┘
┌───────┬─────────┬────────┬───────┐
│   a   │    b    │   c    │   d   │
│ int32 │ varchar │ double │ int32 │
├───────┼─────────┼────────┼───────┤
│     1 │ x       │    1.5 │    10 │
│     2 │ y       │    2.5 │    20 │
└───────┴─────────┴────────┴───────┘
```

### in a subquery, with the clauses of a SELECT around it

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * EXCLUDE (a) FROM (SELECT * EXCLUDE (c) FROM t) ORDER BY b DESC; SELECT * EXCLUDE (a) FROM t JOIN u ON t.a = u.a WHERE d > 10; SELECT DISTINCT * EXCLUDE (a, b, d) FROM t, u ORDER BY c; SELECT * EXCLUDE (b) FROM t GROUP BY ALL ORDER BY a")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ y       │
│ x       │
└─────────┘
┌─────────┬────────┬───────┐
│    b    │   c    │   d   │
│ varchar │ double │ int32 │
├─────────┼────────┼───────┤
│ y       │    2.5 │    20 │
└─────────┴────────┴───────┘
┌────────┐
│   c    │
│ double │
├────────┤
│    1.5 │
│    2.5 │
└────────┘
┌───────┬────────┐
│   a   │   c    │
│ int32 │ double │
├───────┼────────┤
│     1 │    1.5 │
│     2 │    2.5 │
└───────┴────────┘
```

### a star left with nothing is no fault beside another item

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (a, b, c), 1 FROM t")
```
---
```output
┌───────┐
│   1   │
│ int32 │
├───────┤
│     1 │
│     1 │
└───────┘
```

## star replace

### REPLACE puts an expression in a column's place, under the column's name

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE (a * 10 AS a) FROM t")
```
---
```output
┌───────┬─────────┬────────┐
│   a   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│    10 │ x       │    1.5 │
│    20 │ y       │    2.5 │
└───────┴─────────┴────────┘
```

### one needs no parentheses, the type is the expression's, and the name is as REPLACE writes it

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE upper(b) AS b FROM t; SELECT * REPLACE (b AS a, a + c AS c) FROM t; SELECT * REPLACE (a AS A) FROM t")
```
---
```output
┌───────┬─────────┬────────┐
│   a   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│     1 │ X       │    1.5 │
│     2 │ Y       │    2.5 │
└───────┴─────────┴────────┘
┌─────────┬─────────┬────────┐
│    a    │    b    │   c    │
│ varchar │ varchar │ double │
├─────────┼─────────┼────────┤
│ x       │ x       │    2.5 │
│ y       │ y       │    4.5 │
└─────────┴─────────┴────────┘
┌───────┬─────────┬────────┐
│   A   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│     1 │ x       │    1.5 │
│     2 │ y       │    2.5 │
└───────┴─────────┴────────┘
```

### after EXCLUDE

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (b) REPLACE (a + c AS a) FROM t")
```
---
```output
┌────────┬────────┐
│   a    │   c    │
│ double │ double │
├────────┼────────┤
│    2.5 │    1.5 │
│    4.5 │    2.5 │
└────────┴────────┘
```

### a window function in one

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE (sum(a) OVER () AS a) FROM t")
```
---
```output
┌────────┬─────────┬────────┐
│   a    │    b    │   c    │
│ int128 │ varchar │ double │
├────────┼─────────┼────────┤
│      3 │ x       │    1.5 │
│      3 │ y       │    2.5 │
└────────┴─────────┴────────┘
```

### a star of one table, and the column a USING joined on

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT t.* RENAME (a AS z), u.* REPLACE (d + 1 AS d) FROM t JOIN u ON t.a = u.a; SELECT * REPLACE (a + 100 AS a) FROM t JOIN u USING (a)")
```
---
```output
┌───────┬─────────┬────────┬───────┬───────┐
│   z   │    b    │   c    │   a   │   d   │
│ int32 │ varchar │ double │ int32 │ int32 │
├───────┼─────────┼────────┼───────┼───────┤
│     1 │ x       │    1.5 │     1 │    11 │
│     2 │ y       │    2.5 │     2 │    21 │
└───────┴─────────┴────────┴───────┴───────┘
┌───────┬─────────┬────────┬───────┐
│   a   │    b    │   c    │   d   │
│ int32 │ varchar │ double │ int32 │
├───────┼─────────┼────────┼───────┤
│   101 │ x       │    1.5 │    10 │
│   102 │ y       │    2.5 │    20 │
└───────┴─────────┴────────┴───────┘
```

### a REPLACE is used once: of two columns of its name the first is replaced and the second is left out

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * REPLACE (d AS a) FROM t JOIN u ON t.a = u.a")
```
---
```output
┌───────┬─────────┬────────┬───────┐
│   a   │    b    │   c    │   d   │
│ int32 │ varchar │ double │ int32 │
├───────┼─────────┼────────┼───────┤
│    10 │ x       │    1.5 │    10 │
│    20 │ y       │    2.5 │    20 │
└───────┴─────────┴────────┴───────┘
```

### lists go with CREATE TABLE AS

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE v AS SELECT * EXCLUDE (c) RENAME (b AS name) FROM t; SELECT * FROM v")
```
---
```output
┌───────┬─────────┐
│   a   │  name   │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ y       │
└───────┴─────────┘
```

## star rename

### RENAME shows a column under another name

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * RENAME (a AS z) FROM t; SELECT * RENAME a AS z FROM t")
```
---
```output
┌───────┬─────────┬────────┐
│   z   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│     1 │ x       │    1.5 │
│     2 │ y       │    2.5 │
└───────┴─────────┴────────┘
┌───────┬─────────┬────────┐
│   z   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│     1 │ x       │    1.5 │
│     2 │ y       │    2.5 │
└───────┴─────────┴────────┘
```

### after EXCLUDE, and ORDER BY knows the new name

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (b) RENAME (a AS z) FROM t ORDER BY z DESC")
```
---
```output
┌───────┬────────┐
│   z   │   c    │
│ int32 │ double │
├───────┼────────┤
│     2 │    2.5 │
│     1 │    1.5 │
└───────┴────────┘
```

### a bare name renames that column of every table, a qualified one of its table

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); CREATE OR REPLACE TABLE u (a INT, d INT); INSERT INTO u VALUES (1, 10), (2, 20); SELECT * RENAME (a AS z) FROM t JOIN u ON t.a = u.a; SELECT * RENAME (t.a AS z) FROM t JOIN u ON t.a = u.a")
```
---
```output
┌───────┬─────────┬────────┬───────┬───────┐
│   z   │    b    │   c    │   z   │   d   │
│ int32 │ varchar │ double │ int32 │ int32 │
├───────┼─────────┼────────┼───────┼───────┤
│     1 │ x       │    1.5 │     1 │    10 │
│     2 │ y       │    2.5 │     2 │    20 │
└───────┴─────────┴────────┴───────┴───────┘
┌───────┬─────────┬────────┬───────┬───────┐
│   z   │    b    │   c    │   a   │   d   │
│ int32 │ varchar │ double │ int32 │ int32 │
├───────┼─────────┼────────┼───────┼───────┤
│     1 │ x       │    1.5 │     1 │    10 │
│     2 │ y       │    2.5 │     2 │    20 │
└───────┴─────────┴────────┴───────┴───────┘
```

### a column the star has not is passed over, and of two renames of one column the later holds

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * RENAME (q AS z) FROM t; SELECT * RENAME (a AS z, a AS y) FROM t")
```
---
```output
┌───────┬─────────┬────────┐
│   a   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│     1 │ x       │    1.5 │
│     2 │ y       │    2.5 │
└───────┴─────────┴────────┘
┌───────┬─────────┬────────┐
│   y   │    b    │   c    │
│ int32 │ varchar │ double │
├───────┼─────────┼────────┤
│     1 │ x       │    1.5 │
│     2 │ y       │    2.5 │
└───────┴─────────┴────────┘
```

## star errors

### EXCLUDE of a column the star has not

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (z) FROM t")
```
---
```output
Binder Error: Column "z" in EXCLUDE list not found in FROM clause
```

### or its table has not

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT t.* EXCLUDE (d) FROM t")
```
---
```output
Binder Error: Column "d" in EXCLUDE list not found in t
```

### or of a table that is not there

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (x.a) FROM t")
```
---
```output
Binder Error: Column "x"."a" in EXCLUDE list not found in FROM clause
```

### REPLACE of one

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE (a * 10 AS z) FROM t")
```
---
```output
Binder Error: Column "z" in REPLACE list not found in FROM clause
```

### and of one its table has not

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT t.* REPLACE (1 AS z) FROM t")
```
---
```output
Binder Error: Column "z" in REPLACE list not found in t
```

### a column twice in EXCLUDE

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (a, A) FROM t")
```
---
```output
Parser Error: Duplicate entry "A" in EXCLUDE list
```

### or in REPLACE

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE (1 AS a, 2 AS a) FROM t")
```
---
```output
Parser Error: Duplicate entry "a" in REPLACE list
```

### a column in EXCLUDE and REPLACE

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (a) REPLACE (a + c AS a) FROM t")
```
---
```output
Parser Error: Column ""a"" cannot occur in both EXCLUDE and REPLACE list
```

### in EXCLUDE and RENAME

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (a) RENAME (a AS z) FROM t")
```
---
```output
Parser Error: Column "a" cannot occur in both EXCLUDE and RENAME list
```

### in REPLACE and RENAME

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE (a + 1 AS a) RENAME (a AS z) FROM t")
```
---
```output
Parser Error: Column "a" cannot occur in both REPLACE and RENAME list
```

### every column left out

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE (a, b, c) FROM t")
```
---
```output
Binder Error: SELECT list is empty after resolving * expressions!
```

### the lists out of their order

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * REPLACE (1 AS a) EXCLUDE (b) FROM t")
```
---
```output
Parser Error: syntax error at or near "EXCLUDE"
```

### an empty list

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT * EXCLUDE () FROM t")
```
---
```output
Parser Error: syntax error at or near ")"
```

### a star of a table that is not there

```x
(sql "CREATE OR REPLACE TABLE t (a INT, b TEXT, c DOUBLE); INSERT INTO t VALUES (1, 'x', 1.5), (2, 'y', 2.5); SELECT x.* EXCLUDE (b) FROM t")
```
---
```output
Binder Error: Referenced table "x" not found!
```

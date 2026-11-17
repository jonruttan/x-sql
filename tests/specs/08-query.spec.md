A SELECT over one table: FROM, WHERE, ORDER BY, LIMIT and OFFSET, and
DuckDB's FROM-first order.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## query from

### * is every column, in the table's order

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT * FROM t")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ boolean │
├───────┼─────────┼─────────┤
│     2 │ two     │ true    │
│     1 │ one     │ false   │
│  NULL │ NULL    │ NULL    │
│     3 │ three   │ NULL    │
└───────┴─────────┴─────────┘
```

### a column is headed by the name the table has, an expression as written

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT A, t.b, A + 1, t.a * 2 FROM t")
```
---
```output
┌───────┬─────────┬─────────┬───────────┐
│   a   │    b    │ (A + 1) │ (t.a * 2) │
│ int32 │ varchar │  int32  │   int32   │
├───────┼─────────┼─────────┼───────────┤
│     2 │ two     │       3 │         4 │
│     1 │ one     │       2 │         2 │
│  NULL │ NULL    │    NULL │      NULL │
│     3 │ three   │       4 │         6 │
└───────┴─────────┴─────────┴───────────┘
```

### an alias names the table, and the table's own name no longer does

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT x.a, x.* FROM t AS x; SELECT y.b FROM t y")
```
---
```output
┌───────┬───────┬─────────┬─────────┐
│   a   │   a   │    b    │    c    │
│ int32 │ int32 │ varchar │ boolean │
├───────┼───────┼─────────┼─────────┤
│     2 │     2 │ two     │ true    │
│     1 │     1 │ one     │ false   │
│  NULL │  NULL │ NULL    │ NULL    │
│     3 │     3 │ three   │ NULL    │
└───────┴───────┴─────────┴─────────┘
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ two     │
│ one     │
│ NULL    │
│ three   │
└─────────┘
```

### the table's name is no qualifier under an alias

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT t.a FROM t AS x")
```
---
```output
Binder Error: Referenced table "t" not found!
```

### a column the table does not have

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT z FROM t")
```
---
```output
Binder Error: Referenced column "z" not found in FROM clause!
```

### a table that is not there

```x
(sql "SELECT * FROM nope")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

### * with no FROM

```x
(sql "SELECT *")
```
---
```output
Binder Error: * expression without FROM clause!
```

### FROM alone is every column

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); FROM t")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ boolean │
├───────┼─────────┼─────────┤
│     2 │ two     │ true    │
│     1 │ one     │ false   │
│  NULL │ NULL    │ NULL    │
│     3 │ three   │ NULL    │
└───────┴─────────┴─────────┘
```

### FROM first, then SELECT

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); FROM t SELECT b, a")
```
---
```output
┌─────────┬───────┐
│    b    │   a   │
│ varchar │ int32 │
├─────────┼───────┤
│ two     │     2 │
│ one     │     1 │
│ NULL    │  NULL │
│ three   │     3 │
└─────────┴───────┘
```

### a constant over a table is one a row

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT 'x' AS k, 1 + 1 FROM t")
```
---
```output
┌─────────┬─────────┐
│    k    │ (1 + 1) │
│ varchar │  int32  │
├─────────┼─────────┤
│ x       │       2 │
│ x       │       2 │
│ x       │       2 │
│ x       │       2 │
└─────────┴─────────┘
```

## query where

### WHERE keeps the rows that are true: not the false, not the NULL

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT * FROM t WHERE a > 1; SELECT a FROM t WHERE c")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ boolean │
├───────┼─────────┼─────────┤
│     2 │ two     │ true    │
│     3 │ three   │ NULL    │
└───────┴─────────┴─────────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
└───────┘
```

### conditions join

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a, b FROM t WHERE a >= 2 AND b != 'two' OR a IS NULL")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│  NULL │ NULL    │
│     3 │ three   │
└───────┴─────────┘
```

### no row left is the heading and a count

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a, b FROM t WHERE a > 5")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
└───────┴─────────┘
      0 rows     
```

### WHERE with no FROM

```x
(sql "SELECT 1 AS a WHERE false; SELECT 2 AS b WHERE true")
```
---
```output
┌────────┐
│   a    │
│ int32  │
└────────┘
  0 rows
┌───────┐
│   b   │
│ int32 │
├───────┤
│     2 │
└───────┘
```

## query order

### ascending, NULL last

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY a")
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
│  NULL │
└───────┘
```

### descending, NULL still last

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY a DESC")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     3 │
│     2 │
│     1 │
│  NULL │
└───────┘
```

### NULLS FIRST

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY a NULLS FIRST; SELECT a FROM t ORDER BY a DESC NULLS FIRST")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│  NULL │
│     1 │
│     2 │
│     3 │
└───────┘
┌───────┐
│   a   │
│ int32 │
├───────┤
│  NULL │
│     3 │
│     2 │
│     1 │
└───────┘
```

### text sorts by its bytes

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT b FROM t ORDER BY b")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ one     │
│ three   │
│ two     │
│ NULL    │
└─────────┘
```

### a second term breaks ties, and rows that still tie keep their order

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1, 'b'), (2, 'a'), (1, 'a'), (2, 'a'); SELECT * FROM t ORDER BY a DESC, b")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     2 │ a       │
│     2 │ a       │
│     1 │ a       │
│     1 │ b       │
└───────┴─────────┘
```

### a term may be an expression, a place in the list, or an alias

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY 0 - a; SELECT b, a FROM t ORDER BY 2; SELECT a * -1 AS z FROM t ORDER BY z")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     3 │
│     2 │
│     1 │
│  NULL │
└───────┘
┌─────────┬───────┐
│    b    │   a   │
│ varchar │ int32 │
├─────────┼───────┤
│ one     │     1 │
│ two     │     2 │
│ three   │     3 │
│ NULL    │  NULL │
└─────────┴───────┘
┌───────┐
│   z   │
│ int32 │
├───────┤
│    -3 │
│    -2 │
│    -1 │
│  NULL │
└───────┘
```

### a place past the list

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY 5")
```
---
```output
Binder Error: ORDER term out of range - should be between 1 and 1
```

## query limit

### LIMIT cuts, OFFSET skips

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY a LIMIT 2; SELECT a FROM t ORDER BY a LIMIT 2 OFFSET 1; SELECT a FROM t ORDER BY a OFFSET 3")
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
│  NULL │
└───────┘
```

### a count may be an expression

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t ORDER BY a LIMIT 1 + 1")
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
```

### LIMIT 0 is the heading and a count

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a, b FROM t LIMIT 0")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
└───────┴─────────┘
      0 rows     
```

### a negative count

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); SELECT a FROM t LIMIT -1")
```
---
```output
Binder Error: LIMIT/OFFSET cannot be negative
```

### FROM first with every clause

The clauses after the table keep the order they have after a SELECT.

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); FROM t SELECT b WHERE a IS NOT NULL ORDER BY a DESC LIMIT 2 OFFSET 1")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ two     │
│ one     │
└─────────┘
```

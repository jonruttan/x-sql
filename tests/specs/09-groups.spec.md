Aggregates, GROUP BY, HAVING and DISTINCT.  DuckDB gives groups no
order, so every case with more than one sorts them.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## groups aggregates

### count, sum, min and max over every row; a NULL is not counted, summed or compared

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT count(*), count(a), sum(a), min(a), max(a), min(b), max(b) FROM t")
```
---
```output
┌──────────────┬──────────┬────────┬────────┬────────┬─────────┬─────────┐
│ count_star() │ count(a) │ sum(a) │ min(a) │ max(a) │ min(b)  │ max(b)  │
│    int64     │  int64   │ int128 │ int32  │ int32  │ varchar │ varchar │
├──────────────┼──────────┼────────┼────────┼────────┼─────────┼─────────┤
│            5 │        3 │      6 │      1 │      3 │ x       │ y       │
└──────────────┴──────────┴────────┴────────┴────────┴─────────┴─────────┘
```

### a heading spells a call in lower case, and count(*) DuckDB's way

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT COUNT(*), Sum(a), count() FROM t")
```
---
```output
┌──────────────┬────────┬──────────────┐
│ count_star() │ sum(a) │ count_star() │
│    int64     │ int128 │    int64     │
├──────────────┼────────┼──────────────┤
│            5 │      6 │            5 │
└──────────────┴────────┴──────────────┘
```

### over no rows count is 0 and the rest are NULL, each still of its type

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT count(*), count(a), sum(a), min(a), max(b) FROM t WHERE a > 9")
```
---
```output
┌──────────────┬──────────┬────────┬────────┬─────────┐
│ count_star() │ count(a) │ sum(a) │ min(a) │ max(b)  │
│    int64     │  int64   │ int128 │ int32  │ varchar │
├──────────────┼──────────┼────────┼────────┼─────────┤
│            0 │        0 │   NULL │   NULL │ NULL    │
└──────────────┴──────────┴────────┴────────┴─────────┘
```

### DISTINCT in a call takes each value once

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT count(DISTINCT b), count(b), sum(DISTINCT a + a - a) FROM t")
```
---
```output
┌───────────────────┬──────────┬─────────────────────────────┐
│ count(DISTINCT b) │ count(b) │ sum(DISTINCT ((a + a) - a)) │
│       int64       │  int64   │           int128            │
├───────────────────┼──────────┼─────────────────────────────┤
│                 2 │        4 │                           6 │
└───────────────────┴──────────┴─────────────────────────────┘
```

### an aggregate is a value in an expression

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT sum(a) + 1, max(a) - min(a), count(*) > 3 FROM t")
```
---
```output
┌──────────────┬───────────────────┬────────────────────┐
│ (sum(a) + 1) │ (max(a) - min(a)) │ (count_star() > 3) │
│    int128    │       int32       │      boolean       │
├──────────────┼───────────────────┼────────────────────┤
│            7 │                 2 │ true               │
└──────────────┴───────────────────┴────────────────────┘
```

### an aggregate with no FROM is over one row

```x
(sql "SELECT count(*), sum(2), max(7)")
```
---
```output
┌──────────────┬────────┬────────┐
│ count_star() │ sum(2) │ max(7) │
│    int64     │ int128 │ int32  │
├──────────────┼────────┼────────┤
│            1 │      2 │      7 │
└──────────────┴────────┴────────┘
```

### a sum is a HUGEINT, and does not overflow its operands' type

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER); INSERT INTO t VALUES (2147483647), (2147483647); SELECT sum(a) FROM t")
```
---
```output
┌────────────┐
│   sum(a)   │
│   int128   │
├────────────┤
│ 4294967294 │
└────────────┘
```

## groups group by

### a row a group, NULL a group of its own

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, count(*) AS n, sum(a) FROM t GROUP BY b ORDER BY b")
```
---
```output
┌─────────┬───────┬────────┐
│    b    │   n   │ sum(a) │
│ varchar │ int64 │ int128 │
├─────────┼───────┼────────┤
│ x       │     2 │      3 │
│ y       │     2 │      3 │
│ NULL    │     1 │   NULL │
└─────────┴───────┴────────┘
```

### a key may be an expression, an alias, or a place in the list

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT a + 1 AS k, count(*) FROM t GROUP BY a + 1 ORDER BY k; SELECT a + 1 AS k, count(*) FROM t GROUP BY k ORDER BY k; SELECT a + 1, count(*) FROM t GROUP BY 1 ORDER BY 1")
```
---
```output
┌───────┬──────────────┐
│   k   │ count_star() │
│ int32 │    int64     │
├───────┼──────────────┤
│     2 │            1 │
│     3 │            1 │
│     4 │            1 │
│  NULL │            2 │
└───────┴──────────────┘
┌───────┬──────────────┐
│   k   │ count_star() │
│ int32 │    int64     │
├───────┼──────────────┤
│     2 │            1 │
│     3 │            1 │
│     4 │            1 │
│  NULL │            2 │
└───────┴──────────────┘
┌─────────┬──────────────┐
│ (a + 1) │ count_star() │
│  int32  │    int64     │
├─────────┼──────────────┤
│       2 │            1 │
│       3 │            1 │
│       4 │            1 │
│    NULL │            2 │
└─────────┴──────────────┘
```

### two keys

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, a IS NULL AS missing, count(*) FROM t GROUP BY b, a IS NULL ORDER BY 1, 2")
```
---
```output
┌─────────┬─────────┬──────────────┐
│    b    │ missing │ count_star() │
│ varchar │ boolean │    int64     │
├─────────┼─────────┼──────────────┤
│ x       │ false   │            2 │
│ y       │ false   │            1 │
│ y       │ true    │            1 │
│ NULL    │ true    │            1 │
└─────────┴─────────┴──────────────┘
```

### GROUP BY ALL groups by every item that holds no aggregate

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, count(*), max(a) FROM t GROUP BY ALL ORDER BY b")
```
---
```output
┌─────────┬──────────────┬────────┐
│    b    │ count_star() │ max(a) │
│ varchar │    int64     │ int32  │
├─────────┼──────────────┼────────┤
│ x       │            2 │      2 │
│ y       │            2 │      3 │
│ NULL    │            1 │   NULL │
└─────────┴──────────────┴────────┘
```

### a key need not be shown

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT count(*) FROM t GROUP BY b ORDER BY 1")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            1 │
│            2 │
│            2 │
└──────────────┘
```

### a grouped table with no rows has no groups

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, count(*) FROM t WHERE a > 9 GROUP BY b")
```
---
```output
┌─────────┬──────────────┐
│    b    │ count_star() │
│ varchar │    int64     │
└─────────┴──────────────┘
          0 rows        
```

### ORDER BY may sort groups by an aggregate

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b FROM t GROUP BY b ORDER BY sum(a) DESC NULLS LAST, b")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ x       │
│ y       │
│ NULL    │
└─────────┘
```

### WHERE is before the groups, LIMIT after

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, count(*) FROM t WHERE a IS NOT NULL GROUP BY b ORDER BY b LIMIT 1")
```
---
```output
┌─────────┬──────────────┐
│    b    │ count_star() │
│ varchar │    int64     │
├─────────┼──────────────┤
│ x       │            2 │
└─────────┴──────────────┘
```

### FROM first

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); FROM t SELECT b, count(*) GROUP BY b ORDER BY b")
```
---
```output
┌─────────┬──────────────┐
│    b    │ count_star() │
│ varchar │    int64     │
├─────────┼──────────────┤
│ x       │            2 │
│ y       │            2 │
│ NULL    │            1 │
└─────────┴──────────────┘
```

## groups having

### HAVING keeps the groups that are true

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, count(*) FROM t GROUP BY b HAVING count(*) > 1 ORDER BY b")
```
---
```output
┌─────────┬──────────────┐
│    b    │ count_star() │
│ varchar │    int64     │
├─────────┼──────────────┤
│ x       │            2 │
│ y       │            2 │
└─────────┴──────────────┘
```

### by an aggregate that is not shown

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b FROM t GROUP BY b HAVING max(a) > 2")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ y       │
└─────────┘
```

### HAVING with no GROUP BY is over the one group

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT count(*) FROM t HAVING count(*) > 9; SELECT count(*) FROM t HAVING count(*) > 1")
```
---
```output
┌──────────────┐
│ count_star() │
│    int64     │
└──────────────┘
     0 rows   
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            5 │
└──────────────┘
```

## groups distinct

### DISTINCT drops rows that repeat, NULL equal to NULL

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT DISTINCT b FROM t ORDER BY b")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ x       │
│ y       │
│ NULL    │
└─────────┘
```

### a row is every item together

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT DISTINCT b, a IS NULL FROM t ORDER BY 1, 2")
```
---
```output
┌─────────┬─────────────┐
│    b    │ (a IS NULL) │
│ varchar │   boolean   │
├─────────┼─────────────┤
│ x       │ false       │
│ y       │ false       │
│ y       │ true        │
│ NULL    │ true        │
└─────────┴─────────────┘
```

### LIMIT counts what DISTINCT leaves

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT DISTINCT b FROM t ORDER BY b LIMIT 2")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ x       │
│ y       │
└─────────┘
```

## groups errors

### a column that is neither a key nor aggregated

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, a FROM t GROUP BY b")
```
---
```output
Binder Error: column "a" must appear in the GROUP BY clause or must be part of an aggregate function.
```

### the same with no GROUP BY

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT b, sum(a) FROM t")
```
---
```output
Binder Error: column "b" must appear in the GROUP BY clause or must be part of an aggregate function.
```

### an aggregate in WHERE

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT a FROM t WHERE sum(a) > 1")
```
---
```output
Binder Error: WHERE clause cannot contain aggregates!
```

### an aggregate in an aggregate

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT sum(sum(a)) FROM t")
```
---
```output
Binder Error: aggregate function calls cannot be nested
```

### a key past the list

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT max(a), b FROM t GROUP BY 3")
```
---
```output
Binder Error: GROUP BY term out of range - should be between 1 and 2
```

### a sum of text

DuckDB's sentence goes on to suggest casts and list its candidates.

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT sum(b) FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'sum(VARCHAR)'.
```

### a function there is not

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT foo(a) FROM t")
```
---
```output
Catalog Error: Scalar Function with name foo does not exist!
```

### avg is not built

DuckDB answers a DOUBLE.

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'x'),(2,'x'),(3,'y'),(NULL,'y'),(NULL,NULL); SELECT avg(a) FROM t")
```
---
```output
Catalog Error: Scalar Function with name avg does not exist!
```

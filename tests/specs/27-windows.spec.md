Window functions: a call OVER the rows around each row.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## windows functions

### row_number counts a partition's rows in the window's order

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, g, a, row_number() OVER (PARTITION BY g ORDER BY a, id) FROM t ORDER BY id")
```
---
```output
┌───────┬─────────┬───────┬───────────────────────────────────────────────────┐
│  id   │    g    │   a   │ row_number() OVER (PARTITION BY g ORDER BY a, id) │
│ int32 │ varchar │ int32 │                       int64                       │
├───────┼─────────┼───────┼───────────────────────────────────────────────────┤
│     1 │ x       │     1 │                                                 1 │
│     2 │ x       │     2 │                                                 2 │
│     3 │ x       │     2 │                                                 3 │
│     4 │ y       │     6 │                                                 1 │
│     5 │ y       │  NULL │                                                 2 │
└───────┴─────────┴───────┴───────────────────────────────────────────────────┘
```

### rank leaves a gap after rows that tie and dense_rank does not

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, rank() OVER (ORDER BY a), dense_rank() OVER (ORDER BY a) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬──────────────────────────┬────────────────────────────────┐
│  id   │   a   │ rank() OVER (ORDER BY a) │ dense_rank() OVER (ORDER BY a) │
│ int32 │ int32 │          int64           │             int64              │
├───────┼───────┼──────────────────────────┼────────────────────────────────┤
│     1 │     1 │                        1 │                              1 │
│     2 │     2 │                        2 │                              2 │
│     3 │     2 │                        2 │                              2 │
│     4 │     6 │                        4 │                              3 │
│     5 │  NULL │                        5 │                              4 │
└───────┴───────┴──────────────────────────┴────────────────────────────────┘
```

### lag and lead reach a row before and after, by one row or by more, with a value for no row

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, lag(a) OVER (ORDER BY id), lead(a) OVER (ORDER BY id), lag(a, 2) OVER (ORDER BY id), lead(a, 2, -1) OVER (PARTITION BY g ORDER BY id) FROM t ORDER BY id")
```
---
```output
┌───────┬───────────────────────────┬────────────────────────────┬──────────────────────────────┬──────────────────────────────────────────────────┐
│  id   │ lag(a) OVER (ORDER BY id) │ lead(a) OVER (ORDER BY id) │ lag(a, 2) OVER (ORDER BY id) │ lead(a, 2, -1) OVER (PARTITION BY g ORDER BY id) │
│ int32 │           int32           │           int32            │            int32             │                      int32                       │
├───────┼───────────────────────────┼────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────┤
│     1 │                      NULL │                          2 │                         NULL │                                                2 │
│     2 │                         1 │                          2 │                         NULL │                                               -1 │
│     3 │                         2 │                          6 │                            1 │                                               -1 │
│     4 │                         2 │                       NULL │                            2 │                                               -1 │
│     5 │                         6 │                       NULL │                            2 │                                               -1 │
└───────┴───────────────────────────┴────────────────────────────┴──────────────────────────────┴──────────────────────────────────────────────────┘
```

### the value for no row is cast to the argument's type

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, lag(g, 1, 7) OVER (ORDER BY id), typeof(lead(a, 1, 0.5) OVER (ORDER BY id)) FROM t ORDER BY id")
```
---
```output
┌───────┬─────────────────────────────────┬────────────────────────────────────────────┐
│  id   │ lag(g, 1, 7) OVER (ORDER BY id) │ typeof(lead(a, 1, 0.5) OVER (ORDER BY id)) │
│ int32 │             varchar             │                  varchar                   │
├───────┼─────────────────────────────────┼────────────────────────────────────────────┤
│     1 │ 7                               │ INTEGER                                    │
│     2 │ x                               │ INTEGER                                    │
│     3 │ x                               │ INTEGER                                    │
│     4 │ x                               │ INTEGER                                    │
│     5 │ y                               │ INTEGER                                    │
└───────┴─────────────────────────────────┴────────────────────────────────────────────┘
```

### first_value and last_value read the ends of the frame, which stops at the row unless it is told otherwise

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, first_value(a) OVER (PARTITION BY g ORDER BY id), last_value(a) OVER (PARTITION BY g ORDER BY id), last_value(a) OVER (PARTITION BY g ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬──────────────────────────────────────────────────┬─────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  id   │ first_value(a) OVER (PARTITION BY g ORDER BY id) │ last_value(a) OVER (PARTITION BY g ORDER BY id) │ last_value(a) OVER (PARTITION BY g ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) │
│ int32 │                      int32                       │                      int32                      │                                                  int32                                                   │
├───────┼──────────────────────────────────────────────────┼─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│     1 │                                                1 │                                               1 │                                                                                                        2 │
│     2 │                                                1 │                                               2 │                                                                                                        2 │
│     3 │                                                1 │                                               2 │                                                                                                        2 │
│     4 │                                                6 │                                               6 │                                                                                                     NULL │
│     5 │                                                6 │                                            NULL │                                                                                                     NULL │
└───────┴──────────────────────────────────────────────────┴─────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
## windows aggregates

### an aggregate over a window with no order answers for the whole partition

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, count(*) OVER (), sum(a) OVER (PARTITION BY g), avg(a) OVER (PARTITION BY g), min(a) OVER (), max(a) OVER (PARTITION BY g) FROM t ORDER BY id")
```
---
```output
┌───────┬─────────────────┬──────────────────────────────┬──────────────────────────────┬────────────────┬──────────────────────────────┐
│  id   │ count() OVER () │ sum(a) OVER (PARTITION BY g) │ avg(a) OVER (PARTITION BY g) │ min(a) OVER () │ max(a) OVER (PARTITION BY g) │
│ int32 │      int64      │            int128            │            double            │     int32      │            int32             │
├───────┼─────────────────┼──────────────────────────────┼──────────────────────────────┼────────────────┼──────────────────────────────┤
│     1 │               5 │                            5 │           1.6666666666666667 │              1 │                            2 │
│     2 │               5 │                            5 │           1.6666666666666667 │              1 │                            2 │
│     3 │               5 │                            5 │           1.6666666666666667 │              1 │                            2 │
│     4 │               5 │                            6 │                          6.0 │              1 │                            6 │
│     5 │               5 │                            6 │                          6.0 │              1 │                            6 │
└───────┴─────────────────┴──────────────────────────────┴──────────────────────────────┴────────────────┴──────────────────────────────┘
```

### with an order it runs to the row and the rows that tie with it

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, sum(a) OVER (ORDER BY a), count(a) OVER (ORDER BY a) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬──────────────────────────┬────────────────────────────┐
│  id   │   a   │ sum(a) OVER (ORDER BY a) │ count(a) OVER (ORDER BY a) │
│ int32 │ int32 │          int128          │           int64            │
├───────┼───────┼──────────────────────────┼────────────────────────────┤
│     1 │     1 │                        1 │                          1 │
│     2 │     2 │                        5 │                          3 │
│     3 │     2 │                        5 │                          3 │
│     4 │     6 │                       11 │                          4 │
│     5 │  NULL │                       11 │                          4 │
└───────┴───────┴──────────────────────────┴────────────────────────────┘
```

### DISTINCT counts a value once

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, count(DISTINCT a) OVER (PARTITION BY g), sum(DISTINCT a) OVER () FROM t ORDER BY id")
```
---
```output
┌───────┬─────────────────────────────────────────┬─────────────────────────┐
│  id   │ count(DISTINCT a) OVER (PARTITION BY g) │ sum(DISTINCT a) OVER () │
│ int32 │                  int64                  │         int128          │
├───────┼─────────────────────────────────────────┼─────────────────────────┤
│     1 │                                       2 │                       9 │
│     2 │                                       2 │                       9 │
│     3 │                                       2 │                       9 │
│     4 │                                       1 │                       9 │
│     5 │                                       1 │                       9 │
└───────┴─────────────────────────────────────────┴─────────────────────────┘
```

### other types

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a * 1.5) OVER (ORDER BY id), max(g) OVER (ORDER BY id), avg(a) OVER (ORDER BY id) FROM t ORDER BY id")
```
---
```output
┌───────┬───────────────────────────────────┬───────────────────────────┬───────────────────────────┐
│  id   │ sum((a * 1.5)) OVER (ORDER BY id) │ max(g) OVER (ORDER BY id) │ avg(a) OVER (ORDER BY id) │
│ int32 │           decimal(38,1)           │          varchar          │          double           │
├───────┼───────────────────────────────────┼───────────────────────────┼───────────────────────────┤
│     1 │                               1.5 │ x                         │                       1.0 │
│     2 │                               4.5 │ x                         │                       1.5 │
│     3 │                               7.5 │ x                         │        1.6666666666666667 │
│     4 │                              16.5 │ y                         │                      2.75 │
│     5 │                              16.5 │ y                         │                      2.75 │
└───────┴───────────────────────────────────┴───────────────────────────┴───────────────────────────┘
```

## windows frames

### ROWS BETWEEN counts rows either side of the row

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW), sum(a) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────┐
│  id   │ sum(a) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) │ sum(a) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) │
│ int32 │                               int128                               │                               int128                               │
├───────┼────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│     1 │                                                                  1 │                                                                  3 │
│     2 │                                                                  3 │                                                                  5 │
│     3 │                                                                  4 │                                                                 10 │
│     4 │                                                                  8 │                                                                  8 │
│     5 │                                                                  6 │                                                                  6 │
└───────┴────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────┘
```

### one end alone is the start, the row the end

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a) OVER (ORDER BY id ROWS UNBOUNDED PRECEDING), count(*) OVER (ORDER BY id ROWS 1 PRECEDING) FROM t ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────┐
│  id   │ sum(a) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) │ count() OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) │
│ int32 │                                   int128                                   │                                int64                                │
├───────┼────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┤
│     1 │                                                                          1 │                                                                   1 │
│     2 │                                                                          3 │                                                                   2 │
│     3 │                                                                          5 │                                                                   2 │
│     4 │                                                                         11 │                                                                   2 │
│     5 │                                                                         11 │                                                                   2 │
└───────┴────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────┘
```

### UNBOUNDED FOLLOWING runs to the partition's end

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, count(*) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬─────────────────────────────────────────────────────────────────────────────┐
│  id   │ count() OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) │
│ int32 │                                    int64                                    │
├───────┼─────────────────────────────────────────────────────────────────────────────┤
│     1 │                                                                           5 │
│     2 │                                                                           4 │
│     3 │                                                                           3 │
│     4 │                                                                           2 │
│     5 │                                                                           1 │
└───────┴─────────────────────────────────────────────────────────────────────────────┘
```

### a frame with no rows: a count of none and a NULL sum

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a) OVER (ORDER BY id ROWS BETWEEN 2 FOLLOWING AND 3 FOLLOWING), count(*) OVER (ORDER BY id ROWS BETWEEN 2 FOLLOWING AND 3 FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────┐
│  id   │ sum(a) OVER (ORDER BY id ROWS BETWEEN 2 FOLLOWING AND 3 FOLLOWING) │ count() OVER (ORDER BY id ROWS BETWEEN 2 FOLLOWING AND 3 FOLLOWING) │
│ int32 │                               int128                               │                                int64                                │
├───────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┤
│     1 │                                                                  8 │                                                                   2 │
│     2 │                                                                  6 │                                                                   2 │
│     3 │                                                               NULL │                                                                   1 │
│     4 │                                                               NULL │                                                                   0 │
│     5 │                                                               NULL │                                                                   0 │
└───────┴────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────┘
```

## windows order

### a NULL is last in a window's order unless it says NULLS FIRST

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, row_number() OVER (ORDER BY a DESC, id), row_number() OVER (ORDER BY a DESC NULLS FIRST, id) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬─────────────────────────────────────────┬─────────────────────────────────────────────────────┐
│  id   │   a   │ row_number() OVER (ORDER BY a DESC, id) │ row_number() OVER (ORDER BY a DESC NULLS FIRST, id) │
│ int32 │ int32 │                  int64                  │                        int64                        │
├───────┼───────┼─────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│     1 │     1 │                                       4 │                                                   5 │
│     2 │     2 │                                       2 │                                                   3 │
│     3 │     2 │                                       3 │                                                   4 │
│     4 │     6 │                                       1 │                                                   2 │
│     5 │  NULL │                                       5 │                                                   1 │
└───────┴───────┴─────────────────────────────────────────┴─────────────────────────────────────────────────────┘
```

### a window is a value like any other: in an expression, and in ORDER BY

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a * 10 + rank() OVER (ORDER BY a) AS r FROM t ORDER BY row_number() OVER (ORDER BY id DESC)")
```
---
```output
┌───────┬───────┐
│  id   │   r   │
│ int32 │ int64 │
├───────┼───────┤
│     5 │  NULL │
│     4 │    64 │
│     3 │    22 │
│     2 │    22 │
│     1 │    11 │
└───────┴───────┘
```

### windows are answered after the groups are made, over the groups

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT g, sum(a), sum(sum(a)) OVER (ORDER BY g), rank() OVER (ORDER BY sum(a) DESC) FROM t GROUP BY g ORDER BY g")
```
---
```output
┌─────────┬────────┬───────────────────────────────┬────────────────────────────────────┐
│    g    │ sum(a) │ sum(sum(a)) OVER (ORDER BY g) │ rank() OVER (ORDER BY sum(a) DESC) │
│ varchar │ int128 │            int128             │               int64                │
├─────────┼────────┼───────────────────────────────┼────────────────────────────────────┤
│ x       │      5 │                             5 │                                  2 │
│ y       │      6 │                            11 │                                  1 │
└─────────┴────────┴───────────────────────────────┴────────────────────────────────────┘
```

### with no FROM there is one row

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT row_number() OVER (), 1 + rank() OVER (ORDER BY 1), sum(5) OVER ()")
```
---
```output
┌──────────────────────┬────────────────────────────────┬────────────────┐
│ row_number() OVER () │ (1 + rank() OVER (ORDER BY 1)) │ sum(5) OVER () │
│        int64         │             int64              │     int128     │
├──────────────────────┼────────────────────────────────┼────────────────┤
│                    1 │                              2 │              5 │
└──────────────────────┴────────────────────────────────┴────────────────┘
```

### with no rows the columns keep their types

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT count(*) OVER (), sum(a) OVER (ORDER BY a), lag(g) OVER (ORDER BY id), avg(a) OVER () FROM t WHERE false")
```
---
```output
┌─────────────────┬──────────────────────────┬───────────────────────────┬────────────────┐
│ count() OVER () │ sum(a) OVER (ORDER BY a) │ lag(g) OVER (ORDER BY id) │ avg(a) OVER () │
│      int64      │          int128          │          varchar          │     double     │
└─────────────────┴──────────────────────────┴───────────────────────────┴────────────────┘
                                          0 rows                                         
```

### a derived table's window is a column to filter on

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id FROM (SELECT id, row_number() OVER (ORDER BY a DESC NULLS LAST, id) AS n FROM t) WHERE n <= 2 ORDER BY id")
```
---
```output
┌───────┐
│  id   │
│ int32 │
├───────┤
│     2 │
│     4 │
└───────┘
```

## windows qualify

### QUALIFY keeps the rows a window says: the first of each partition

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, g, a FROM t QUALIFY row_number() OVER (PARTITION BY g ORDER BY a DESC, id) = 1 ORDER BY id")
```
---
```output
┌───────┬─────────┬───────┐
│  id   │    g    │   a   │
│ int32 │ varchar │ int32 │
├───────┼─────────┼───────┤
│     2 │ x       │     2 │
│     4 │ y       │     6 │
└───────┴─────────┴───────┘
```

### after GROUP BY and HAVING

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT g, sum(a) AS s FROM t GROUP BY g HAVING count(*) > 1 QUALIFY rank() OVER (ORDER BY sum(a) DESC) = 1")
```
---
```output
┌─────────┬────────┐
│    g    │   s    │
│ varchar │ int128 │
├─────────┼────────┤
│ y       │      6 │
└─────────┴────────┘
```

### FROM first

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); FROM t SELECT id QUALIFY lag(a) OVER (ORDER BY id) = a")
```
---
```output
┌───────┐
│  id   │
│ int32 │
├───────┤
│     3 │
└───────┘
```

## windows errors

### WHERE is answered before any window

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT a FROM t WHERE row_number() OVER () = 1")
```
---
```output
Binder Error: WHERE clause cannot contain window functions!
```

### and so is HAVING

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT g FROM t GROUP BY g HAVING row_number() OVER () > 1")
```
---
```output
Binder Error: HAVING clause cannot contain window functions!
```

### and GROUP BY

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT g FROM t GROUP BY row_number() OVER ()")
```
---
```output
Binder Error: GROUP BY clause cannot contain window functions!
```

### a window function needs its OVER

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT row_number() FROM t")
```
---
```output
Binder Error: Window functions are not supported here
```

### an aggregate cannot hold a window

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT sum(row_number() OVER ()) FROM t")
```
---
```output
Binder Error: aggregate function calls cannot contain window function calls
```

### nor a window's definition another

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT rank() OVER (ORDER BY rank() OVER ()) FROM t")
```
---
```output
Parser Error: window functions are not allowed in window definitions
```

### UPDATE has none

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); UPDATE t SET a = row_number() OVER ()")
```
---
```output
Binder Error: window functions are not allowed in UPDATE
```

### a scalar function has no window

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT lower(g) OVER () FROM t")
```
---
```output
Catalog Error: lower is not an aggregate function
```

### nor a name no function has

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT nosuch(g) OVER () FROM t")
```
---
```output
Catalog Error: Aggregate Function with name nosuch does not exist!
```

### row_number takes no argument

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT row_number(a) OVER () FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'row_number(INTEGER)'. You might need to add explicit type casts.
```

### lag takes one at least

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT lag() OVER () FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'lag()'. You might need to add explicit type casts.
```

### and a whole number of rows

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT lag(a, g) OVER () FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'lag(INTEGER, VARCHAR)'. You might need to add explicit type casts.
```

### first_value takes one

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT first_value(a, a) OVER () FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'first_value(INTEGER, INTEGER)'. You might need to add explicit type casts.
```

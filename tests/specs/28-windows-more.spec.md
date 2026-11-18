The rest of the windows: more functions, RANGE and GROUPS frames, EXCLUDE,
and a WINDOW clause.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## more windows functions

### ntile deals a partition's rows into buckets as even as they go, the larger first

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, ntile(2) OVER (ORDER BY id), ntile(3) OVER (ORDER BY id), ntile(7) OVER (PARTITION BY g ORDER BY id) FROM t ORDER BY id")
```
---
```output
┌───────┬─────────────────────────────┬─────────────────────────────┬────────────────────────────────────────────┐
│  id   │ ntile(2) OVER (ORDER BY id) │ ntile(3) OVER (ORDER BY id) │ ntile(7) OVER (PARTITION BY g ORDER BY id) │
│ int32 │            int64            │            int64            │                   int64                    │
├───────┼─────────────────────────────┼─────────────────────────────┼────────────────────────────────────────────┤
│     1 │                           1 │                           1 │                                          1 │
│     2 │                           1 │                           1 │                                          2 │
│     3 │                           1 │                           2 │                                          3 │
│     4 │                           2 │                           2 │                                          1 │
│     5 │                           2 │                           3 │                                          2 │
└───────┴─────────────────────────────┴─────────────────────────────┴────────────────────────────────────────────┘
```

### a NULL count of buckets is a NULL bucket

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, ntile(NULL) OVER (ORDER BY id) FROM t ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────┐
│  id   │ ntile(NULL) OVER (ORDER BY id) │
│ int32 │             int64              │
├───────┼────────────────────────────────┤
│     1 │                           NULL │
│     2 │                           NULL │
│     3 │                           NULL │
│     4 │                           NULL │
│     5 │                           NULL │
└───────┴────────────────────────────────┘
```

### nth_value reads the frame by place, NULL where the frame is shorter

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, nth_value(a, 2) OVER (ORDER BY id), nth_value(a, 2) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING), nth_value(g, 9) OVER (ORDER BY id), nth_value(a, 0) OVER (ORDER BY id) FROM t ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────┬────────────────────────────────────┐
│  id   │ nth_value(a, 2) OVER (ORDER BY id) │ nth_value(a, 2) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) │ nth_value(g, 9) OVER (ORDER BY id) │ nth_value(a, 0) OVER (ORDER BY id) │
│ int32 │               int32                │                                            int32                                            │              varchar               │               int32                │
├───────┼────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼────────────────────────────────────┤
│     1 │                               NULL │                                                                                           2 │ NULL                               │                               NULL │
│     2 │                                  2 │                                                                                           2 │ NULL                               │                               NULL │
│     3 │                                  2 │                                                                                           2 │ NULL                               │                               NULL │
│     4 │                                  2 │                                                                                           2 │ NULL                               │                               NULL │
│     5 │                                  2 │                                                                                           2 │ NULL                               │                               NULL │
└───────┴────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────┴────────────────────────────────────┘
```

### percent_rank is a rank as a share of the rows before the last, cume_dist the share of rows up to the row's peers

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, percent_rank() OVER (ORDER BY a), cume_dist() OVER (ORDER BY a), percent_rank() OVER (), cume_dist() OVER (PARTITION BY g ORDER BY a) FROM t ORDER BY id")
```
---
```output
┌───────┬──────────────────────────────────┬───────────────────────────────┬────────────────────────┬──────────────────────────────────────────────┐
│  id   │ percent_rank() OVER (ORDER BY a) │ cume_dist() OVER (ORDER BY a) │ percent_rank() OVER () │ cume_dist() OVER (PARTITION BY g ORDER BY a) │
│ int32 │              double              │            double             │         double         │                    double                    │
├───────┼──────────────────────────────────┼───────────────────────────────┼────────────────────────┼──────────────────────────────────────────────┤
│     1 │                              0.0 │                           0.2 │                    0.0 │                           0.3333333333333333 │
│     2 │                             0.25 │                           0.6 │                    0.0 │                                          1.0 │
│     3 │                             0.25 │                           0.6 │                    0.0 │                                          1.0 │
│     4 │                             0.75 │                           0.8 │                    0.0 │                                          0.5 │
│     5 │                              1.0 │                           1.0 │                    0.0 │                                          1.0 │
└───────┴──────────────────────────────────┴───────────────────────────────┴────────────────────────┴──────────────────────────────────────────────┘
```

### ntile needs a count above none

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT ntile(0) OVER (ORDER BY id) FROM t")
```
---
```output
Invalid Input Error: Argument for ntile must be greater than zero
```

### and takes one argument

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT ntile() OVER () FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'ntile()'. You might need to add explicit type casts.
```

### nth_value takes two

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT nth_value(a) OVER (ORDER BY id) FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'nth_value(INTEGER)'. You might need to add explicit type casts.
```

### percent_rank takes none

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT percent_rank(a) OVER () FROM t")
```
---
```output
Binder Error: No function matches the given name and argument types 'percent_rank(INTEGER)'. You might need to add explicit type casts.
```

## more windows range

### a RANGE frame is the rows whose value is within a distance of the row's

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, sum(a) OVER (ORDER BY a RANGE BETWEEN 1 PRECEDING AND CURRENT ROW), count(*) OVER (ORDER BY a RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────┐
│  id   │   a   │ sum(a) OVER (ORDER BY a RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) │ count() OVER (ORDER BY a RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING) │
│ int32 │ int32 │                               int128                               │                                int64                                │
├───────┼───────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┤
│     1 │     1 │                                                                  1 │                                                                   3 │
│     2 │     2 │                                                                  5 │                                                                   3 │
│     3 │     2 │                                                                  5 │                                                                   3 │
│     4 │     6 │                                                                  6 │                                                                   1 │
│     5 │  NULL │                                                               NULL │                                                                   1 │
└───────┴───────┴────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────┘
```

### its ends may be the partition's, and the row's end is its last peer

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a) OVER (ORDER BY a RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), count(*) OVER (ORDER BY a RANGE BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING), count(*) OVER (ORDER BY a RANGE UNBOUNDED PRECEDING) FROM t ORDER BY id")
```
---
```output
┌───────┬──────────────────────────┬─────────────────────────────────────────────────────────────────────────────┬───────────────────────────┐
│  id   │ sum(a) OVER (ORDER BY a) │ count() OVER (ORDER BY a RANGE BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) │ count() OVER (ORDER BY a) │
│ int32 │          int128          │                                    int64                                    │           int64           │
├───────┼──────────────────────────┼─────────────────────────────────────────────────────────────────────────────┼───────────────────────────┤
│     1 │                        1 │                                                                           5 │                         1 │
│     2 │                        5 │                                                                           4 │                         3 │
│     3 │                        5 │                                                                           4 │                         3 │
│     4 │                       11 │                                                                           2 │                         4 │
│     5 │                       11 │                                                                           1 │                         5 │
└───────┴──────────────────────────┴─────────────────────────────────────────────────────────────────────────────┴───────────────────────────┘
```

### PRECEDING is toward the window's start whichever way it sorts

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, count(*) OVER (ORDER BY a DESC RANGE BETWEEN 1 PRECEDING AND CURRENT ROW), count(*) OVER (ORDER BY a DESC NULLS FIRST RANGE BETWEEN CURRENT ROW AND 4 FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬──────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────┐
│  id   │   a   │ count() OVER (ORDER BY a DESC RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) │ count() OVER (ORDER BY a DESC NULLS FIRST RANGE BETWEEN CURRENT ROW AND 4 FOLLOWING) │
│ int32 │ int32 │                                  int64                                   │                                        int64                                         │
├───────┼───────┼──────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┤
│     1 │     1 │                                                                        3 │                                                                                    1 │
│     2 │     2 │                                                                        2 │                                                                                    3 │
│     3 │     2 │                                                                        2 │                                                                                    3 │
│     4 │     6 │                                                                        1 │                                                                                    3 │
│     5 │  NULL │                                                                        1 │                                                                                    1 │
└───────┴───────┴──────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────┘
```

### a distance may be a fraction

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a) OVER (ORDER BY a RANGE BETWEEN 0.5 PRECEDING AND 1.5 FOLLOWING) FROM t ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────────────────────────────────────────┐
│  id   │ sum(a) OVER (ORDER BY a RANGE BETWEEN 0.5 PRECEDING AND 1.5 FOLLOWING) │
│ int32 │                                 int128                                 │
├───────┼────────────────────────────────────────────────────────────────────────┤
│     1 │                                                                      5 │
│     2 │                                                                      4 │
│     3 │                                                                      4 │
│     4 │                                                                      6 │
│     5 │                                                                   NULL │
└───────┴────────────────────────────────────────────────────────────────────────┘
```

### over dates a distance is an interval, and over doubles a double

```x
(sql "CREATE OR REPLACE TABLE d (id INTEGER, dt DATE, v DOUBLE); INSERT INTO d VALUES (1,'2026-01-01',1.5),(2,'2026-01-02',2.5),(3,'2026-01-05',4.0),(4,'2026-01-06',NULL); SELECT id, count(*) OVER (ORDER BY dt RANGE BETWEEN INTERVAL 1 DAY PRECEDING AND CURRENT ROW), sum(v) OVER (ORDER BY v RANGE BETWEEN 1.5 PRECEDING AND CURRENT ROW) FROM d ORDER BY id")
```
---
```output
┌───────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────┐
│  id   │ count() OVER (ORDER BY dt RANGE BETWEEN to_days(CAST(trunc(CAST(1 AS DOUBLE)) AS INTEGER)) PRECEDING AND CURRENT ROW) │ sum(v) OVER (ORDER BY v RANGE BETWEEN 1.5 PRECEDING AND CURRENT ROW) │
│ int32 │                                                         int64                                                         │                                double                                │
├───────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
│     1 │                                                                                                                     1 │                                                                  1.5 │
│     2 │                                                                                                                     2 │                                                                  4.0 │
│     3 │                                                                                                                     1 │                                                                  6.5 │
│     4 │                                                                                                                     2 │                                                                 NULL │
└───────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

### a distance needs one ORDER BY term

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT count(*) OVER (ORDER BY a, id RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) FROM t")
```
---
```output
Binder Error: RANGE frames must have only one ORDER BY expression
```

### and one at least

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT count(*) OVER (RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) FROM t")
```
---
```output
Binder Error: RANGE frames must have only one ORDER BY expression
```

## more windows groups and exclude

### a GROUPS frame counts runs of peers

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, count(*) OVER (ORDER BY a GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW), sum(a) OVER (ORDER BY a GROUPS BETWEEN 1 FOLLOWING AND 2 FOLLOWING), count(*) OVER (ORDER BY a GROUPS BETWEEN 5 PRECEDING AND 1 PRECEDING) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬──────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────┐
│  id   │   a   │ count() OVER (ORDER BY a GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW) │ sum(a) OVER (ORDER BY a GROUPS BETWEEN 1 FOLLOWING AND 2 FOLLOWING) │ count() OVER (ORDER BY a GROUPS BETWEEN 5 PRECEDING AND 1 PRECEDING) │
│ int32 │ int32 │                                int64                                 │                               int128                                │                                int64                                 │
├───────┼───────┼──────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
│     1 │     1 │                                                                    1 │                                                                  10 │                                                                    0 │
│     2 │     2 │                                                                    3 │                                                                   6 │                                                                    1 │
│     3 │     2 │                                                                    3 │                                                                   6 │                                                                    1 │
│     4 │     6 │                                                                    3 │                                                                NULL │                                                                    3 │
│     5 │  NULL │                                                                    2 │                                                                NULL │                                                                    4 │
└───────┴───────┴──────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

### EXCLUDE leaves out the row

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, count(*) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING EXCLUDE CURRENT ROW), sum(a) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE CURRENT ROW) FROM t ORDER BY id")
```
---
```output
┌───────┬─────────────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  id   │ count() OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING EXCLUDE CURRENT ROW) │ sum(a) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE CURRENT ROW) │
│ int32 │                                          int64                                          │                                                 int128                                                 │
├───────┼─────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│     1 │                                                                                       1 │                                                                                                     10 │
│     2 │                                                                                       2 │                                                                                                      9 │
│     3 │                                                                                       2 │                                                                                                      9 │
│     4 │                                                                                       2 │                                                                                                      5 │
│     5 │                                                                                       1 │                                                                                                     11 │
└───────┴─────────────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### or its peers, with it or without

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, a, count(*) OVER (ORDER BY a ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE GROUP), count(*) OVER (ORDER BY a ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE TIES), count(*) OVER (ORDER BY a RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW EXCLUDE NO OTHERS) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬──────────────────────────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────┬───────────────────────────┐
│  id   │   a   │ count() OVER (ORDER BY a ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE GROUP) │ count() OVER (ORDER BY a ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE TIES) │ count() OVER (ORDER BY a) │
│ int32 │ int32 │                                              int64                                               │                                              int64                                              │           int64           │
├───────┼───────┼──────────────────────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────┤
│     1 │     1 │                                                                                                4 │                                                                                               5 │                         1 │
│     2 │     2 │                                                                                                3 │                                                                                               4 │                         3 │
│     3 │     2 │                                                                                                3 │                                                                                               4 │                         3 │
│     4 │     6 │                                                                                                4 │                                                                                               5 │                         4 │
│     5 │  NULL │                                                                                                4 │                                                                                               5 │                         5 │
└───────┴───────┴──────────────────────────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────┴───────────────────────────┘
```

## more windows named

### WINDOW names a window for the calls OVER it

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, sum(a) OVER w, row_number() OVER w, rank() OVER v FROM t WINDOW w AS (PARTITION BY g ORDER BY id), v AS (ORDER BY a) ORDER BY id")
```
---
```output
┌───────┬──────────────────────────────────────────┬────────────────────────────────────────────────┬──────────────────────────┐
│  id   │ sum(a) OVER (PARTITION BY g ORDER BY id) │ row_number() OVER (PARTITION BY g ORDER BY id) │ rank() OVER (ORDER BY a) │
│ int32 │                  int128                  │                     int64                      │          int64           │
├───────┼──────────────────────────────────────────┼────────────────────────────────────────────────┼──────────────────────────┤
│     1 │                                        1 │                                              1 │                        1 │
│     2 │                                        3 │                                              2 │                        2 │
│     3 │                                        5 │                                              3 │                        2 │
│     4 │                                        6 │                                              1 │                        4 │
│     5 │                                        6 │                                              2 │                        5 │
└───────┴──────────────────────────────────────────┴────────────────────────────────────────────────┴──────────────────────────┘
```

### a window in parentheses may start from a named one and add to it

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, count(*) OVER (w ROWS 1 PRECEDING), sum(a) OVER (p ORDER BY id DESC) FROM t WINDOW w AS (PARTITION BY g ORDER BY id), p AS (PARTITION BY g) ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────┐
│  id   │ count() OVER (PARTITION BY g ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) │ sum(a) OVER (PARTITION BY g ORDER BY id DESC) │
│ int32 │                                       int64                                        │                    int128                     │
├───────┼────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
│     1 │                                                                                  1 │                                             5 │
│     2 │                                                                                  2 │                                             4 │
│     3 │                                                                                  2 │                                             2 │
│     4 │                                                                                  1 │                                             6 │
│     5 │                                                                                  2 │                                          NULL │
└───────┴────────────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────┘
```

### and so may a later name

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id, row_number() OVER o FROM t WINDOW p AS (PARTITION BY g), o AS (p ORDER BY a DESC, id) ORDER BY id")
```
---
```output
┌───────┬────────────────────────────────────────────────────────┐
│  id   │ row_number() OVER (PARTITION BY g ORDER BY a DESC, id) │
│ int32 │                         int64                          │
├───────┼────────────────────────────────────────────────────────┤
│     1 │                                                      3 │
│     2 │                                                      1 │
│     3 │                                                      2 │
│     4 │                                                      1 │
│     5 │                                                      2 │
└───────┴────────────────────────────────────────────────────────┘
```

### QUALIFY comes after it, and reads it

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT id FROM t WINDOW w AS (ORDER BY id) QUALIFY row_number() OVER w = 2")
```
---
```output
┌───────┐
│  id   │
│ int32 │
├───────┤
│     2 │
└───────┘
```

### a name no WINDOW gives

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT sum(a) OVER nope FROM t")
```
---
```output
Parser Error: window "nope" does not exist
```

### a name given twice

```x
(sql "CREATE OR REPLACE TABLE t (id INTEGER, g VARCHAR, a INTEGER); INSERT INTO t VALUES (1,'x',1),(2,'x',2),(3,'x',2),(4,'y',6),(5,'y',NULL); SELECT sum(a) OVER w FROM t WINDOW w AS (ORDER BY id), w AS (ORDER BY a)")
```
---
```output
Parser Error: window "w" is already defined
```

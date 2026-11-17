DECIMAL: a number written with a point, exact, of a width and a scale.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## decimals constants

### a number with a point is a DECIMAL of the digits written

```x
(sql "SELECT 1.5, 0.5, 10.25, 1.50, -1.5")
```
---
```output
┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│     1.5      │     0.5      │    10.25     │     1.50     │     -1.5     │
│ decimal(2,1) │ decimal(2,1) │ decimal(4,2) │ decimal(3,2) │ decimal(2,1) │
├──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│          1.5 │          0.5 │        10.25 │         1.50 │         -1.5 │
└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

### with no digit before the point there is none in the result

```x
(sql "SELECT .5, -.25")
```
---
```output
┌──────────────┬──────────────┐
│      .5      │     -.25     │
│ decimal(1,1) │ decimal(2,2) │
├──────────────┼──────────────┤
│           .5 │         -.25 │
└──────────────┴──────────────┘
```

## decimals arithmetic

### a sum has the wider scale and room to carry

```x
(sql "SELECT 1.5 + 2.25, 1.5 - 2.25, 9.9 + 9.9, 0.1 + 0.2")
```
---
```output
┌──────────────┬──────────────┬──────────────┬──────────────┐
│ (1.5 + 2.25) │ (1.5 - 2.25) │ (9.9 + 9.9)  │ (0.1 + 0.2)  │
│ decimal(4,2) │ decimal(4,2) │ decimal(3,1) │ decimal(3,1) │
├──────────────┼──────────────┼──────────────┼──────────────┤
│         3.75 │        -0.75 │         19.8 │          0.3 │
└──────────────┴──────────────┴──────────────┴──────────────┘
```

### a product has the widths and the scales added

```x
(sql "SELECT 1.5 * 2.25, 9.9 * 9.9, 0.5 * 0.5")
```
---
```output
┌──────────────┬──────────────┬──────────────┐
│ (1.5 * 2.25) │ (9.9 * 9.9)  │ (0.5 * 0.5)  │
│ decimal(5,3) │ decimal(4,2) │ decimal(4,2) │
├──────────────┼──────────────┼──────────────┤
│        3.375 │        98.01 │         0.25 │
└──────────────┴──────────────┴──────────────┘
```

### an integer is a decimal of its type's width

```x
(sql "SELECT 1.5 + 2, 1.5 * 2, 1.5 - 2147483648, 2 - 0.5")
```
---
```output
┌───────────────┬───────────────┬────────────────────┬───────────────┐
│   (1.5 + 2)   │   (1.5 * 2)   │ (1.5 - 2147483648) │   (2 - 0.5)   │
│ decimal(12,1) │ decimal(12,1) │   decimal(21,1)    │ decimal(12,1) │
├───────────────┼───────────────┼────────────────────┼───────────────┤
│           3.5 │           3.0 │      -2147483646.5 │           1.5 │
└───────────────┴───────────────┴────────────────────┴───────────────┘
```

### a minus on an expression

```x
(sql "SELECT -(1.5 + 1.5)")
```
---
```output
┌──────────────────┐
│ (-((1.5 + 1.5))) │
│   decimal(3,1)   │
├──────────────────┤
│             -3.0 │
└──────────────────┘
```

### a NULL operand answers NULL

```x
(sql "SELECT 1.5 * NULL")
```
---
```output
┌──────────────┐
│ (1.5 * NULL) │
│    "null"    │
├──────────────┤
│ NULL         │
└──────────────┘
```

### || shows every digit of the scale

```x
(sql "SELECT 1.50 || 'x'")
```
---
```output
┌───────────────┐
│ (1.50 || 'x') │
│    varchar    │
├───────────────┤
│ 1.50x         │
└───────────────┘
```

## decimals comparison

### decimals compare by value whatever their scales

```x
(sql "SELECT 1.5 = 1.50, 1.5 < 1.51, 2 > 1.99, 1.0 = 1, -0.5 < 0")
```
---
```output
┌──────────────┬──────────────┬────────────┬───────────┬────────────┐
│ (1.5 = 1.50) │ (1.5 < 1.51) │ (2 > 1.99) │ (1.0 = 1) │ (-0.5 < 0) │
│   boolean    │   boolean    │  boolean   │  boolean  │  boolean   │
├──────────────┼──────────────┼────────────┼───────────┼────────────┤
│ true         │ true         │ true       │ true      │ true       │
└──────────────┴──────────────┴────────────┴───────────┴────────────┘
```

## decimals columns

### a DECIMAL column rounds what goes in to its scale, a half away from zero

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT n FROM t")
```
---
```output
┌──────────────┐
│      n       │
│ decimal(6,2) │
├──────────────┤
│         2.00 │
│         0.13 │
│        -1.01 │
│         NULL │
└──────────────┘
```

### DECIMAL alone is 18 digits, 3 after the point; NUMERIC is its other name

```x
(sql "CREATE OR REPLACE TABLE t (a DECIMAL, b NUMERIC(4), c NUMERIC(5,1)); INSERT INTO t VALUES (1.0005, 12, 3.25); FROM t")
```
---
```output
┌───────────────┬──────────────┬──────────────┐
│       a       │      b       │      c       │
│ decimal(18,3) │ decimal(4,0) │ decimal(5,1) │
├───────────────┼──────────────┼──────────────┤
│         1.001 │           12 │          3.3 │
└───────────────┴──────────────┴──────────────┘
```

### a value too wide for the column

```x
(sql "CREATE OR REPLACE TABLE t (a DECIMAL(3,1)); INSERT INTO t VALUES (99.95)")
```
---
```output
Conversion Error: Casting value "99.95" to type DECIMAL(3,1) failed: value is out of range!
```

### decimals sort and filter as numbers

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT n FROM t WHERE n < 1 ORDER BY n")
```
---
```output
┌──────────────┐
│      n       │
│ decimal(6,2) │
├──────────────┤
│        -1.01 │
│         0.13 │
└──────────────┘
```

### a column in arithmetic

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT n + 1, n * n, n * 2, n + d FROM t ORDER BY n")
```
---
```output
┌───────────────┬───────────────┬───────────────┬─────────┐
│    (n + 1)    │    (n * n)    │    (n * 2)    │ (n + d) │
│ decimal(13,2) │ decimal(12,4) │ decimal(16,2) │ double  │
├───────────────┼───────────────┼───────────────┼─────────┤
│         -0.01 │        1.0201 │         -2.02 │    1.49 │
│          1.13 │        0.0169 │          0.26 │    0.23 │
│          3.00 │        4.0000 │          4.00 │     3.0 │
│          NULL │          NULL │          NULL │    NULL │
└───────────────┴───────────────┴───────────────┴─────────┘
```

### a sum is a DECIMAL of 38 digits at the column's scale; min and max keep the type

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT sum(n), min(n), max(n), sum(n) + 1 FROM t")
```
---
```output
┌───────────────┬──────────────┬──────────────┬───────────────┐
│    sum(n)     │    min(n)    │    max(n)    │ (sum(n) + 1)  │
│ decimal(38,2) │ decimal(6,2) │ decimal(6,2) │ decimal(38,2) │
├───────────────┼──────────────┼──────────────┼───────────────┤
│          1.12 │        -1.01 │         2.00 │          2.12 │
└───────────────┴──────────────┴──────────────┴───────────────┘
```

### a group by a decimal

```x
(sql "CREATE OR REPLACE TABLE t (p DECIMAL(5,2), q INTEGER); INSERT INTO t VALUES (1.5, 1), (1.50, 2), (2, 3); SELECT p, sum(q) FROM t GROUP BY p ORDER BY p")
```
---
```output
┌──────────────┬────────┐
│      p       │ sum(q) │
│ decimal(5,2) │ int128 │
├──────────────┼────────┤
│         1.50 │      3 │
│         2.00 │      3 │
└──────────────┴────────┘
```

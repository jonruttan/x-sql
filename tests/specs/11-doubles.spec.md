DOUBLE: a number written with an exponent, the answer of every division,
and a column type.  A double is shown in the fewest digits that read back
as it.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## doubles constants

### a number with an exponent is a DOUBLE, headed as written

```x
(sql "SELECT 1e3, 1.5e-7, 100e0, 2.5E2, -5e-1")
```
---
```output
┌────────┬─────────┬────────┬────────┬────────┐
│  1e3   │ 1.5e-7  │ 100e0  │ 2.5E2  │ -5e-1  │
│ double │ double  │ double │ double │ double │
├────────┼─────────┼────────┼────────┼────────┤
│ 1000.0 │ 1.5e-07 │  100.0 │  250.0 │   -0.5 │
└────────┴─────────┴────────┴────────┴────────┘
```

### written out in full from 0.0001 to fifteen zeros, with an exponent outside

```x
(sql "SELECT 1e15, 1e16, 1e-4, 1e-5, 123456789012345678e0")
```
---
```output
┌────────────────────┬────────┬────────┬────────┬────────────────────────┐
│        1e15        │  1e16  │  1e-4  │  1e-5  │  123456789012345678e0  │
│       double       │ double │ double │ double │         double         │
├────────────────────┼────────┼────────┼────────┼────────────────────────┤
│ 1000000000000000.0 │  1e+16 │ 0.0001 │  1e-05 │ 1.2345678901234568e+17 │
└────────────────────┴────────┴────────┴────────┴────────────────────────┘
```

### the fewest digits that read back

```x
(sql "SELECT 0.1e0 + 0.2e0, 1e0 / 3, 2e0 / 3, 1e23, 4.35e0 * 100")
```
---
```output
┌─────────────────────┬────────────────────┬────────────────────┬────────┬────────────────────┐
│   (0.1e0 + 0.2e0)   │     (1e0 / 3)      │     (2e0 / 3)      │  1e23  │   (4.35e0 * 100)   │
│       double        │       double       │       double       │ double │       double       │
├─────────────────────┼────────────────────┼────────────────────┼────────┼────────────────────┤
│ 0.30000000000000004 │ 0.3333333333333333 │ 0.6666666666666666 │  1e+23 │ 434.99999999999994 │
└─────────────────────┴────────────────────┴────────────────────┴────────┴────────────────────┘
```

### the least and the greatest

```x
(sql "SELECT 5e-324, 1.7976931348623157e308, 2.2250738585072014e-308")
```
---
```output
┌────────┬─────────────────────────┬─────────────────────────┐
│ 5e-324 │ 1.7976931348623157e308  │ 2.2250738585072014e-308 │
│ double │         double          │         double          │
├────────┼─────────────────────────┼─────────────────────────┤
│ 5e-324 │ 1.7976931348623157e+308 │ 2.2250738585072014e-308 │
└────────┴─────────────────────────┴─────────────────────────┘
```

### a constant of more than 38 digits is a DOUBLE

```x
(sql "SELECT 99999999999999999999999999999999999999.5")
```
---
```output
┌──────────────────────────────────────────┐
│ 99999999999999999999999999999999999999.5 │
│                  double                  │
├──────────────────────────────────────────┤
│                                    1e+38 │
└──────────────────────────────────────────┘
```

### a number with no digit before its point, or no point at all

The platform's reader wants digits on both sides of a point before an
exponent; the bundle writes what a number lacks before handing it over.

```x
(sql "SELECT 1e3, .5e1, 1E3, '1e3'::DOUBLE, '.5'::DOUBLE, '7'::DOUBLE, -1e-3")
```
---
```output
┌────────┬────────┬────────┬───────────────────────┬──────────────────────┬─────────────────────┬────────┐
│  1e3   │  .5e1  │  1E3   │ CAST('1e3' AS DOUBLE) │ CAST('.5' AS DOUBLE) │ CAST('7' AS DOUBLE) │ -1e-3  │
│ double │ double │ double │        double         │        double        │       double        │ double │
├────────┼────────┼────────┼───────────────────────┼──────────────────────┼─────────────────────┼────────┤
│ 1000.0 │    5.0 │ 1000.0 │                1000.0 │                  0.5 │                 7.0 │ -0.001 │
└────────┴────────┴────────┴───────────────────────┴──────────────────────┴─────────────────────┴────────┘
```

## doubles arithmetic

### / answers a DOUBLE whatever it divides

```x
(sql "SELECT 1 / 2, 7 / 2, 6 / 3, 1.5 / 2, 1e0 / 4")
```
---
```output
┌─────────┬─────────┬─────────┬───────────┬───────────┐
│ (1 / 2) │ (7 / 2) │ (6 / 3) │ (1.5 / 2) │ (1e0 / 4) │
│ double  │ double  │ double  │  double   │  double   │
├─────────┼─────────┼─────────┼───────────┼───────────┤
│     0.5 │     3.5 │     2.0 │      0.75 │      0.25 │
└─────────┴─────────┴─────────┴───────────┴───────────┘
```

### a double with an integer or a decimal is a double

```x
(sql "SELECT 1e0 + 1, 2 * 1.5e0, 1.5 + 1e0, 1e0 - 0.25")
```
---
```output
┌───────────┬─────────────┬─────────────┬──────────────┐
│ (1e0 + 1) │ (2 * 1.5e0) │ (1.5 + 1e0) │ (1e0 - 0.25) │
│  double   │   double    │   double    │    double    │
├───────────┼─────────────┼─────────────┼──────────────┤
│       2.0 │         3.0 │         2.5 │         0.75 │
└───────────┴─────────────┴─────────────┴──────────────┘
```

### an overflow is an infinity, and a division by zero is one or no number

```x
(sql "SELECT 1e308 * 10, -1e308 * 10, 1 / 0, 1e0 / 0, 0e0 / 0")
```
---
```output
┌──────────────┬───────────────┬─────────┬───────────┬───────────┐
│ (1e308 * 10) │ (-1e308 * 10) │ (1 / 0) │ (1e0 / 0) │ (0e0 / 0) │
│    double    │    double     │ double  │  double   │  double   │
├──────────────┼───────────────┼─────────┼───────────┼───────────┤
│          inf │          -inf │     inf │       inf │       nan │
└──────────────┴───────────────┴─────────┴───────────┴───────────┘
```

### a minus on an expression

```x
(sql "SELECT -(1e0 + 1), -(1 / 4)")
```
---
```output
┌────────────────┬──────────────┐
│ (-((1e0 + 1))) │ (-((1 / 4))) │
│     double     │    double    │
├────────────────┼──────────────┤
│           -2.0 │        -0.25 │
└────────────────┴──────────────┘
```

### a NULL operand answers NULL

```x
(sql "SELECT 1e0 + NULL, NULL / 2")
```
---
```output
┌──────────────┬────────────┐
│ (1e0 + NULL) │ (NULL / 2) │
│    double    │   double   │
├──────────────┼────────────┤
│         NULL │       NULL │
└──────────────┴────────────┘
```

### || shows a double as a result does

```x
(sql "SELECT 2e0 || 'x', 1 / 3 || ''")
```
---
```output
┌──────────────┬────────────────────┐
│ (2e0 || 'x') │  ((1 / 3) || '')   │
│   varchar    │      varchar       │
├──────────────┼────────────────────┤
│ 2.0x         │ 0.3333333333333333 │
└──────────────┴────────────────────┘
```

## doubles comparison

### a double compares with any number

```x
(sql "SELECT 1e0 = 1, 1e0 < 1.5, 0.1e0 = 0.1, 2.5e0 > 2, 1 / 2 = 0.5")
```
---
```output
┌───────────┬─────────────┬───────────────┬─────────────┬─────────────────┐
│ (1e0 = 1) │ (1e0 < 1.5) │ (0.1e0 = 0.1) │ (2.5e0 > 2) │ ((1 / 2) = 0.5) │
│  boolean  │   boolean   │    boolean    │   boolean   │     boolean     │
├───────────┼─────────────┼───────────────┼─────────────┼─────────────────┤
│ true      │ true        │ true          │ true        │ true            │
└───────────┴─────────────┴───────────────┴─────────────┴─────────────────┘
```

### an integer compares as the double nearest it

```x
(sql "SELECT 9007199254740993 = 9007199254740992e0")
```
---
```output
┌─────────────────────────────────────────┐
│ (9007199254740993 = 9007199254740992e0) │
│                 boolean                 │
├─────────────────────────────────────────┤
│ true                                    │
└─────────────────────────────────────────┘
```

## doubles columns

### a DOUBLE column takes integers, decimals and doubles

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT d FROM t")
```
---
```output
┌────────┐
│   d    │
│ double │
├────────┤
│    1.0 │
│    0.1 │
│    2.5 │
│   NULL │
└────────┘
```

### FLOAT8 is its other name

```x
(sql "CREATE OR REPLACE TABLE t (f FLOAT8); INSERT INTO t VALUES (4); FROM t")
```
---
```output
┌────────┐
│   f    │
│ double │
├────────┤
│    4.0 │
└────────┘
```

### doubles sort and filter as numbers

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT d FROM t WHERE d > 0.5 ORDER BY d DESC")
```
---
```output
┌────────┐
│   d    │
│ double │
├────────┤
│    2.5 │
│    1.0 │
└────────┘
```

### sum, min and max of doubles are doubles

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT sum(d), min(d), max(d) FROM t")
```
---
```output
┌────────┬────────┬────────┐
│ sum(d) │ min(d) │ max(d) │
│ double │ double │ double │
├────────┼────────┼────────┤
│    3.6 │    0.1 │    2.5 │
└────────┴────────┴────────┘
```

### avg is a DOUBLE of any number, and NULL of none

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT avg(d), avg(k), avg(n), avg(1) FROM t; SELECT avg(k) FROM t WHERE k > 9")
```
---
```output
┌────────┬────────┬─────────────────────┬────────┐
│ avg(d) │ avg(k) │       avg(n)        │ avg(1) │
│ double │ double │       double        │ double │
├────────┼────────┼─────────────────────┼────────┤
│    1.2 │    5.0 │ 0.37333333333333335 │    1.0 │
└────────┴────────┴─────────────────────┴────────┘
┌────────┐
│ avg(k) │
│ double │
├────────┤
│   NULL │
└────────┘
```

### a group by a double

```x
(sql "CREATE OR REPLACE TABLE t (d DOUBLE, n DECIMAL(6,2), k INTEGER); INSERT INTO t VALUES (1, 2, 3), (0.1, 0.125, 7), (2.5e0, -1.005, NULL), (NULL, NULL, NULL); SELECT d > 1, count(*), avg(k) FROM t GROUP BY ALL ORDER BY 1")
```
---
```output
┌─────────┬──────────────┬────────┐
│ (d > 1) │ count_star() │ avg(k) │
│ boolean │    int64     │ double │
├─────────┼──────────────┼────────┤
│ false   │            2 │    5.0 │
│ true    │            1 │   NULL │
│ NULL    │            1 │   NULL │
└─────────┴──────────────┴────────┘
```

The functions of one row's values.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## functions text

### lower, upper and length, which counts characters

```x
(sql "SELECT lower('AbC'), upper('abc'), length('héllo'), length('')")
```
---
```output
┌──────────────┬──────────────┬─────────────────┬────────────┐
│ lower('AbC') │ upper('abc') │ length('héllo') │ length('') │
│   varchar    │   varchar    │      int64      │   int64    │
├──────────────┼──────────────┼─────────────────┼────────────┤
│ abc          │ ABC          │               5 │          0 │
└──────────────┴──────────────┴─────────────────┴────────────┘
```

### trim, ltrim and rtrim take blanks off the ends

```x
(sql "SELECT trim('  x '), ltrim('  x '), rtrim('  x ')")
```
---
```output
┌────────────────┬───────────────┬───────────────┐
│ "trim"('  x ') │ ltrim('  x ') │ rtrim('  x ') │
│    varchar     │    varchar    │    varchar    │
├────────────────┼───────────────┼───────────────┤
│ x              │ x             │   x           │
└────────────────┴───────────────┴───────────────┘
```

### substring counts from 1, and substr is its other name

```x
(sql "SELECT substring('héllo', 2, 3), substring('hello', 2), substr('hello', 1, 1), substring('hello', 4, 10)")
```
---
```output
┌────────────────────────────┬─────────────────────────┬───────────────────────┬─────────────────────────────┐
│ "substring"('héllo', 2, 3) │ "substring"('hello', 2) │ substr('hello', 1, 1) │ "substring"('hello', 4, 10) │
│          varchar           │         varchar         │        varchar        │           varchar           │
├────────────────────────────┼─────────────────────────┼───────────────────────┼─────────────────────────────┤
│ éll                        │ ello                    │ h                     │ lo                          │
└────────────────────────────┴─────────────────────────┴───────────────────────┴─────────────────────────────┘
```

### a start before the text, and one counted from the end

```x
(sql "SELECT substring('hello', 0, 2), substring('hello', -2), substring('hello', -3, 2)")
```
---
```output
┌────────────────────────────┬──────────────────────────┬─────────────────────────────┐
│ "substring"('hello', 0, 2) │ "substring"('hello', -2) │ "substring"('hello', -3, 2) │
│          varchar           │         varchar          │           varchar           │
├────────────────────────────┼──────────────────────────┼─────────────────────────────┤
│ h                          │ lo                       │ ll                          │
└────────────────────────────┴──────────────────────────┴─────────────────────────────┘
```

### left and right, a negative count leaving that many off

```x
(sql "SELECT left('héllo', 2), right('hello', 2), left('abc', -1), right('abc', -1), left('abc', 9)")
```
---
```output
┌────────────────────┬─────────────────────┬───────────────────┬────────────────────┬──────────────────┐
│ "left"('héllo', 2) │ "right"('hello', 2) │ "left"('abc', -1) │ "right"('abc', -1) │ "left"('abc', 9) │
│      varchar       │       varchar       │      varchar      │      varchar       │     varchar      │
├────────────────────┼─────────────────────┼───────────────────┼────────────────────┼──────────────────┤
│ hé                 │ lo                  │ ab                │ bc                 │ abc              │
└────────────────────┴─────────────────────┴───────────────────┴────────────────────┴──────────────────┘
```

### replace, reverse and repeat

```x
(sql "SELECT replace('aXbX', 'X', '-'), replace('abc', 'z', '-'), reverse('héllo'), repeat('ab', 3), repeat('x', 0)")
```
---
```output
┌─────────────────────────────┬────────────────────────────┬──────────────────┬─────────────────┬────────────────┐
│ "replace"('aXbX', 'X', '-') │ "replace"('abc', 'z', '-') │ reverse('héllo') │ repeat('ab', 3) │ repeat('x', 0) │
│           varchar           │          varchar           │     varchar      │     varchar     │    varchar     │
├─────────────────────────────┼────────────────────────────┼──────────────────┼─────────────────┼────────────────┤
│ a-b-                        │ abc                        │ olléh            │ ababab          │                │
└─────────────────────────────┴────────────────────────────┴──────────────────┴─────────────────┴────────────────┘
```

### starts_with and contains

```x
(sql "SELECT starts_with('abc', 'ab'), starts_with('abc', 'bc'), contains('abc', 'bc'), contains('abc', 'x')")
```
---
```output
┌──────────────────────────┬──────────────────────────┬───────────────────────┬──────────────────────┐
│ starts_with('abc', 'ab') │ starts_with('abc', 'bc') │ contains('abc', 'bc') │ contains('abc', 'x') │
│         boolean          │         boolean          │        boolean        │       boolean        │
├──────────────────────────┼──────────────────────────┼───────────────────────┼──────────────────────┤
│ true                     │ false                    │ true                  │ false                │
└──────────────────────────┴──────────────────────────┴───────────────────────┴──────────────────────┘
```

### concat shows each argument as a result would, and leaves NULLs out

```x
(sql "SELECT concat('a', 1, NULL, 'b'), concat(1.50, true), concat(NULL)")
```
---
```output
┌───────────────────────────┬────────────────────┬──────────────┐
│ concat('a', 1, NULL, 'b') │ concat(1.50, true) │ concat(NULL) │
│          varchar          │      varchar       │   varchar    │
├───────────────────────────┼────────────────────┼──────────────┤
│ a1b                       │ 1.50true           │              │
└───────────────────────────┴────────────────────┴──────────────┘
```

### a NULL argument answers NULL

```x
(sql "SELECT lower(NULL), length(NULL), substring(NULL, 1), replace('a', NULL, 'b'), left('a', NULL)")
```
---
```output
┌─────────────┬──────────────┬──────────────────────┬───────────────────────────┬───────────────────┐
│ lower(NULL) │ length(NULL) │ "substring"(NULL, 1) │ "replace"('a', NULL, 'b') │ "left"('a', NULL) │
│   varchar   │    int64     │       varchar        │          varchar          │      varchar      │
├─────────────┼──────────────┼──────────────────────┼───────────────────────────┼───────────────────┤
│ NULL        │         NULL │ NULL                 │ NULL                      │ NULL              │
└─────────────┴──────────────┴──────────────────────┴───────────────────────────┴───────────────────┘
```

### over the rows of a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT upper(b), length(b) FROM t WHERE b IS NOT NULL ORDER BY length(b) DESC, b")
```
---
```output
┌──────────┬───────────┐
│ upper(b) │ length(b) │
│ varchar  │   int64   │
├──────────┼───────────┤
│ BANANA   │         6 │
│ CHERRY   │         6 │
│ APPLE    │         5 │
│ DATE     │         4 │
└──────────┴───────────┘
```

## functions numbers

### abs keeps its argument's type

```x
(sql "SELECT abs(-5), abs(5), abs(-1.5), abs(-1e0), abs(-2147483649)")
```
---
```output
┌─────────┬────────┬──────────────┬───────────┬──────────────────┐
│ abs(-5) │ abs(5) │  abs(-1.5)   │ abs(-1e0) │ abs(-2147483649) │
│  int32  │ int32  │ decimal(2,1) │  double   │      int64       │
├─────────┼────────┼──────────────┼───────────┼──────────────────┤
│       5 │      5 │          1.5 │       1.0 │       2147483649 │
└─────────┴────────┴──────────────┴───────────┴──────────────────┘
```

### floor, ceil and round of a decimal are a decimal with no fraction

```x
(sql "SELECT floor(2.7), ceil(2.1), round(2.5), round(-2.5), floor(-2.5), ceil(-2.5), ceiling(2.1)")
```
---
```output
┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│  floor(2.7)  │  ceil(2.1)   │  round(2.5)  │ round(-2.5)  │ floor(-2.5)  │  ceil(-2.5)  │ ceiling(2.1) │
│ decimal(2,0) │ decimal(2,0) │ decimal(2,0) │ decimal(2,0) │ decimal(2,0) │ decimal(2,0) │ decimal(2,0) │
├──────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│            2 │            3 │            3 │           -3 │           -3 │           -2 │            3 │
└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

### of a double they are doubles, a half rounding away from zero

```x
(sql "SELECT floor(2.7e0), ceil(-2.1e0), round(2.5e0), round(-2.5e0), round(0.5e0)")
```
---
```output
┌──────────────┬──────────────┬──────────────┬───────────────┬──────────────┐
│ floor(2.7e0) │ ceil(-2.1e0) │ round(2.5e0) │ round(-2.5e0) │ round(0.5e0) │
│    double    │    double    │    double    │    double     │    double    │
├──────────────┼──────────────┼──────────────┼───────────────┼──────────────┤
│          2.0 │         -2.0 │          3.0 │          -3.0 │          1.0 │
└──────────────┴──────────────┴──────────────┴───────────────┴──────────────┘
```

### sqrt and power answer doubles; pow is power's other name

```x
(sql "SELECT sqrt(16), sqrt(2), power(2, 10), pow(2, 0.5), power(2e0, -1)")
```
---
```output
┌──────────┬────────────────────┬──────────────┬────────────────────┬────────────────┐
│ sqrt(16) │      sqrt(2)       │ power(2, 10) │    pow(2, 0.5)     │ power(2e0, -1) │
│  double  │       double       │    double    │       double       │     double     │
├──────────┼────────────────────┼──────────────┼────────────────────┼────────────────┤
│      4.0 │ 1.4142135623730951 │       1024.0 │ 1.4142135623730951 │            0.5 │
└──────────┴────────────────────┴──────────────┴────────────────────┴────────────────┘
```

### a NULL argument answers NULL

```x
(sql "SELECT abs(NULL), sqrt(NULL), power(2, NULL)")
```
---
```output
┌───────────┬────────────┬────────────────┐
│ abs(NULL) │ sqrt(NULL) │ power(2, NULL) │
│   int64   │   double   │     double     │
├───────────┼────────────┼────────────────┤
│      NULL │       NULL │           NULL │
└───────────┴────────────┴────────────────┘
```

## functions nulls and choices

### coalesce is the first argument that is not NULL, in the type they all go into

```x
(sql "SELECT coalesce(NULL, 1, 2), coalesce(1, 2.5), coalesce(NULL, 'x'), coalesce(NULL, NULL)")
```
---
```output
┌──────────────────────┬──────────────────┬─────────────────────┬──────────────────────┐
│ COALESCE(NULL, 1, 2) │ COALESCE(1, 2.5) │ COALESCE(NULL, 'x') │ COALESCE(NULL, NULL) │
│        int32         │  decimal(11,1)   │       varchar       │        "null"        │
├──────────────────────┼──────────────────┼─────────────────────┼──────────────────────┤
│                    1 │              1.0 │ x                   │ NULL                 │
└──────────────────────┴──────────────────┴─────────────────────┴──────────────────────┘
```

### ifnull is coalesce of two

```x
(sql "SELECT ifnull(NULL, 'x'), ifnull(1, 2)")
```
---
```output
┌─────────────────────┬────────────────┐
│ COALESCE(NULL, 'x') │ COALESCE(1, 2) │
│       varchar       │     int32      │
├─────────────────────┼────────────────┤
│ x                   │              1 │
└─────────────────────┴────────────────┘
```

### nullif is NULL when its two arguments are equal

```x
(sql "SELECT nullif(1, 1), nullif(1, 2), nullif('a', 'a'), nullif(NULL, 1)")
```
---
```output
┌────────────────┬────────────────┬────────────────────┬───────────────────┐
│ "nullif"(1, 1) │ "nullif"(1, 2) │ "nullif"('a', 'a') │ "nullif"(NULL, 1) │
│     int32      │     int32      │      varchar       │      "null"       │
├────────────────┼────────────────┼────────────────────┼───────────────────┤
│           NULL │              1 │ NULL               │ NULL              │
└────────────────┴────────────────┴────────────────────┴───────────────────┘
```

### greatest and least leave NULLs out

```x
(sql "SELECT greatest(1, 5, 3), least(1, NULL, 3), greatest(1, 2.5), greatest('a', 'b'), least(NULL, NULL)")
```
---
```output
┌───────────────────┬───────────────────┬──────────────────┬────────────────────┬───────────────────┐
│ greatest(1, 5, 3) │ least(1, NULL, 3) │ greatest(1, 2.5) │ greatest('a', 'b') │ least(NULL, NULL) │
│       int32       │       int32       │  decimal(11,1)   │      varchar       │      "null"       │
├───────────────────┼───────────────────┼──────────────────┼────────────────────┼───────────────────┤
│                 5 │                 1 │              2.5 │ b                  │ NULL              │
└───────────────────┴───────────────────┴──────────────────┴────────────────────┴───────────────────┘
```

### typeof names a value's type

```x
(sql "SELECT typeof(1), typeof(2147483648), typeof(1.5), typeof(1e0), typeof('x'), typeof(true), typeof(NULL)")
```
---
```output
┌───────────┬────────────────────┬──────────────┬─────────────┬─────────────┬──────────────┬──────────────┐
│ typeof(1) │ typeof(2147483648) │ typeof(1.5)  │ typeof(1e0) │ typeof('x') │ typeof(true) │ typeof(NULL) │
│  varchar  │      varchar       │   varchar    │   varchar   │   varchar   │   varchar    │   varchar    │
├───────────┼────────────────────┼──────────────┼─────────────┼─────────────┼──────────────┼──────────────┤
│ INTEGER   │ BIGINT             │ DECIMAL(2,1) │ DOUBLE      │ VARCHAR     │ BOOLEAN      │ "NULL"       │
└───────────┴────────────────────┴──────────────┴─────────────┴─────────────┴──────────────┴──────────────┘
```

### functions nest, and take aggregates

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT upper(coalesce(max(b), 'none')), abs(min(a) - max(a)), round(avg(a)) FROM t")
```
---
```output
┌─────────────────────────────────┬────────────────────────┬───────────────┐
│ upper(COALESCE(max(b), 'none')) │ abs((min(a) - max(a))) │ round(avg(a)) │
│             varchar             │         int32          │    double     │
├─────────────────────────────────┼────────────────────────┼───────────────┤
│ DATE                            │                      4 │           3.0 │
└─────────────────────────────────┴────────────────────────┴───────────────┘
```

### a function in WHERE, GROUP BY and ORDER BY

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT length(b) AS n, count(*) FROM t WHERE coalesce(a, 0) < 5 GROUP BY length(b) ORDER BY n")
```
---
```output
┌───────┬──────────────┐
│   n   │ count_star() │
│ int64 │    int64     │
├───────┼──────────────┤
│     4 │            1 │
│     5 │            1 │
│     6 │            2 │
└───────┴──────────────┘
```

## functions errors

### a function there is not

```x
(sql "SELECT nope(1)")
```
---
```output
Catalog Error: Scalar Function with name nope does not exist!
```

### text asked of a number

DuckDB names a constant's type INTEGER_LITERAL and lists its candidates.

```x
(sql "SELECT lower(1)")
```
---
```output
Binder Error: No function matches the given name and argument types 'lower(INTEGER)'.
```

### too few arguments

DuckDB lists its candidates.

```x
(sql "SELECT length()")
```
---
```output
Binder Error: No function matches the given name and argument types 'length()'.
```

### a column in a function is still a column to GROUP BY

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT upper(b), count(*) FROM t")
```
---
```output
Binder Error: column "b" must appear in the GROUP BY clause or must be part of an aggregate function.
```

### the square root of a negative number is no number

```x
(sql "SELECT sqrt(-1e0), sqrt(-4)")
```
---
```output
┌────────────┬──────────┐
│ sqrt(-1e0) │ sqrt(-4) │
│   double   │  double  │
├────────────┼──────────┤
│        nan │      nan │
└────────────┴──────────┘
```

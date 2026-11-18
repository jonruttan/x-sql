TINYINT, SMALLINT and REAL.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## small integers

### TINYINT and SMALLINT, and their other names

```x
(sql "SELECT 1::TINYINT a, 127::TINYINT b, (-128)::TINYINT c, 1::SMALLINT d, (-32768)::SMALLINT e, 1::INT1 f, 1::INT2 g, 1::SHORT h, typeof(1::INT1), typeof(1::SHORT)")
```
---
```output
┌──────┬──────┬──────┬───────┬────────┬──────┬───────┬───────┬─────────────────────────┬──────────────────────────┐
│  a   │  b   │  c   │   d   │   e    │  f   │   g   │   h   │ typeof(CAST(1 AS INT1)) │ typeof(CAST(1 AS SHORT)) │
│ int8 │ int8 │ int8 │ int16 │ int16  │ int8 │ int16 │ int16 │         varchar         │         varchar          │
├──────┼──────┼──────┼───────┼────────┼──────┼───────┼───────┼─────────────────────────┼──────────────────────────┤
│    1 │  127 │ -128 │     1 │ -32768 │    1 │     1 │     1 │ TINYINT                 │ SMALLINT                 │
└──────┴──────┴──────┴───────┴────────┴──────┴───────┴───────┴─────────────────────────┴──────────────────────────┘
```

### arithmetic stays in the wider of the two

```x
(sql "SELECT typeof(1::TINYINT + 1::TINYINT), typeof(1::TINYINT + 1::SMALLINT), typeof(1::SMALLINT * 2::INTEGER), typeof(1::TINYINT - 1::BIGINT), typeof(-(1::TINYINT)), typeof(7::TINYINT // 2::TINYINT), typeof(7::TINYINT % 2::SMALLINT)")
```
---
```output
┌───────────────────────────────────────────────────┬────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬──────────────────────────────────────────────────┬─────────────────────────────────┬────────────────────────────────────────────────────┬────────────────────────────────────────────────────┐
│ typeof((CAST(1 AS TINYINT) + CAST(1 AS TINYINT))) │ typeof((CAST(1 AS TINYINT) + CAST(1 AS SMALLINT))) │ typeof((CAST(1 AS SMALLINT) * CAST(2 AS INTEGER))) │ typeof((CAST(1 AS TINYINT) - CAST(1 AS BIGINT))) │ typeof((-(CAST(1 AS TINYINT)))) │ typeof((CAST(7 AS TINYINT) // CAST(2 AS TINYINT))) │ typeof((CAST(7 AS TINYINT) % CAST(2 AS SMALLINT))) │
│                      varchar                      │                      varchar                       │                      varchar                       │                     varchar                      │             varchar             │                      varchar                       │                      varchar                       │
├───────────────────────────────────────────────────┼────────────────────────────────────────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────────────────┼─────────────────────────────────┼────────────────────────────────────────────────────┼────────────────────────────────────────────────────┤
│ TINYINT                                           │ SMALLINT                                           │ INTEGER                                            │ BIGINT                                           │ TINYINT                         │ TINYINT                                            │ SMALLINT                                           │
└───────────────────────────────────────────────────┴────────────────────────────────────────────────────┴────────────────────────────────────────────────────┴──────────────────────────────────────────────────┴─────────────────────────────────┴────────────────────────────────────────────────────┴────────────────────────────────────────────────────┘
```

### an integer constant beside one is its type when it fits, and an INTEGER when it does not

```x
(sql "SELECT typeof(1::TINYINT + 1), typeof(1 + 1::SMALLINT), typeof(1::TINYINT + 200), typeof(1::SMALLINT * 40000), 100::TINYINT + 27, 7::TINYINT // 2, 7::SMALLINT % 4")
```
---
```output
┌──────────────────────────────────┬───────────────────────────────────┬────────────────────────────────────┬───────────────────────────────────────┬─────────────────────────────┬───────────────────────────┬───────────────────────────┐
│ typeof((CAST(1 AS TINYINT) + 1)) │ typeof((1 + CAST(1 AS SMALLINT))) │ typeof((CAST(1 AS TINYINT) + 200)) │ typeof((CAST(1 AS SMALLINT) * 40000)) │ (CAST(100 AS TINYINT) + 27) │ (CAST(7 AS TINYINT) // 2) │ (CAST(7 AS SMALLINT) % 4) │
│             varchar              │              varchar              │              varchar               │                varchar                │            int8             │           int8            │           int16           │
├──────────────────────────────────┼───────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────┼─────────────────────────────┼───────────────────────────┼───────────────────────────┤
│ TINYINT                          │ SMALLINT                          │ INTEGER                            │ INTEGER                               │                         127 │                         3 │                         3 │
└──────────────────────────────────┴───────────────────────────────────┴────────────────────────────────────┴───────────────────────────────────────┴─────────────────────────────┴───────────────────────────┴───────────────────────────┘
```

### with a decimal the answer is a decimal with room for it, and / answers a DOUBLE

```x
(sql "SELECT typeof(1::TINYINT + 1.5), typeof(1::SMALLINT * 1.5), typeof(1::TINYINT + 1::DECIMAL(5,2)), typeof(1::TINYINT / 2::TINYINT), 7::TINYINT / 2::TINYINT, 1::SMALLINT * 1.5")
```
---
```output
┌────────────────────────────────────┬─────────────────────────────────────┬─────────────────────────────────────────────────────────┬───────────────────────────────────────────────────┬───────────────────────────────────────────┬─────────────────────────────┐
│ typeof((CAST(1 AS TINYINT) + 1.5)) │ typeof((CAST(1 AS SMALLINT) * 1.5)) │ typeof((CAST(1 AS TINYINT) + CAST(1 AS DECIMAL(5, 2)))) │ typeof((CAST(1 AS TINYINT) / CAST(2 AS TINYINT))) │ (CAST(7 AS TINYINT) / CAST(2 AS TINYINT)) │ (CAST(1 AS SMALLINT) * 1.5) │
│              varchar               │               varchar               │                         varchar                         │                      varchar                      │                  double                   │        decimal(7,1)         │
├────────────────────────────────────┼─────────────────────────────────────┼─────────────────────────────────────────────────────────┼───────────────────────────────────────────────────┼───────────────────────────────────────────┼─────────────────────────────┤
│ DECIMAL(5,1)                       │ DECIMAL(7,1)                        │ DECIMAL(6,2)                                            │ DOUBLE                                            │                                       3.5 │                         1.5 │
└────────────────────────────────────┴─────────────────────────────────────┴─────────────────────────────────────────────────────────┴───────────────────────────────────────────────────┴───────────────────────────────────────────┴─────────────────────────────┘
```

### a fraction is rounded as it goes in, a half away from zero

```x
(sql "SELECT 1.5::TINYINT, 2.5::TINYINT, 127.4::TINYINT, (-1.5)::SMALLINT, 2.5::DOUBLE::TINYINT, '12'::TINYINT, ' -7 '::SMALLINT, true::TINYINT")
```
---
```output
┌──────────────────────┬──────────────────────┬────────────────────────┬────────────────────────┬──────────────────────────────────────┬───────────────────────┬──────────────────────────┬───────────────────────┐
│ CAST(1.5 AS TINYINT) │ CAST(2.5 AS TINYINT) │ CAST(127.4 AS TINYINT) │ CAST(-1.5 AS SMALLINT) │ CAST(CAST(2.5 AS DOUBLE) AS TINYINT) │ CAST('12' AS TINYINT) │ CAST(' -7 ' AS SMALLINT) │ CAST(true AS TINYINT) │
│         int8         │         int8         │          int8          │         int16          │                 int8                 │         int8          │          int16           │         int8          │
├──────────────────────┼──────────────────────┼────────────────────────┼────────────────────────┼──────────────────────────────────────┼───────────────────────┼──────────────────────────┼───────────────────────┤
│                    2 │                    3 │                    127 │                     -2 │                                    2 │                    12 │                       -7 │                     1 │
└──────────────────────┴──────────────────────┴────────────────────────┴────────────────────────┴──────────────────────────────────────┴───────────────────────┴──────────────────────────┴───────────────────────┘
```

### and comes out as other types

```x
(sql "SELECT 5::TINYINT::VARCHAR, 5::TINYINT::DOUBLE, typeof(5::TINYINT::DECIMAL), 5::SMALLINT::DECIMAL(6,2), 5::TINYINT::BIGINT, 0::TINYINT::BOOLEAN, 5::TINYINT || 'x'")
```
---
```output
┌─────────────────────────────────────┬────────────────────────────────────┬─────────────────────────────────────────────┬────────────────────────────────────────────┬────────────────────────────────────┬─────────────────────────────────────┬─────────────────────────────┐
│ CAST(CAST(5 AS TINYINT) AS VARCHAR) │ CAST(CAST(5 AS TINYINT) AS DOUBLE) │ typeof(CAST(CAST(5 AS TINYINT) AS DECIMAL)) │ CAST(CAST(5 AS SMALLINT) AS DECIMAL(6, 2)) │ CAST(CAST(5 AS TINYINT) AS BIGINT) │ CAST(CAST(0 AS TINYINT) AS BOOLEAN) │ (CAST(5 AS TINYINT) || 'x') │
│               varchar               │               double               │                   varchar                   │                decimal(6,2)                │               int64                │               boolean               │           varchar           │
├─────────────────────────────────────┼────────────────────────────────────┼─────────────────────────────────────────────┼────────────────────────────────────────────┼────────────────────────────────────┼─────────────────────────────────────┼─────────────────────────────┤
│ 5                                   │                                5.0 │ DECIMAL(18,3)                               │                                       5.00 │                                  5 │ false                               │ 5x                          │
└─────────────────────────────────────┴────────────────────────────────────┴─────────────────────────────────────────────┴────────────────────────────────────────────┴────────────────────────────────────┴─────────────────────────────────────┴─────────────────────────────┘
```

### they compare with every number

```x
(sql "SELECT 1::TINYINT = 1::BIGINT, 1::TINYINT < 1.5, 2::SMALLINT > 1::TINYINT, 1::TINYINT = 1.0::DOUBLE, 3::TINYINT BETWEEN 1 AND 5, 3::SMALLINT IN (1, 3)")
```
---
```output
┌──────────────────────────────────────────┬────────────────────────────┬────────────────────────────────────────────┬────────────────────────────────────────────┬──────────────────────────────────────┬─────────────────────────────────┐
│ (CAST(1 AS TINYINT) = CAST(1 AS BIGINT)) │ (CAST(1 AS TINYINT) < 1.5) │ (CAST(2 AS SMALLINT) > CAST(1 AS TINYINT)) │ (CAST(1 AS TINYINT) = CAST(1.0 AS DOUBLE)) │ (CAST(3 AS TINYINT) BETWEEN 1 AND 5) │ (CAST(3 AS SMALLINT) IN (1, 3)) │
│                 boolean                  │          boolean           │                  boolean                   │                  boolean                   │               boolean                │             boolean             │
├──────────────────────────────────────────┼────────────────────────────┼────────────────────────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────┼─────────────────────────────────┤
│ true                                     │ true                       │ true                                       │ true                                       │ true                                 │ true                            │
└──────────────────────────────────────────┴────────────────────────────┴────────────────────────────────────────────┴────────────────────────────────────────────┴──────────────────────────────────────┴─────────────────────────────────┘
```

### several values take the wider type

```x
(sql "SELECT typeof(coalesce(1::TINYINT, 1::SMALLINT)), typeof(greatest(1::TINYINT, 300)), typeof(CASE WHEN true THEN 1::TINYINT ELSE 1::BIGINT END), typeof(nullif(1::SMALLINT, 2::TINYINT))")
```
---
```output
┌───────────────────────────────────────────────────────────┬───────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────┐
│ typeof(COALESCE(CAST(1 AS TINYINT), CAST(1 AS SMALLINT))) │ typeof(greatest(CAST(1 AS TINYINT), 300)) │ typeof(CASE  WHEN (true) THEN (CAST(1 AS TINYINT)) ELSE CAST(1 AS BIGINT) END) │ typeof("nullif"(CAST(1 AS SMALLINT), CAST(2 AS TINYINT))) │
│                          varchar                          │                  varchar                  │                                    varchar                                     │                          varchar                          │
├───────────────────────────────────────────────────────────┼───────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
│ SMALLINT                                                  │ INTEGER                                   │ BIGINT                                                                         │ SMALLINT                                                  │
└───────────────────────────────────────────────────────────┴───────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────┘
```

### columns: a value is cast as it goes in

```x
(sql "CREATE OR REPLACE TABLE s (a TINYINT, b SMALLINT); INSERT INTO s VALUES (1, 300), (NULL, -5), (-7, 2); SELECT *, a + b, typeof(a + b), typeof(a) FROM s ORDER BY b")
```
---
```output
┌──────┬───────┬─────────┬─────────────────┬───────────┐
│  a   │   b   │ (a + b) │ typeof((a + b)) │ typeof(a) │
│ int8 │ int16 │  int16  │     varchar     │  varchar  │
├──────┼───────┼─────────┼─────────────────┼───────────┤
│ NULL │    -5 │    NULL │ SMALLINT        │ TINYINT   │
│   -7 │     2 │      -5 │ SMALLINT        │ TINYINT   │
│    1 │   300 │     301 │ SMALLINT        │ TINYINT   │
└──────┴───────┴─────────┴─────────────────┴───────────┘
```

### aggregates and functions

```x
(sql "CREATE OR REPLACE TABLE s (a TINYINT, b SMALLINT); INSERT INTO s VALUES (1, 300), (NULL, -5), (-7, 2); SELECT sum(a), typeof(sum(a)), avg(b), min(a), typeof(min(a)), max(b), count(a) FROM s; SELECT abs(a), typeof(abs(a)), typeof(round(b)), typeof(floor(a)), floor(b), ceil(a) FROM s ORDER BY b; SELECT floor(7), ceil(-7), typeof(ceil(7::BIGINT)), floor(7.5), typeof(floor(7.5))")
```
---
```output
┌────────┬────────────────┬────────┬────────┬────────────────┬────────┬──────────┐
│ sum(a) │ typeof(sum(a)) │ avg(b) │ min(a) │ typeof(min(a)) │ max(b) │ count(a) │
│ int128 │    varchar     │ double │  int8  │    varchar     │ int16  │  int64   │
├────────┼────────────────┼────────┼────────┼────────────────┼────────┼──────────┤
│     -6 │ HUGEINT        │   99.0 │     -7 │ TINYINT        │    300 │        2 │
└────────┴────────────────┴────────┴────────┴────────────────┴────────┴──────────┘
┌────────┬────────────────┬──────────────────┬──────────────────┬──────────┬─────────┐
│ abs(a) │ typeof(abs(a)) │ typeof(round(b)) │ typeof(floor(a)) │ floor(b) │ ceil(a) │
│  int8  │    varchar     │     varchar      │     varchar      │  double  │ double  │
├────────┼────────────────┼──────────────────┼──────────────────┼──────────┼─────────┤
│   NULL │ TINYINT        │ SMALLINT         │ DOUBLE           │     -5.0 │    NULL │
│      7 │ TINYINT        │ SMALLINT         │ DOUBLE           │      2.0 │    -7.0 │
│      1 │ TINYINT        │ SMALLINT         │ DOUBLE           │    300.0 │     1.0 │
└────────┴────────────────┴──────────────────┴──────────────────┴──────────┴─────────┘
┌──────────┬──────────┬─────────────────────────────────┬──────────────┬────────────────────┐
│ floor(7) │ ceil(-7) │ typeof(ceil(CAST(7 AS BIGINT))) │  floor(7.5)  │ typeof(floor(7.5)) │
│  double  │  double  │             varchar             │ decimal(2,0) │      varchar       │
├──────────┼──────────┼─────────────────────────────────┼──────────────┼────────────────────┤
│      7.0 │     -7.0 │ DOUBLE                          │            7 │ DECIMAL(2,0)       │
└──────────┴──────────┴─────────────────────────────────┴──────────────┴────────────────────┘
```

### grouped, sorted and windowed like any integer

```x
(sql "CREATE OR REPLACE TABLE s (a TINYINT, b SMALLINT); INSERT INTO s VALUES (1, 300), (NULL, -5), (-7, 2); SELECT a, count(*) FROM s GROUP BY a ORDER BY a NULLS FIRST; SELECT b, sum(b) OVER (ORDER BY b), typeof(lag(a) OVER (ORDER BY b)) FROM s ORDER BY b")
```
---
```output
┌──────┬──────────────┐
│  a   │ count_star() │
│ int8 │    int64     │
├──────┼──────────────┤
│ NULL │            1 │
│   -7 │            1 │
│    1 │            1 │
└──────┴──────────────┘
┌───────┬──────────────────────────┬──────────────────────────────────┐
│   b   │ sum(b) OVER (ORDER BY b) │ typeof(lag(a) OVER (ORDER BY b)) │
│ int16 │          int128          │             varchar              │
├───────┼──────────────────────────┼──────────────────────────────────┤
│    -5 │                       -5 │ TINYINT                          │
│     2 │                       -3 │ TINYINT                          │
│   300 │                      297 │ TINYINT                          │
└───────┴──────────────────────────┴──────────────────────────────────┘
```

## small integer errors

### a value past a TINYINT

```x
(sql "SELECT 128::TINYINT")
```
---
```output
Conversion Error: Type INT32 with value 128 can't be cast because the value is out of range for the destination type INT8
```

### and past a SMALLINT

```x
(sql "SELECT 32768::SMALLINT")
```
---
```output
Conversion Error: Type INT32 with value 32768 can't be cast because the value is out of range for the destination type INT16
```

### text that spells one

```x
(sql "SELECT '300'::TINYINT")
```
---
```output
Conversion Error: Could not convert string '300' to INT8
```

### a float

```x
(sql "SELECT 300::REAL::TINYINT")
```
---
```output
Conversion Error: Type FLOAT with value 300.0 can't be cast because the value is out of range for the destination type INT8
```

### a row for a column

```x
(sql "CREATE OR REPLACE TABLE s (a TINYINT, b SMALLINT); INSERT INTO s VALUES (1, 300), (NULL, -5), (-7, 2); INSERT INTO s VALUES (200, 1)")
```
---
```output
Conversion Error: Type INT32 with value 200 can't be cast because the value is out of range for the destination type INT8
```

### a sum past the type

```x
(sql "SELECT 100::TINYINT + 100::TINYINT")
```
---
```output
Out of Range Error: Overflow in addition of INT8 (100 + 100)!
```

### a product

```x
(sql "SELECT 100::TINYINT * 2::TINYINT")
```
---
```output
Out of Range Error: Overflow in multiplication of INT8 (100 * 2)!
```

### a difference

```x
(sql "SELECT (-128)::TINYINT - 1::TINYINT")
```
---
```output
Out of Range Error: Overflow in subtraction of INT8 (-128 - 1)!
```

### a SMALLINT sum

```x
(sql "SELECT 32767::SMALLINT + 1::SMALLINT")
```
---
```output
Out of Range Error: Overflow in addition of INT16 (32767 + 1)!
```

## real

### REAL, FLOAT and FLOAT4 are one type of 32 bits, shown in the fewest digits that read back as it

```x
(sql "SELECT 1.1::REAL a, 1::REAL b, 0.1::FLOAT c, 123456.789::FLOAT4 d, 1234567.5::REAL e, 123456789.0::REAL f, 16777217::REAL g, typeof(1::REAL), typeof(1::FLOAT4)")
```
---
```output
┌───────┬───────┬───────┬───────────┬───────────┬─────────────┬────────────┬──────────────────────────┬───────────────────────────┐
│   a   │   b   │   c   │     d     │     e     │      f      │     g      │ typeof(CAST(1 AS FLOAT)) │ typeof(CAST(1 AS FLOAT4)) │
│ float │ float │ float │   float   │   float   │    float    │   float    │         varchar          │          varchar          │
├───────┼───────┼───────┼───────────┼───────────┼─────────────┼────────────┼──────────────────────────┼───────────────────────────┤
│   1.1 │   1.0 │   0.1 │ 123456.79 │ 1234567.5 │ 123456790.0 │ 16777216.0 │ FLOAT                    │ FLOAT                     │
└───────┴───────┴───────┴───────────┴───────────┴─────────────┴────────────┴──────────────────────────┴───────────────────────────┘
```

### large and small ones as a DOUBLE is

```x
(sql "SELECT 1e10::REAL a, 100000000::REAL b, 1e16::REAL c, 1.5e20::REAL d, 3.4e38::REAL e, 0.0001::REAL f, 1e-5::REAL g, 0.000012345::REAL h, (-2.5e-10)::REAL i")
```
---
```output
┌───────────────┬─────────────┬───────┬─────────┬─────────┬────────┬───────┬────────────┬──────────┐
│       a       │      b      │   c   │    d    │    e    │   f    │   g   │     h      │    i     │
│     float     │    float    │ float │  float  │  float  │ float  │ float │   float    │  float   │
├───────────────┼─────────────┼───────┼─────────┼─────────┼────────┼───────┼────────────┼──────────┤
│ 10000000000.0 │ 100000000.0 │ 1e+16 │ 1.5e+20 │ 3.4e+38 │ 0.0001 │ 1e-05 │ 1.2345e-05 │ -2.5e-10 │
└───────────────┴─────────────┴───────┴─────────┴─────────┴────────┴───────┴────────────┴──────────┘
```

### arithmetic with a REAL is a REAL unless a DOUBLE is in it

```x
(sql "SELECT typeof(1::REAL + 1), typeof(1::REAL + 1::BIGINT), typeof(1::REAL + 1.5), typeof(1::REAL + 1::DOUBLE), typeof(1::REAL * 1::REAL), typeof(1::REAL / 2::REAL), typeof(1::REAL / 2), typeof(-(1::REAL)), typeof(1::SMALLINT + 1::REAL)")
```
---
```output
┌────────────────────────────────┬────────────────────────────────────────────────┬──────────────────────────────────┬────────────────────────────────────────────────┬───────────────────────────────────────────────┬───────────────────────────────────────────────┬────────────────────────────────┬───────────────────────────────┬──────────────────────────────────────────────────┐
│ typeof((CAST(1 AS FLOAT) + 1)) │ typeof((CAST(1 AS FLOAT) + CAST(1 AS BIGINT))) │ typeof((CAST(1 AS FLOAT) + 1.5)) │ typeof((CAST(1 AS FLOAT) + CAST(1 AS DOUBLE))) │ typeof((CAST(1 AS FLOAT) * CAST(1 AS FLOAT))) │ typeof((CAST(1 AS FLOAT) / CAST(2 AS FLOAT))) │ typeof((CAST(1 AS FLOAT) / 2)) │ typeof((-(CAST(1 AS FLOAT)))) │ typeof((CAST(1 AS SMALLINT) + CAST(1 AS FLOAT))) │
│            varchar             │                    varchar                     │             varchar              │                    varchar                     │                    varchar                    │                    varchar                    │            varchar             │            varchar            │                     varchar                      │
├────────────────────────────────┼────────────────────────────────────────────────┼──────────────────────────────────┼────────────────────────────────────────────────┼───────────────────────────────────────────────┼───────────────────────────────────────────────┼────────────────────────────────┼───────────────────────────────┼──────────────────────────────────────────────────┤
│ FLOAT                          │ FLOAT                                          │ FLOAT                            │ DOUBLE                                         │ FLOAT                                         │ FLOAT                                         │ FLOAT                          │ FLOAT                         │ FLOAT                                            │
└────────────────────────────────┴────────────────────────────────────────────────┴──────────────────────────────────┴────────────────────────────────────────────────┴───────────────────────────────────────────────┴───────────────────────────────────────────────┴────────────────────────────────┴───────────────────────────────┴──────────────────────────────────────────────────┘
```

### and is rounded to 32 bits

```x
(sql "SELECT 0.1::REAL + 0.2::REAL, 1::REAL / 3::REAL, 2::REAL / 3, 1.1::REAL + 1, 1.1::REAL + 1.5, 1.1::REAL * 3, 1.1::REAL + 1::DOUBLE, -(1.1::REAL)")
```
---
```output
┌───────────────────────────────────────────┬───────────────────────────────────────┬────────────────────────┬──────────────────────────┬────────────────────────────┬──────────────────────────┬──────────────────────────────────────────┬─────────────────────────┐
│ (CAST(0.1 AS FLOAT) + CAST(0.2 AS FLOAT)) │ (CAST(1 AS FLOAT) / CAST(3 AS FLOAT)) │ (CAST(2 AS FLOAT) / 3) │ (CAST(1.1 AS FLOAT) + 1) │ (CAST(1.1 AS FLOAT) + 1.5) │ (CAST(1.1 AS FLOAT) * 3) │ (CAST(1.1 AS FLOAT) + CAST(1 AS DOUBLE)) │ (-(CAST(1.1 AS FLOAT))) │
│                   float                   │                 float                 │         float          │          float           │           float            │          float           │                  double                  │          float          │
├───────────────────────────────────────────┼───────────────────────────────────────┼────────────────────────┼──────────────────────────┼────────────────────────────┼──────────────────────────┼──────────────────────────────────────────┼─────────────────────────┤
│                                       0.3 │                            0.33333334 │              0.6666667 │                      2.1 │                        2.6 │                3.3000002 │                        2.100000023841858 │                    -1.1 │
└───────────────────────────────────────────┴───────────────────────────────────────┴────────────────────────┴──────────────────────────┴────────────────────────────┴──────────────────────────┴──────────────────────────────────────────┴─────────────────────────┘
```

### beside a DOUBLE a REAL is the DOUBLE it is equal to; beside anything else the other is made a REAL

```x
(sql "SELECT 1.1::REAL = 1.1, 1.1::REAL = 1.1::DOUBLE, 1.1::REAL < 1.1::DOUBLE, 1.1::REAL::DOUBLE, 1::REAL = 1, 0.5::REAL = 0.5::DOUBLE, 1.1::REAL > 1")
```
---
```output
┌────────────────────────────┬────────────────────────────────────────────┬────────────────────────────────────────────┬────────────────────────────────────┬────────────────────────┬────────────────────────────────────────────┬──────────────────────────┐
│ (CAST(1.1 AS FLOAT) = 1.1) │ (CAST(1.1 AS FLOAT) = CAST(1.1 AS DOUBLE)) │ (CAST(1.1 AS FLOAT) < CAST(1.1 AS DOUBLE)) │ CAST(CAST(1.1 AS FLOAT) AS DOUBLE) │ (CAST(1 AS FLOAT) = 1) │ (CAST(0.5 AS FLOAT) = CAST(0.5 AS DOUBLE)) │ (CAST(1.1 AS FLOAT) > 1) │
│          boolean           │                  boolean                   │                  boolean                   │               double               │        boolean         │                  boolean                   │         boolean          │
├────────────────────────────┼────────────────────────────────────────────┼────────────────────────────────────────────┼────────────────────────────────────┼────────────────────────┼────────────────────────────────────────────┼──────────────────────────┤
│ true                       │ false                                      │ false                                      │                  1.100000023841858 │ true                   │ true                                       │ true                     │
└────────────────────────────┴────────────────────────────────────────────┴────────────────────────────────────────────┴────────────────────────────────────┴────────────────────────┴────────────────────────────────────────────┴──────────────────────────┘
```

### into other types: a half to the even integer, and away from zero in a decimal

```x
(sql "SELECT 1.5::REAL::INTEGER, 2.5::REAL::INTEGER, 1.25::REAL::DECIMAL(5,1), 1.1::REAL::VARCHAR, 1.1::REAL::DECIMAL(10,5), 16777216::REAL::BIGINT, 3::REAL::TINYINT")
```
---
```output
┌─────────────────────────────────────┬─────────────────────────────────────┬────────────────────────────────────────────┬─────────────────────────────────────┬────────────────────────────────────────────┬─────────────────────────────────────────┬───────────────────────────────────┐
│ CAST(CAST(1.5 AS FLOAT) AS INTEGER) │ CAST(CAST(2.5 AS FLOAT) AS INTEGER) │ CAST(CAST(1.25 AS FLOAT) AS DECIMAL(5, 1)) │ CAST(CAST(1.1 AS FLOAT) AS VARCHAR) │ CAST(CAST(1.1 AS FLOAT) AS DECIMAL(10, 5)) │ CAST(CAST(16777216 AS FLOAT) AS BIGINT) │ CAST(CAST(3 AS FLOAT) AS TINYINT) │
│                int32                │                int32                │                decimal(5,1)                │               varchar               │               decimal(10,5)                │                  int64                  │               int8                │
├─────────────────────────────────────┼─────────────────────────────────────┼────────────────────────────────────────────┼─────────────────────────────────────┼────────────────────────────────────────────┼─────────────────────────────────────────┼───────────────────────────────────┤
│                                   2 │                                   2 │                                        1.3 │ 1.1                                 │                                    1.10000 │                                16777216 │                                 3 │
└─────────────────────────────────────┴─────────────────────────────────────┴────────────────────────────────────────────┴─────────────────────────────────────┴────────────────────────────────────────────┴─────────────────────────────────────────┴───────────────────────────────────┘
```

### from other types

```x
(sql "SELECT true::REAL, '1.5'::REAL, ' 2.5e3 '::REAL, 1.25::DECIMAL(5,2)::REAL, 9007199254740993::REAL, 0.1::DOUBLE::REAL, 'inf'::REAL, '-inf'::FLOAT, 'nan'::REAL")
```
---
```output
┌─────────────────────┬──────────────────────┬──────────────────────────┬────────────────────────────────────────────┬─────────────────────────────────┬────────────────────────────────────┬──────────────────────┬───────────────────────┬──────────────────────┐
│ CAST(true AS FLOAT) │ CAST('1.5' AS FLOAT) │ CAST(' 2.5e3 ' AS FLOAT) │ CAST(CAST(1.25 AS DECIMAL(5, 2)) AS FLOAT) │ CAST(9007199254740993 AS FLOAT) │ CAST(CAST(0.1 AS DOUBLE) AS FLOAT) │ CAST('inf' AS FLOAT) │ CAST('-inf' AS FLOAT) │ CAST('nan' AS FLOAT) │
│        float        │        float         │          float           │                   float                    │              float              │               float                │        float         │         float         │        float         │
├─────────────────────┼──────────────────────┼──────────────────────────┼────────────────────────────────────────────┼─────────────────────────────────┼────────────────────────────────────┼──────────────────────┼───────────────────────┼──────────────────────┤
│                 1.0 │                  1.5 │                   2500.0 │                                       1.25 │              9007199000000000.0 │                                0.1 │                  inf │                  -inf │                  nan │
└─────────────────────┴──────────────────────┴──────────────────────────┴────────────────────────────────────────────┴─────────────────────────────────┴────────────────────────────────────┴──────────────────────┴───────────────────────┴──────────────────────┘
```

### several values take REAL over the exact types and DOUBLE over REAL

```x
(sql "SELECT typeof(greatest(1::REAL, 1)), typeof(coalesce(1::REAL, 1.5)), typeof(CASE WHEN true THEN 1::REAL ELSE 1 END), typeof(CASE WHEN true THEN 1::REAL ELSE 1::DOUBLE END), typeof(nullif(1::REAL, 1))")
```
---
```output
┌───────────────────────────────────────┬─────────────────────────────────────────┬──────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────┐
│ typeof(greatest(CAST(1 AS FLOAT), 1)) │ typeof(COALESCE(CAST(1 AS FLOAT), 1.5)) │ typeof(CASE  WHEN (true) THEN (CAST(1 AS FLOAT)) ELSE 1 END) │ typeof(CASE  WHEN (true) THEN (CAST(1 AS FLOAT)) ELSE CAST(1 AS DOUBLE) END) │ typeof("nullif"(CAST(1 AS FLOAT), 1)) │
│                varchar                │                 varchar                 │                           varchar                            │                                   varchar                                    │                varchar                │
├───────────────────────────────────────┼─────────────────────────────────────────┼──────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────┤
│ FLOAT                                 │ FLOAT                                   │ FLOAT                                                        │ DOUBLE                                                                       │ FLOAT                                 │
└───────────────────────────────────────┴─────────────────────────────────────────┴──────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────┘
```

### columns

```x
(sql "CREATE OR REPLACE TABLE r (id INTEGER, x REAL, y FLOAT, z FLOAT4); INSERT INTO r VALUES (1, 1.1, 2.2, 3.3), (2, 0.1, NULL, 7), (3, 1.1, -2.5, 16777217); SELECT * FROM r ORDER BY id; SELECT typeof(x), typeof(y), typeof(z), x + y, x * 3, y / 2 FROM r ORDER BY id")
```
---
```output
┌───────┬───────┬───────┬────────────┐
│  id   │   x   │   y   │     z      │
│ int32 │ float │ float │   float    │
├───────┼───────┼───────┼────────────┤
│     1 │   1.1 │   2.2 │        3.3 │
│     2 │   0.1 │  NULL │        7.0 │
│     3 │   1.1 │  -2.5 │ 16777216.0 │
└───────┴───────┴───────┴────────────┘
┌───────────┬───────────┬───────────┬───────────┬───────────┬─────────┐
│ typeof(x) │ typeof(y) │ typeof(z) │  (x + y)  │  (x * 3)  │ (y / 2) │
│  varchar  │  varchar  │  varchar  │   float   │   float   │  float  │
├───────────┼───────────┼───────────┼───────────┼───────────┼─────────┤
│ FLOAT     │ FLOAT     │ FLOAT     │ 3.3000002 │ 3.3000002 │     1.1 │
│ FLOAT     │ FLOAT     │ FLOAT     │      NULL │       0.3 │    NULL │
│ FLOAT     │ FLOAT     │ FLOAT     │      -1.4 │ 3.3000002 │   -1.25 │
└───────────┴───────────┴───────────┴───────────┴───────────┴─────────┘
```

### sum and avg of a REAL are DOUBLEs, min and max REALs

```x
(sql "CREATE OR REPLACE TABLE r (id INTEGER, x REAL, y FLOAT, z FLOAT4); INSERT INTO r VALUES (1, 1.1, 2.2, 3.3), (2, 0.1, NULL, 7), (3, 1.1, -2.5, 16777217); SELECT sum(x), avg(x), min(x), max(x), typeof(sum(x)), typeof(avg(x)), typeof(min(x)), count(y) FROM r")
```
---
```output
┌───────────────────┬────────────────────┬────────┬────────┬────────────────┬────────────────┬────────────────┬──────────┐
│      sum(x)       │       avg(x)       │ min(x) │ max(x) │ typeof(sum(x)) │ typeof(avg(x)) │ typeof(min(x)) │ count(y) │
│      double       │       double       │ float  │ float  │    varchar     │    varchar     │    varchar     │  int64   │
├───────────────────┼────────────────────┼────────┼────────┼────────────────┼────────────────┼────────────────┼──────────┤
│ 2.300000049173832 │ 0.7666666830579439 │    0.1 │    1.1 │ DOUBLE         │ DOUBLE         │ FLOAT          │        2 │
└───────────────────┴────────────────────┴────────┴────────┴────────────────┴────────────────┴────────────────┴──────────┘
```

### abs, round, floor and ceil answer a REAL, sqrt and power a DOUBLE

```x
(sql "CREATE OR REPLACE TABLE r (id INTEGER, x REAL, y FLOAT, z FLOAT4); INSERT INTO r VALUES (1, 1.1, 2.2, 3.3), (2, 0.1, NULL, 7), (3, 1.1, -2.5, 16777217); SELECT typeof(abs(x)), typeof(round(x)), typeof(floor(x)), typeof(ceil(x)), typeof(sqrt(x)), typeof(power(x, 2)) FROM r LIMIT 1; SELECT abs(-x), round(x), floor(y), ceil(y), sqrt(x), power(x, 2) FROM r ORDER BY id")
```
---
```output
┌────────────────┬──────────────────┬──────────────────┬─────────────────┬─────────────────┬─────────────────────┐
│ typeof(abs(x)) │ typeof(round(x)) │ typeof(floor(x)) │ typeof(ceil(x)) │ typeof(sqrt(x)) │ typeof(power(x, 2)) │
│    varchar     │     varchar      │     varchar      │     varchar     │     varchar     │       varchar       │
├────────────────┼──────────────────┼──────────────────┼─────────────────┼─────────────────┼─────────────────────┤
│ FLOAT          │ FLOAT            │ FLOAT            │ FLOAT           │ DOUBLE          │ DOUBLE              │
└────────────────┴──────────────────┴──────────────────┴─────────────────┴─────────────────┴─────────────────────┘
┌─────────────┬──────────┬──────────┬─────────┬────────────────────┬──────────────────────┐
│ abs((-(x))) │ round(x) │ floor(y) │ ceil(y) │      sqrt(x)       │     power(x, 2)      │
│    float    │  float   │  float   │  float  │       double       │        double        │
├─────────────┼──────────┼──────────┼─────────┼────────────────────┼──────────────────────┤
│         1.1 │      1.0 │      2.0 │     3.0 │ 1.0488088595363112 │    1.210000052452088 │
│         0.1 │      0.0 │     NULL │    NULL │ 0.3162277683729184 │ 0.010000000298023226 │
│         1.1 │      1.0 │     -3.0 │    -2.0 │ 1.0488088595363112 │    1.210000052452088 │
└─────────────┴──────────┴──────────┴─────────┴────────────────────┴──────────────────────┘
```

### grouped, sorted and distinct

```x
(sql "CREATE OR REPLACE TABLE r (id INTEGER, x REAL, y FLOAT, z FLOAT4); INSERT INTO r VALUES (1, 1.1, 2.2, 3.3), (2, 0.1, NULL, 7), (3, 1.1, -2.5, 16777217); SELECT x, count(*) FROM r GROUP BY x ORDER BY x; SELECT DISTINCT x FROM r ORDER BY x DESC; SELECT id FROM r ORDER BY y NULLS FIRST; SELECT id FROM r WHERE x = 1.1")
```
---
```output
┌───────┬──────────────┐
│   x   │ count_star() │
│ float │    int64     │
├───────┼──────────────┤
│   0.1 │            1 │
│   1.1 │            2 │
└───────┴──────────────┘
┌───────┐
│   x   │
│ float │
├───────┤
│   1.1 │
│   0.1 │
└───────┘
┌───────┐
│  id   │
│ int32 │
├───────┤
│     2 │
│     3 │
│     1 │
└───────┘
┌───────┐
│  id   │
│ int32 │
├───────┤
│     1 │
│     3 │
└───────┘
```

## real errors

### a number past a REAL

```x
(sql "SELECT 1e39::REAL")
```
---
```output
Conversion Error: Type DOUBLE with value 1e+39 can't be cast because the value is out of range for the destination type FLOAT
```

### text that is no number

```x
(sql "SELECT 'abc'::REAL")
```
---
```output
Conversion Error: Could not convert string 'abc' to FLOAT
```

### a REAL past an integer

```x
(sql "SELECT 1e10::REAL::INTEGER")
```
---
```output
Conversion Error: Type FLOAT with value 10000000000.0 can't be cast because the value is out of range for the destination type INT32
```

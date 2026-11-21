CAST(x AS type) and x::type.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## casts forms

### CAST and :: are one thing, headed the long way

```x
(sql "SELECT CAST(7 AS DOUBLE), 7::DOUBLE, CAST('12' AS INTEGER) + 1")
```
---
```output
┌───────────────────┬───────────────────┬─────────────────────────────┐
│ CAST(7 AS DOUBLE) │ CAST(7 AS DOUBLE) │ (CAST('12' AS INTEGER) + 1) │
│      double       │      double       │            int32            │
├───────────────────┼───────────────────┼─────────────────────────────┤
│               7.0 │               7.0 │                          13 │
└───────────────────┴───────────────────┴─────────────────────────────┘
```

### :: binds tighter than a sign and than arithmetic

```x
(sql "SELECT -2.5::INT, 1 + 2.5::INT, (1 + 2.5)::INT")
```
---
```output
┌───────────────────────────┬────────────────────────────┬────────────────────────────┐
│ (-(CAST(2.5 AS INTEGER))) │ (1 + CAST(2.5 AS INTEGER)) │ CAST((1 + 2.5) AS INTEGER) │
│           int32           │           int32            │           int32            │
├───────────────────────────┼────────────────────────────┼────────────────────────────┤
│                        -3 │                          4 │                          4 │
└───────────────────────────┴────────────────────────────┴────────────────────────────┘
```

### casts chain

```x
(sql "SELECT 2.5::DOUBLE::INT, 7::VARCHAR::INT + 1")
```
---
```output
┌──────────────────────────────────────┬───────────────────────────────────────────┐
│ CAST(CAST(2.5 AS DOUBLE) AS INTEGER) │ (CAST(CAST(7 AS VARCHAR) AS INTEGER) + 1) │
│                int32                 │                   int32                   │
├──────────────────────────────────────┼───────────────────────────────────────────┤
│                                    2 │                                         8 │
└──────────────────────────────────────┴───────────────────────────────────────────┘
```

### a heading spells the type as written, but for the names the grammar knows

```x
(sql "SELECT 1::INT, 1::INT8, 1::bigint, 1::Double, 'a'::TEXT, 'a'::CHAR, 1::NUMERIC(6,2), 1::DECIMAL(5), 1::VARCHAR(10)")
```
---
```output
┌────────────────────┬─────────────────┬───────────────────┬───────────────────┬───────────────────┬──────────────────────┬──────────────────────────┬───────────────────────┬────────────────────────┐
│ CAST(1 AS INTEGER) │ CAST(1 AS INT8) │ CAST(1 AS BIGINT) │ CAST(1 AS Double) │ CAST('a' AS TEXT) │ CAST('a' AS VARCHAR) │ CAST(1 AS DECIMAL(6, 2)) │ CAST(1 AS DECIMAL(5)) │ CAST(1 AS VARCHAR(10)) │
│       int32        │      int64      │       int64       │      double       │      varchar      │       varchar        │       decimal(6,2)       │     decimal(5,0)      │        varchar         │
├────────────────────┼─────────────────┼───────────────────┼───────────────────┼───────────────────┼──────────────────────┼──────────────────────────┼───────────────────────┼────────────────────────┤
│                  1 │               1 │                 1 │               1.0 │ a                 │ a                    │                     1.00 │                     1 │ 1                      │
└────────────────────┴─────────────────┴───────────────────┴───────────────────┴───────────────────┴──────────────────────┴──────────────────────────┴───────────────────────┴────────────────────────┘
```

### a NULL of a type

```x
(sql "SELECT NULL::INTEGER, NULL::VARCHAR, CAST(NULL AS DOUBLE)")
```
---
```output
┌───────────────────────┬───────────────────────┬──────────────────────┐
│ CAST(NULL AS INTEGER) │ CAST(NULL AS VARCHAR) │ CAST(NULL AS DOUBLE) │
│         int32         │        varchar        │        double        │
├───────────────────────┼───────────────────────┼──────────────────────┤
│                  NULL │ NULL                  │                 NULL │
└───────────────────────┴───────────────────────┴──────────────────────┘
```

## casts numbers

### a double to an integer rounds a half to the even one

```x
(sql "SELECT 2.5e0::INT, 3.5e0::INT, -2.5e0::INT, 1.7e0::BIGINT, 1e3::INT")
```
---
```output
┌────────────────────────┬────────────────────────┬─────────────────────────────┬───────────────────────┬──────────────────────┐
│ CAST(2.5e0 AS INTEGER) │ CAST(3.5e0 AS INTEGER) │ (-(CAST(2.5e0 AS INTEGER))) │ CAST(1.7e0 AS BIGINT) │ CAST(1e3 AS INTEGER) │
│         int32          │         int32          │            int32            │         int64         │        int32         │
├────────────────────────┼────────────────────────┼─────────────────────────────┼───────────────────────┼──────────────────────┤
│                      2 │                      4 │                          -2 │                     2 │                 1000 │
└────────────────────────┴────────────────────────┴─────────────────────────────┴───────────────────────┴──────────────────────┘
```

### a decimal to an integer rounds a half away from zero

```x
(sql "SELECT 2.5::INT, 3.5::INT, (-2.5)::INT, 1.49::BIGINT")
```
---
```output
┌──────────────────────┬──────────────────────┬───────────────────────┬──────────────────────┐
│ CAST(2.5 AS INTEGER) │ CAST(3.5 AS INTEGER) │ CAST(-2.5 AS INTEGER) │ CAST(1.49 AS BIGINT) │
│        int32         │        int32         │         int32         │        int64         │
├──────────────────────┼──────────────────────┼───────────────────────┼──────────────────────┤
│                    3 │                    4 │                    -3 │                    1 │
└──────────────────────┴──────────────────────┴───────────────────────┴──────────────────────┘
```

### to a decimal: digits past the scale are rounded

```x
(sql "SELECT 1::DECIMAL, 1.239::DECIMAL(4,2), 1e0::DECIMAL(5,3), 0.125e0::DECIMAL(4,2), 7::DECIMAL(3,1)")
```
---
```output
┌────────────────────┬──────────────────────────────┬────────────────────────────┬────────────────────────────────┬──────────────────────────┐
│ CAST(1 AS DECIMAL) │ CAST(1.239 AS DECIMAL(4, 2)) │ CAST(1e0 AS DECIMAL(5, 3)) │ CAST(0.125e0 AS DECIMAL(4, 2)) │ CAST(7 AS DECIMAL(3, 1)) │
│   decimal(18,3)    │         decimal(4,2)         │        decimal(5,3)        │          decimal(4,2)          │       decimal(3,1)       │
├────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────────┼──────────────────────────┤
│              1.000 │                         1.24 │                      1.000 │                           0.13 │                      7.0 │
└────────────────────┴──────────────────────────────┴────────────────────────────┴────────────────────────────────┴──────────────────────────┘
```

### to a double

```x
(sql "SELECT 7::DOUBLE, 1.5::DOUBLE, 9007199254740993::DOUBLE, 0.1::DOUBLE")
```
---
```output
┌───────────────────┬─────────────────────┬──────────────────────────────────┬─────────────────────┐
│ CAST(7 AS DOUBLE) │ CAST(1.5 AS DOUBLE) │ CAST(9007199254740993 AS DOUBLE) │ CAST(0.1 AS DOUBLE) │
│      double       │       double        │              double              │       double        │
├───────────────────┼─────────────────────┼──────────────────────────────────┼─────────────────────┤
│               7.0 │                 1.5 │               9007199254740992.0 │                 0.1 │
└───────────────────┴─────────────────────┴──────────────────────────────────┴─────────────────────┘
```

### between integer types

```x
(sql "SELECT 1::BIGINT, 2147483648::HUGEINT, 5::BIGINT::INTEGER")
```
---
```output
┌───────────────────┬─────────────────────────────┬────────────────────────────────────┐
│ CAST(1 AS BIGINT) │ CAST(2147483648 AS HUGEINT) │ CAST(CAST(5 AS BIGINT) AS INTEGER) │
│       int64       │           int128            │               int32                │
├───────────────────┼─────────────────────────────┼────────────────────────────────────┤
│                 1 │                  2147483648 │                                  5 │
└───────────────────┴─────────────────────────────┴────────────────────────────────────┘
```

## casts text

### anything to text is what a result shows

```x
(sql "SELECT 12::VARCHAR, 1.50::VARCHAR, 1e0::VARCHAR, true::VARCHAR, (1 / 3)::VARCHAR")
```
---
```output
┌─────────────────────┬───────────────────────┬──────────────────────┬───────────────────────┬──────────────────────────┐
│ CAST(12 AS VARCHAR) │ CAST(1.50 AS VARCHAR) │ CAST(1e0 AS VARCHAR) │ CAST(true AS VARCHAR) │ CAST((1 / 3) AS VARCHAR) │
│       varchar       │        varchar        │       varchar        │        varchar        │         varchar          │
├─────────────────────┼───────────────────────┼──────────────────────┼───────────────────────┼──────────────────────────┤
│ 12                  │ 1.50                  │ 1.0                  │ true                  │ 0.3333333333333333       │
└─────────────────────┴───────────────────────┴──────────────────────┴───────────────────────┴──────────────────────────┘
```

### text to a number

```x
(sql "SELECT '12'::INT, ' -7 '::BIGINT, '1.5'::DOUBLE, '1e3'::DOUBLE, '2.5'::DECIMAL(3,1), '-0.125'::DECIMAL(4,2)")
```
---
```output
┌───────────────────────┬────────────────────────┬───────────────────────┬───────────────────────┬──────────────────────────────┬─────────────────────────────────┐
│ CAST('12' AS INTEGER) │ CAST(' -7 ' AS BIGINT) │ CAST('1.5' AS DOUBLE) │ CAST('1e3' AS DOUBLE) │ CAST('2.5' AS DECIMAL(3, 1)) │ CAST('-0.125' AS DECIMAL(4, 2)) │
│         int32         │         int64          │        double         │        double         │         decimal(3,1)         │          decimal(4,2)           │
├───────────────────────┼────────────────────────┼───────────────────────┼───────────────────────┼──────────────────────────────┼─────────────────────────────────┤
│                    12 │                     -7 │                   1.5 │                1000.0 │                          2.5 │                           -0.13 │
└───────────────────────┴────────────────────────┴───────────────────────┴───────────────────────┴──────────────────────────────┴─────────────────────────────────┘
```

### booleans

```x
(sql "SELECT true::INT, false::BIGINT, 0::BOOLEAN, 7::BOOLEAN, 'true'::BOOLEAN, 'F'::BOOLEAN")
```
---
```output
┌───────────────────────┬───────────────────────┬────────────────────┬────────────────────┬─────────────────────────┬──────────────────────┐
│ CAST(true AS INTEGER) │ CAST(false AS BIGINT) │ CAST(0 AS BOOLEAN) │ CAST(7 AS BOOLEAN) │ CAST('true' AS BOOLEAN) │ CAST('F' AS BOOLEAN) │
│         int32         │         int64         │      boolean       │      boolean       │         boolean         │       boolean        │
├───────────────────────┼───────────────────────┼────────────────────┼────────────────────┼─────────────────────────┼──────────────────────┤
│                     1 │                     0 │ false              │ true               │ true                    │ false                │
└───────────────────────┴───────────────────────┴────────────────────┴────────────────────┴─────────────────────────┴──────────────────────┘
```

## casts errors

### text that is no number

```x
(sql "SELECT 'x'::INT")
```
---
```output
Conversion Error: Could not convert string 'x' to INT32
```

### nor a double

```x
(sql "SELECT 'x'::DOUBLE")
```
---
```output
Conversion Error: Could not convert string 'x' to DOUBLE
```

### an integer too wide

```x
(sql "SELECT 2147483648::INT")
```
---
```output
Conversion Error: Type INT64 with value 2147483648 can't be cast because the value is out of range for the destination type INT32
```

### a double too wide

```x
(sql "SELECT 3000000000e0::INT")
```
---
```output
Conversion Error: Type DOUBLE with value 3000000000.0 can't be cast because the value is out of range for the destination type INT32
```

### a decimal too wide for a decimal

```x
(sql "SELECT 99.9::DECIMAL(2,1)")
```
---
```output
Conversion Error: Casting value "99.9" to type DECIMAL(2,1) failed: value is out of range!
```

### an infinity is no integer

```x
(sql "SELECT (1 / 0)::INT")
```
---
```output
Conversion Error: Type DOUBLE with value inf can't be cast because the value is out of range for the destination type INT32
```

### a type that is not built

DuckDB has the type, and no cast to it from a number.

```x
(sql "SELECT 1::UUID")
```
---
```output
Not implemented Error: the type UUID
```

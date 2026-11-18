The unsigned integers: UTINYINT, USMALLINT, UINTEGER, UBIGINT and UHUGEINT.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## unsigned types

### five unsigned integers, each to the last value its bits hold

```x
(sql "SELECT 255::UTINYINT a, 65535::USMALLINT b, 4294967295::UINTEGER c, 18446744073709551615::UBIGINT d, 340282366920938463463374607431768211455::UHUGEINT e, 0::UTINYINT f")
```
---
```output
┌───────┬────────┬────────────┬──────────────────────┬─────────────────────────────────────────┬───────┐
│   a   │   b    │     c      │          d           │                    e                    │   f   │
│ uint8 │ uint16 │   uint32   │        uint64        │                 uint128                 │ uint8 │
├───────┼────────┼────────────┼──────────────────────┼─────────────────────────────────────────┼───────┤
│   255 │  65535 │ 4294967295 │ 18446744073709551615 │ 340282366920938463463374607431768211455 │     0 │
└───────┴────────┴────────────┴──────────────────────┴─────────────────────────────────────────┴───────┘
```

### and their other names

```x
(sql "SELECT typeof(1::UINT8), typeof(1::UINT16), typeof(1::UINT32), typeof(1::UINT64), typeof(1::UINT128), 1::UINT8")
```
---
```output
┌──────────────────────────┬───────────────────────────┬───────────────────────────┬───────────────────────────┬────────────────────────────┬──────────────────┐
│ typeof(CAST(1 AS UINT8)) │ typeof(CAST(1 AS UINT16)) │ typeof(CAST(1 AS UINT32)) │ typeof(CAST(1 AS UINT64)) │ typeof(CAST(1 AS UINT128)) │ CAST(1 AS UINT8) │
│         varchar          │          varchar          │          varchar          │          varchar          │          varchar           │      uint8       │
├──────────────────────────┼───────────────────────────┼───────────────────────────┼───────────────────────────┼────────────────────────────┼──────────────────┤
│ UTINYINT                 │ USMALLINT                 │ UINTEGER                  │ UBIGINT                   │ UHUGEINT                   │                1 │
└──────────────────────────┴───────────────────────────┴───────────────────────────┴───────────────────────────┴────────────────────────────┴──────────────────┘
```

### an integer constant past a HUGEINT is a UHUGEINT

```x
(sql "SELECT typeof(18446744073709551615), typeof(170141183460469231731687303715884105728), 340282366920938463463374607431768211455")
```
---
```output
┌──────────────────────────────┬─────────────────────────────────────────────────┬─────────────────────────────────────────┐
│ typeof(18446744073709551615) │ typeof(170141183460469231731687303715884105728) │ 340282366920938463463374607431768211455 │
│           varchar            │                     varchar                     │                 uint128                 │
├──────────────────────────────┼─────────────────────────────────────────────────┼─────────────────────────────────────────┤
│ HUGEINT                      │ UHUGEINT                                        │ 340282366920938463463374607431768211455 │
└──────────────────────────────┴─────────────────────────────────────────────────┴─────────────────────────────────────────┘
```

## unsigned arithmetic

### two unsigned are the wider

```x
(sql "SELECT typeof(1::UTINYINT + 1::UTINYINT), typeof(1::UTINYINT + 1::USMALLINT), typeof(1::UBIGINT * 1::UINTEGER), typeof(1::UHUGEINT - 1::UBIGINT), typeof(7::UTINYINT // 2::UTINYINT), typeof(7::UTINYINT % 2::USMALLINT)")
```
---
```output
┌─────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┐
│ typeof((CAST(1 AS UTINYINT) + CAST(1 AS UTINYINT))) │ typeof((CAST(1 AS UTINYINT) + CAST(1 AS USMALLINT))) │ typeof((CAST(1 AS UBIGINT) * CAST(1 AS UINTEGER))) │ typeof((CAST(1 AS UHUGEINT) - CAST(1 AS UBIGINT))) │ typeof((CAST(7 AS UTINYINT) // CAST(2 AS UTINYINT))) │ typeof((CAST(7 AS UTINYINT) % CAST(2 AS USMALLINT))) │
│                       varchar                       │                       varchar                        │                      varchar                       │                      varchar                       │                       varchar                        │                       varchar                        │
├─────────────────────────────────────────────────────┼──────────────────────────────────────────────────────┼────────────────────────────────────────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────────────────────┼──────────────────────────────────────────────────────┤
│ UTINYINT                                            │ USMALLINT                                            │ UBIGINT                                            │ UHUGEINT                                           │ UTINYINT                                             │ USMALLINT                                            │
└─────────────────────────────────────────────────────┴──────────────────────────────────────────────────────┴────────────────────────────────────────────────────┴────────────────────────────────────────────────────┴──────────────────────────────────────────────────────┴──────────────────────────────────────────────────────┘
```

### with a signed type that holds every value of the unsigned one, that type

```x
(sql "SELECT typeof(1::UTINYINT + 1::SMALLINT), typeof(1::UTINYINT + 1::HUGEINT), typeof(1::USMALLINT * 1::INTEGER), typeof(1::UINTEGER + 1::BIGINT), typeof(1::UBIGINT + 1::HUGEINT)")
```
---
```output
┌─────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬─────────────────────────────────────────────────────┬───────────────────────────────────────────────────┬───────────────────────────────────────────────────┐
│ typeof((CAST(1 AS UTINYINT) + CAST(1 AS SMALLINT))) │ typeof((CAST(1 AS UTINYINT) + CAST(1 AS HUGEINT))) │ typeof((CAST(1 AS USMALLINT) * CAST(1 AS INTEGER))) │ typeof((CAST(1 AS UINTEGER) + CAST(1 AS BIGINT))) │ typeof((CAST(1 AS UBIGINT) + CAST(1 AS HUGEINT))) │
│                       varchar                       │                      varchar                       │                       varchar                       │                      varchar                      │                      varchar                      │
├─────────────────────────────────────────────────────┼────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┼───────────────────────────────────────────────────┼───────────────────────────────────────────────────┤
│ SMALLINT                                            │ HUGEINT                                            │ INTEGER                                             │ BIGINT                                            │ HUGEINT                                           │
└─────────────────────────────────────────────────────┴────────────────────────────────────────────────────┴─────────────────────────────────────────────────────┴───────────────────────────────────────────────────┴───────────────────────────────────────────────────┘
```

### with one that does not, a BIGINT, or a HUGEINT when a BIGINT does not hold both, or a DOUBLE

```x
(sql "SELECT typeof(1::UTINYINT + 1::TINYINT), typeof(1::USMALLINT + 1::TINYINT), typeof(1::UINTEGER + 1::INTEGER), typeof(1::UINTEGER * 1::TINYINT), typeof(1::UBIGINT + 1::BIGINT), typeof(1::UBIGINT + 1::TINYINT), typeof(1::UHUGEINT + 1::TINYINT), 200::UTINYINT + 100::TINYINT, 1::UHUGEINT + 1::TINYINT")
```
---
```output
┌────────────────────────────────────────────────────┬─────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬────────────────────────────────────────────────────┬──────────────────────────────────────────────────┬───────────────────────────────────────────────────┬────────────────────────────────────────────────────┬────────────────────────────────────────────────┬────────────────────────────────────────────┐
│ typeof((CAST(1 AS UTINYINT) + CAST(1 AS TINYINT))) │ typeof((CAST(1 AS USMALLINT) + CAST(1 AS TINYINT))) │ typeof((CAST(1 AS UINTEGER) + CAST(1 AS INTEGER))) │ typeof((CAST(1 AS UINTEGER) * CAST(1 AS TINYINT))) │ typeof((CAST(1 AS UBIGINT) + CAST(1 AS BIGINT))) │ typeof((CAST(1 AS UBIGINT) + CAST(1 AS TINYINT))) │ typeof((CAST(1 AS UHUGEINT) + CAST(1 AS TINYINT))) │ (CAST(200 AS UTINYINT) + CAST(100 AS TINYINT)) │ (CAST(1 AS UHUGEINT) + CAST(1 AS TINYINT)) │
│                      varchar                       │                       varchar                       │                      varchar                       │                      varchar                       │                     varchar                      │                      varchar                      │                      varchar                       │                     int64                      │                   double                   │
├────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┼────────────────────────────────────────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────────────────┼───────────────────────────────────────────────────┼────────────────────────────────────────────────────┼────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ BIGINT                                             │ BIGINT                                              │ BIGINT                                             │ BIGINT                                             │ HUGEINT                                          │ HUGEINT                                           │ DOUBLE                                             │                                            300 │                                        2.0 │
└────────────────────────────────────────────────────┴─────────────────────────────────────────────────────┴────────────────────────────────────────────────────┴────────────────────────────────────────────────────┴──────────────────────────────────────────────────┴───────────────────────────────────────────────────┴────────────────────────────────────────────────────┴────────────────────────────────────────────────┴────────────────────────────────────────────┘
```

### an integer constant beside one is its type when it fits

```x
(sql "SELECT typeof(1::UTINYINT + 1), typeof(1::UTINYINT + 300), typeof(1::UTINYINT + (-1)), typeof(1::UBIGINT + 1), typeof(2 * 1::UINTEGER), typeof(1::UHUGEINT + 1), 250::UTINYINT + 5, 18446744073709551614::UBIGINT + 1")
```
---
```output
┌───────────────────────────────────┬─────────────────────────────────────┬────────────────────────────────────┬──────────────────────────────────┬───────────────────────────────────┬───────────────────────────────────┬─────────────────────────────┬─────────────────────────────────────────────┐
│ typeof((CAST(1 AS UTINYINT) + 1)) │ typeof((CAST(1 AS UTINYINT) + 300)) │ typeof((CAST(1 AS UTINYINT) + -1)) │ typeof((CAST(1 AS UBIGINT) + 1)) │ typeof((2 * CAST(1 AS UINTEGER))) │ typeof((CAST(1 AS UHUGEINT) + 1)) │ (CAST(250 AS UTINYINT) + 5) │ (CAST(18446744073709551614 AS UBIGINT) + 1) │
│              varchar              │               varchar               │              varchar               │             varchar              │              varchar              │              varchar              │            uint8            │                   uint64                    │
├───────────────────────────────────┼─────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┼─────────────────────────────┼─────────────────────────────────────────────┤
│ UTINYINT                          │ INTEGER                             │ INTEGER                            │ UBIGINT                          │ UINTEGER                          │ UHUGEINT                          │                         255 │                        18446744073709551615 │
└───────────────────────────────────┴─────────────────────────────────────┴────────────────────────────────────┴──────────────────────────────────┴───────────────────────────────────┴───────────────────────────────────┴─────────────────────────────┴─────────────────────────────────────────────┘
```

### with a decimal, a decimal with room for it; with a float, the float; / answers a DOUBLE

```x
(sql "SELECT typeof(1::UTINYINT + 1.5), typeof(1::USMALLINT * 1.5), typeof(1::UINTEGER + 1.5), typeof(1::UBIGINT + 1.5), typeof(1::UHUGEINT + 1.5), typeof(1::UTINYINT + 1::DECIMAL(5,2)), typeof(1::UBIGINT + 1::REAL), typeof(1::UINTEGER + 1::DOUBLE), typeof(1::UTINYINT / 2::UTINYINT), 7::UTINYINT / 2::UTINYINT, 255::UTINYINT * 1.5")
```
---
```output
┌─────────────────────────────────────┬──────────────────────────────────────┬─────────────────────────────────────┬────────────────────────────────────┬─────────────────────────────────────┬──────────────────────────────────────────────────────────┬─────────────────────────────────────────────────┬───────────────────────────────────────────────────┬─────────────────────────────────────────────────────┬─────────────────────────────────────────────┬───────────────────────────────┐
│ typeof((CAST(1 AS UTINYINT) + 1.5)) │ typeof((CAST(1 AS USMALLINT) * 1.5)) │ typeof((CAST(1 AS UINTEGER) + 1.5)) │ typeof((CAST(1 AS UBIGINT) + 1.5)) │ typeof((CAST(1 AS UHUGEINT) + 1.5)) │ typeof((CAST(1 AS UTINYINT) + CAST(1 AS DECIMAL(5, 2)))) │ typeof((CAST(1 AS UBIGINT) + CAST(1 AS FLOAT))) │ typeof((CAST(1 AS UINTEGER) + CAST(1 AS DOUBLE))) │ typeof((CAST(1 AS UTINYINT) / CAST(2 AS UTINYINT))) │ (CAST(7 AS UTINYINT) / CAST(2 AS UTINYINT)) │ (CAST(255 AS UTINYINT) * 1.5) │
│               varchar               │               varchar                │               varchar               │              varchar               │               varchar               │                         varchar                          │                     varchar                     │                      varchar                      │                       varchar                       │                   double                    │         decimal(5,1)          │
├─────────────────────────────────────┼──────────────────────────────────────┼─────────────────────────────────────┼────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────┼───────────────────────────────────────────────────┼─────────────────────────────────────────────────────┼─────────────────────────────────────────────┼───────────────────────────────┤
│ DECIMAL(5,1)                        │ DECIMAL(7,1)                         │ DECIMAL(12,1)                       │ DECIMAL(22,1)                      │ DECIMAL(38,1)                       │ DECIMAL(6,2)                                             │ FLOAT                                           │ DOUBLE                                            │ DOUBLE                                              │                                         3.5 │                         382.5 │
└─────────────────────────────────────┴──────────────────────────────────────┴─────────────────────────────────────┴────────────────────────────────────┴─────────────────────────────────────┴──────────────────────────────────────────────────────────┴─────────────────────────────────────────────────┴───────────────────────────────────────────────────┴─────────────────────────────────────────────────────┴─────────────────────────────────────────────┴───────────────────────────────┘
```

### zero is its own negative

```x
(sql "SELECT -(0::UTINYINT), typeof(-(0::UBIGINT))")
```
---
```output
┌──────────────────────────┬─────────────────────────────────┐
│ (-(CAST(0 AS UTINYINT))) │ typeof((-(CAST(0 AS UBIGINT)))) │
│          uint8           │             varchar             │
├──────────────────────────┼─────────────────────────────────┤
│                        0 │ UBIGINT                         │
└──────────────────────────┴─────────────────────────────────┘
```

## unsigned casts and comparisons

### a fraction is rounded as it goes in

```x
(sql "SELECT 254.5::UTINYINT, 1.5::UINTEGER, 2.5::DOUBLE::UBIGINT, 2.5::REAL::USMALLINT, '12'::USMALLINT, ' 7 '::UHUGEINT, true::UTINYINT")
```
---
```output
┌─────────────────────────┬───────────────────────┬──────────────────────────────────────┬───────────────────────────────────────┬─────────────────────────┬─────────────────────────┬────────────────────────┐
│ CAST(254.5 AS UTINYINT) │ CAST(1.5 AS UINTEGER) │ CAST(CAST(2.5 AS DOUBLE) AS UBIGINT) │ CAST(CAST(2.5 AS FLOAT) AS USMALLINT) │ CAST('12' AS USMALLINT) │ CAST(' 7 ' AS UHUGEINT) │ CAST(true AS UTINYINT) │
│          uint8          │        uint32         │                uint64                │                uint16                 │         uint16          │         uint128         │         uint8          │
├─────────────────────────┼───────────────────────┼──────────────────────────────────────┼───────────────────────────────────────┼─────────────────────────┼─────────────────────────┼────────────────────────┤
│                     255 │                     2 │                                    2 │                                     2 │                      12 │                       7 │                      1 │
└─────────────────────────┴───────────────────────┴──────────────────────────────────────┴───────────────────────────────────────┴─────────────────────────┴─────────────────────────┴────────────────────────┘
```

### into other types

```x
(sql "SELECT 5::UTINYINT::VARCHAR, 5::UBIGINT::DOUBLE, 5::UTINYINT::BIGINT, 200::UTINYINT::SMALLINT, 5::UINTEGER::DECIMAL(6,2), typeof(5::UTINYINT::DECIMAL), 0::UTINYINT::BOOLEAN, 5::UTINYINT || 'x', 18446744073709551615::UBIGINT::HUGEINT, 18446744073709551615::UBIGINT::REAL")
```
---
```output
┌──────────────────────────────────────┬────────────────────────────────────┬─────────────────────────────────────┬─────────────────────────────────────────┬────────────────────────────────────────────┬──────────────────────────────────────────────┬──────────────────────────────────────┬──────────────────────────────┬────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┐
│ CAST(CAST(5 AS UTINYINT) AS VARCHAR) │ CAST(CAST(5 AS UBIGINT) AS DOUBLE) │ CAST(CAST(5 AS UTINYINT) AS BIGINT) │ CAST(CAST(200 AS UTINYINT) AS SMALLINT) │ CAST(CAST(5 AS UINTEGER) AS DECIMAL(6, 2)) │ typeof(CAST(CAST(5 AS UTINYINT) AS DECIMAL)) │ CAST(CAST(0 AS UTINYINT) AS BOOLEAN) │ (CAST(5 AS UTINYINT) || 'x') │ CAST(CAST(18446744073709551615 AS UBIGINT) AS HUGEINT) │ CAST(CAST(18446744073709551615 AS UBIGINT) AS FLOAT) │
│               varchar                │               double               │                int64                │                  int16                  │                decimal(6,2)                │                   varchar                    │               boolean                │           varchar            │                         int128                         │                        float                         │
├──────────────────────────────────────┼────────────────────────────────────┼─────────────────────────────────────┼─────────────────────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────────┼──────────────────────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────┤
│ 5                                    │                                5.0 │                                   5 │                                     200 │                                       5.00 │ DECIMAL(18,3)                                │ false                                │ 5x                           │                                   18446744073709551615 │                                        1.8446744e+19 │
└──────────────────────────────────────┴────────────────────────────────────┴─────────────────────────────────────┴─────────────────────────────────────────┴────────────────────────────────────────────┴──────────────────────────────────────────────┴──────────────────────────────────────┴──────────────────────────────┴────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────┘
```

### compared with every number by value

```x
(sql "SELECT 1::UTINYINT = 1::TINYINT, 255::UTINYINT > (-1)::TINYINT, 18446744073709551615::UBIGINT > (-1)::BIGINT, 1::UINTEGER = 1.0, 1::UBIGINT < 1.5::DOUBLE, 3::UTINYINT BETWEEN 1 AND 5, 3::USMALLINT IN (1, 3)")
```
---
```output
┌────────────────────────────────────────────┬───────────────────────────────────────────────┬──────────────────────────────────────────────────────────────┬─────────────────────────────┬────────────────────────────────────────────┬───────────────────────────────────────┬──────────────────────────────────┐
│ (CAST(1 AS UTINYINT) = CAST(1 AS TINYINT)) │ (CAST(255 AS UTINYINT) > CAST(-1 AS TINYINT)) │ (CAST(18446744073709551615 AS UBIGINT) > CAST(-1 AS BIGINT)) │ (CAST(1 AS UINTEGER) = 1.0) │ (CAST(1 AS UBIGINT) < CAST(1.5 AS DOUBLE)) │ (CAST(3 AS UTINYINT) BETWEEN 1 AND 5) │ (CAST(3 AS USMALLINT) IN (1, 3)) │
│                  boolean                   │                    boolean                    │                           boolean                            │           boolean           │                  boolean                   │                boolean                │             boolean              │
├────────────────────────────────────────────┼───────────────────────────────────────────────┼──────────────────────────────────────────────────────────────┼─────────────────────────────┼────────────────────────────────────────────┼───────────────────────────────────────┼──────────────────────────────────┤
│ true                                       │ true                                          │ true                                                         │ true                        │ true                                       │ true                                  │ true                             │
└────────────────────────────────────────────┴───────────────────────────────────────────────┴──────────────────────────────────────────────────────────────┴─────────────────────────────┴────────────────────────────────────────────┴───────────────────────────────────────┴──────────────────────────────────┘
```

### several values take the type that holds both, the narrowest signed one for a signed with an unsigned

```x
(sql "SELECT typeof(coalesce(1::UTINYINT, 1::TINYINT)), typeof(greatest(1::UINTEGER, 1::INTEGER)), typeof(CASE WHEN true THEN 1::UBIGINT ELSE 1::BIGINT END), typeof(coalesce(1::UTINYINT, 1::USMALLINT)), typeof(coalesce(1::UHUGEINT, 1::BIGINT)), typeof(coalesce(1::UTINYINT, 1.5)), typeof(nullif(1::UINTEGER, 1::UTINYINT))")
```
---
```output
┌───────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────┬────────────────────────────────────────────┬────────────────────────────────────────────────────────────┐
│ typeof(COALESCE(CAST(1 AS UTINYINT), CAST(1 AS TINYINT))) │ typeof(greatest(CAST(1 AS UINTEGER), CAST(1 AS INTEGER))) │ typeof(CASE  WHEN (true) THEN (CAST(1 AS UBIGINT)) ELSE CAST(1 AS BIGINT) END) │ typeof(COALESCE(CAST(1 AS UTINYINT), CAST(1 AS USMALLINT))) │ typeof(COALESCE(CAST(1 AS UHUGEINT), CAST(1 AS BIGINT))) │ typeof(COALESCE(CAST(1 AS UTINYINT), 1.5)) │ typeof("nullif"(CAST(1 AS UINTEGER), CAST(1 AS UTINYINT))) │
│                          varchar                          │                          varchar                          │                                    varchar                                     │                           varchar                           │                         varchar                          │                  varchar                   │                          varchar                           │
├───────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────┼────────────────────────────────────────────┼────────────────────────────────────────────────────────────┤
│ SMALLINT                                                  │ BIGINT                                                    │ HUGEINT                                                                        │ USMALLINT                                                   │ HUGEINT                                                  │ DECIMAL(4,1)                               │ UINTEGER                                                   │
└───────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────┴────────────────────────────────────────────┴────────────────────────────────────────────────────────────┘
```

## unsigned columns

### columns: a value is cast as it goes in

```x
(sql "CREATE OR REPLACE TABLE u (a UTINYINT, b USMALLINT, c UINTEGER, d UBIGINT, e UHUGEINT); INSERT INTO u VALUES (1, 300, 70000, 5000000000, 20000000000000000000), (NULL, 2, NULL, 18446744073709551615, 1), (255, 65535, 4294967295, 0, 340282366920938463463374607431768211455); SELECT * FROM u ORDER BY b")
```
---
```output
┌───────┬────────┬────────────┬──────────────────────┬─────────────────────────────────────────┐
│   a   │   b    │     c      │          d           │                    e                    │
│ uint8 │ uint16 │   uint32   │        uint64        │                 uint128                 │
├───────┼────────┼────────────┼──────────────────────┼─────────────────────────────────────────┤
│  NULL │      2 │       NULL │ 18446744073709551615 │                                       1 │
│     1 │    300 │      70000 │           5000000000 │                    20000000000000000000 │
│   255 │  65535 │ 4294967295 │                    0 │ 340282366920938463463374607431768211455 │
└───────┴────────┴────────────┴──────────────────────┴─────────────────────────────────────────┘
```

### aggregates: a sum is a HUGEINT, and a DOUBLE for a UHUGEINT

```x
(sql "CREATE OR REPLACE TABLE u (a UTINYINT, b USMALLINT, c UINTEGER, d UBIGINT, e UHUGEINT); INSERT INTO u VALUES (1, 300, 70000, 5000000000, 20000000000000000000), (NULL, 2, NULL, 18446744073709551615, 1), (255, 65535, 4294967295, 0, 340282366920938463463374607431768211455); SELECT sum(a), sum(d), sum(e), typeof(sum(a)), typeof(sum(d)), typeof(sum(e)), avg(b), typeof(avg(c)), min(a), max(d), typeof(max(d)), count(c) FROM u")
```
---
```output
┌────────┬──────────────────────┬───────────────────────┬────────────────┬────────────────┬────────────────┬────────────────────┬────────────────┬────────┬──────────────────────┬────────────────┬──────────┐
│ sum(a) │        sum(d)        │        sum(e)         │ typeof(sum(a)) │ typeof(sum(d)) │ typeof(sum(e)) │       avg(b)       │ typeof(avg(c)) │ min(a) │        max(d)        │ typeof(max(d)) │ count(c) │
│ int128 │        int128        │        double         │    varchar     │    varchar     │    varchar     │       double       │    varchar     │ uint8  │        uint64        │    varchar     │  int64   │
├────────┼──────────────────────┼───────────────────────┼────────────────┼────────────────┼────────────────┼────────────────────┼────────────────┼────────┼──────────────────────┼────────────────┼──────────┤
│    256 │ 18446744078709551615 │ 3.402823669209385e+38 │ HUGEINT        │ HUGEINT        │ DOUBLE         │ 21945.666666666668 │ DOUBLE         │      1 │ 18446744073709551615 │ UBIGINT        │        2 │
└────────┴──────────────────────┴───────────────────────┴────────────────┴────────────────┴────────────────┴────────────────────┴────────────────┴────────┴──────────────────────┴────────────────┴──────────┘
```

### functions

```x
(sql "CREATE OR REPLACE TABLE u (a UTINYINT, b USMALLINT, c UINTEGER, d UBIGINT, e UHUGEINT); INSERT INTO u VALUES (1, 300, 70000, 5000000000, 20000000000000000000), (NULL, 2, NULL, 18446744073709551615, 1), (255, 65535, 4294967295, 0, 340282366920938463463374607431768211455); SELECT abs(a), typeof(abs(a)), floor(b), typeof(floor(b)), typeof(sqrt(c)), greatest(a, b), least(c, d) FROM u ORDER BY b")
```
---
```output
┌────────┬────────────────┬──────────┬──────────────────┬─────────────────┬────────────────┬──────────────────────┐
│ abs(a) │ typeof(abs(a)) │ floor(b) │ typeof(floor(b)) │ typeof(sqrt(c)) │ greatest(a, b) │     least(c, d)      │
│ uint8  │    varchar     │  double  │     varchar      │     varchar     │     uint16     │        uint64        │
├────────┼────────────────┼──────────┼──────────────────┼─────────────────┼────────────────┼──────────────────────┤
│   NULL │ UTINYINT       │      2.0 │ DOUBLE           │ DOUBLE          │              2 │ 18446744073709551615 │
│      1 │ UTINYINT       │    300.0 │ DOUBLE           │ DOUBLE          │            300 │                70000 │
│    255 │ UTINYINT       │  65535.0 │ DOUBLE           │ DOUBLE          │          65535 │                    0 │
└────────┴────────────────┴──────────┴──────────────────┴─────────────────┴────────────────┴──────────────────────┘
```

### expressions across the columns

```x
(sql "CREATE OR REPLACE TABLE u (a UTINYINT, b USMALLINT, c UINTEGER, d UBIGINT, e UHUGEINT); INSERT INTO u VALUES (1, 300, 70000, 5000000000, 20000000000000000000), (NULL, 2, NULL, 18446744073709551615, 1), (255, 65535, 4294967295, 0, 340282366920938463463374607431768211455); SELECT a + b, typeof(a + b), b * c, typeof(b * c), d - c, typeof(d - c), a + 1, typeof(a + 1) FROM u WHERE a = 1")
```
---
```output
┌─────────┬─────────────────┬──────────┬─────────────────┬────────────┬─────────────────┬─────────┬─────────────────┐
│ (a + b) │ typeof((a + b)) │ (b * c)  │ typeof((b * c)) │  (d - c)   │ typeof((d - c)) │ (a + 1) │ typeof((a + 1)) │
│ uint16  │     varchar     │  uint32  │     varchar     │   uint64   │     varchar     │  uint8  │     varchar     │
├─────────┼─────────────────┼──────────┼─────────────────┼────────────┼─────────────────┼─────────┼─────────────────┤
│     301 │ USMALLINT       │ 21000000 │ UINTEGER        │ 4999930000 │ UBIGINT         │       2 │ UTINYINT        │
└─────────┴─────────────────┴──────────┴─────────────────┴────────────┴─────────────────┴─────────┴─────────────────┘
```

### grouped, sorted and windowed like any integer

```x
(sql "CREATE OR REPLACE TABLE u (a UTINYINT, b USMALLINT, c UINTEGER, d UBIGINT, e UHUGEINT); INSERT INTO u VALUES (1, 300, 70000, 5000000000, 20000000000000000000), (NULL, 2, NULL, 18446744073709551615, 1), (255, 65535, 4294967295, 0, 340282366920938463463374607431768211455); SELECT a, count(*) FROM u GROUP BY a ORDER BY a NULLS FIRST; SELECT b, sum(b) OVER (ORDER BY b), typeof(lag(d) OVER (ORDER BY b)), row_number() OVER (ORDER BY d DESC) FROM u ORDER BY b")
```
---
```output
┌───────┬──────────────┐
│   a   │ count_star() │
│ uint8 │    int64     │
├───────┼──────────────┤
│  NULL │            1 │
│     1 │            1 │
│   255 │            1 │
└───────┴──────────────┘
┌────────┬──────────────────────────┬──────────────────────────────────┬─────────────────────────────────────┐
│   b    │ sum(b) OVER (ORDER BY b) │ typeof(lag(d) OVER (ORDER BY b)) │ row_number() OVER (ORDER BY d DESC) │
│ uint16 │          int128          │             varchar              │                int64                │
├────────┼──────────────────────────┼──────────────────────────────────┼─────────────────────────────────────┤
│      2 │                        2 │ UBIGINT                          │                                   1 │
│    300 │                      302 │ UBIGINT                          │                                   2 │
│  65535 │                    65837 │ UBIGINT                          │                                   3 │
└────────┴──────────────────────────┴──────────────────────────────────┴─────────────────────────────────────┘
```

## unsigned errors

### a negative value

```x
(sql "SELECT (-1)::UTINYINT")
```
---
```output
Conversion Error: Type INT32 with value -1 can't be cast because the value is out of range for the destination type UINT8
```

### a value past the type

```x
(sql "SELECT 256::UTINYINT")
```
---
```output
Conversion Error: Type INT32 with value 256 can't be cast because the value is out of range for the destination type UINT8
```

### past a UBIGINT

```x
(sql "SELECT 18446744073709551616::UBIGINT")
```
---
```output
Conversion Error: Type INT128 with value 18446744073709551616 can't be cast because the value is out of range for the destination type UINT64
```

### text that spells a negative

```x
(sql "SELECT '-1'::UINTEGER")
```
---
```output
Conversion Error: Could not convert string '-1' to UINT32
```

### an unsigned value past a signed type

```x
(sql "SELECT 200::UTINYINT::TINYINT")
```
---
```output
Conversion Error: Type UINT8 with value 200 can't be cast because the value is out of range for the destination type INT8
```

### and past a BIGINT

```x
(sql "SELECT 18446744073709551615::UBIGINT::BIGINT")
```
---
```output
Conversion Error: Type UINT64 with value 18446744073709551615 can't be cast because the value is out of range for the destination type INT64
```

### a row for a column

```x
(sql "CREATE OR REPLACE TABLE u (a UTINYINT, b USMALLINT, c UINTEGER, d UBIGINT, e UHUGEINT); INSERT INTO u VALUES (1, 300, 70000, 5000000000, 20000000000000000000), (NULL, 2, NULL, 18446744073709551615, 1), (255, 65535, 4294967295, 0, 340282366920938463463374607431768211455); INSERT INTO u VALUES (256, 1, 1, 1, 1)")
```
---
```output
Conversion Error: Type INT32 with value 256 can't be cast because the value is out of range for the destination type UINT8
```

### a difference below zero

```x
(sql "SELECT 1::UTINYINT - 2::UTINYINT")
```
---
```output
Out of Range Error: Overflow in subtraction of UINT8 (1 - 2)!
```

### with a constant too

```x
(sql "SELECT 1::UTINYINT - 2")
```
---
```output
Out of Range Error: Overflow in subtraction of UINT8 (1 - 2)!
```

### a sum past the type

```x
(sql "SELECT 200::UTINYINT + 100::UTINYINT")
```
---
```output
Out of Range Error: Overflow in addition of UINT8 (200 + 100)!
```

### a product

```x
(sql "SELECT 200::UTINYINT * 2::UTINYINT")
```
---
```output
Out of Range Error: Overflow in multiplication of UINT8 (200 * 2)!
```

### past a UINTEGER

```x
(sql "SELECT 4294967295::UINTEGER + 1::UINTEGER")
```
---
```output
Out of Range Error: Overflow in addition of UINT32 (4294967295 + 1)!
```

### past a UBIGINT

```x
(sql "SELECT 18446744073709551615::UBIGINT + 1::UBIGINT")
```
---
```output
Out of Range Error: Overflow in addition of UINT64 (18446744073709551615 + 1)!
```

### past a UHUGEINT

```x
(sql "SELECT 340282366920938463463374607431768211455::UHUGEINT + 1::UHUGEINT")
```
---
```output
Out of Range Error: Overflow in addition of UINT128 (340282366920938463463374607431768211455 + 1)!
```

### the negative of one that is not zero

```x
(sql "SELECT -(1::UTINYINT)")
```
---
```output
Out of Range Error: Overflow in negation of numeric value!
```

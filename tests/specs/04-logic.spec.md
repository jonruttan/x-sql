Comparison, three-valued logic, IS NULL and ||.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## logic comparison

### the six comparisons

```x
(sql "SELECT 1 < 2, 2 <= 2, 3 > 4, 4 >= 5, 1 = 1, 1 != 1")
```
---
```output
┌─────────┬──────────┬─────────┬──────────┬─────────┬──────────┐
│ (1 < 2) │ (2 <= 2) │ (3 > 4) │ (4 >= 5) │ (1 = 1) │ (1 != 1) │
│ boolean │ boolean  │ boolean │ boolean  │ boolean │ boolean  │
├─────────┼──────────┼─────────┼──────────┼─────────┼──────────┤
│ true    │ true     │ false   │ false    │ true    │ false    │
└─────────┴──────────┴─────────┴──────────┴─────────┴──────────┘
```

### integers of unlike types compare by value

```x
(sql "SELECT 2147483648 > 1, 1 = 9223372036854775808")
```
---
```output
┌──────────────────┬───────────────────────────┐
│ (2147483648 > 1) │ (1 = 9223372036854775808) │
│     boolean      │          boolean          │
├──────────────────┼───────────────────────────┤
│ true             │ false                     │
└──────────────────┴───────────────────────────┘
```

### strings compare byte by byte

```x
(sql "SELECT 'a' < 'b', 'B' < 'a', 'a' = 'a', 'ab' > 'a'")
```
---
```output
┌─────────────┬─────────────┬─────────────┬──────────────┐
│ ('a' < 'b') │ ('B' < 'a') │ ('a' = 'a') │ ('ab' > 'a') │
│   boolean   │   boolean   │   boolean   │   boolean    │
├─────────────┼─────────────┼─────────────┼──────────────┤
│ true        │ true        │ true        │ true         │
└─────────────┴─────────────┴─────────────┴──────────────┘
```

### false sorts before true

```x
(sql "SELECT true = true, false < true, true < false")
```
---
```output
┌───────────────┬────────────────┬────────────────┐
│ (true = true) │ (false < true) │ (true < false) │
│    boolean    │    boolean     │    boolean     │
├───────────────┼────────────────┼────────────────┤
│ true          │ true           │ false          │
└───────────────┴────────────────┴────────────────┘
```

### a comparison with NULL is NULL

```x
(sql "SELECT 1 = NULL, NULL = NULL, NULL < 1")
```
---
```output
┌────────────┬───────────────┬────────────┐
│ (1 = NULL) │ (NULL = NULL) │ (NULL < 1) │
│  boolean   │    boolean    │  boolean   │
├────────────┼───────────────┼────────────┤
│ NULL       │ NULL          │ NULL       │
└────────────┴───────────────┴────────────┘
```

### IS NULL and IS NOT NULL answer true or false

```x
(sql "SELECT NULL IS NULL, 1 IS NULL, NULL IS NOT NULL, 1 IS NOT NULL")
```
---
```output
┌────────────────┬─────────────┬────────────────────┬─────────────────┐
│ (NULL IS NULL) │ (1 IS NULL) │ (NULL IS NOT NULL) │ (1 IS NOT NULL) │
│    boolean     │   boolean   │      boolean       │     boolean     │
├────────────────┼─────────────┼────────────────────┼─────────────────┤
│ true           │ false       │ false              │ true            │
└────────────────┴─────────────┴────────────────────┴─────────────────┘
```

## logic connectives

### AND: false wins over NULL

```x
(sql "SELECT true AND true, true AND false, NULL AND false, NULL AND true")
```
---
```output
┌─────────────────┬──────────────────┬──────────────────┬─────────────────┐
│ (true AND true) │ (true AND false) │ (NULL AND false) │ (NULL AND true) │
│     boolean     │     boolean      │     boolean      │     boolean     │
├─────────────────┼──────────────────┼──────────────────┼─────────────────┤
│ true            │ false            │ false            │ NULL            │
└─────────────────┴──────────────────┴──────────────────┴─────────────────┘
```

### OR: true wins over NULL

```x
(sql "SELECT false OR false, true OR false, NULL OR true, NULL OR false")
```
---
```output
┌──────────────────┬─────────────────┬────────────────┬─────────────────┐
│ (false OR false) │ (true OR false) │ (NULL OR true) │ (NULL OR false) │
│     boolean      │     boolean     │    boolean     │     boolean     │
├──────────────────┼─────────────────┼────────────────┼─────────────────┤
│ false            │ true            │ true           │ NULL            │
└──────────────────┴─────────────────┴────────────────┴─────────────────┘
```

### NOT

```x
(sql "SELECT NOT true, NOT false, NOT NULL")
```
---
```output
┌────────────┬─────────────┬────────────┐
│ (NOT true) │ (NOT false) │ (NOT NULL) │
│  boolean   │   boolean   │  boolean   │
├────────────┼─────────────┼────────────┤
│ false      │ true        │ NULL       │
└────────────┴─────────────┴────────────┘
```

### NOT binds looser than a comparison, AND tighter than OR

```x
(sql "SELECT NOT 1 = 2, true OR false AND false, 1 = 1 AND 2 < 3")
```
---
```output
┌───────────────┬─────────────────────────────┬───────────────────────┐
│ (NOT (1 = 2)) │ (true OR (false AND false)) │ ((1 = 1) AND (2 < 3)) │
│    boolean    │           boolean           │        boolean        │
├───────────────┼─────────────────────────────┼───────────────────────┤
│ true          │ true                        │ true                  │
└───────────────┴─────────────────────────────┴───────────────────────┘
```

### an integer is true unless it is zero

```x
(sql "SELECT NOT 1, 1 AND true, 0 OR false")
```
---
```output
┌─────────┬──────────────┬──────────────┐
│ (NOT 1) │ (1 AND true) │ (0 OR false) │
│ boolean │   boolean    │   boolean    │
├─────────┼──────────────┼──────────────┤
│ false   │ true         │ false        │
└─────────┴──────────────┴──────────────┘
```

### a string is no truth value

```x
(sql "SELECT 'a' AND true")
```
---
```output
Conversion Error: Could not convert string 'a' to BOOL
```

## logic concatenation

### || joins strings

```x
(sql "SELECT 'a' || 'b', 'a' || 'b' || 'c'")
```
---
```output
┌──────────────┬───────────────────────┐
│ ('a' || 'b') │ (('a' || 'b') || 'c') │
│   varchar    │        varchar        │
├──────────────┼───────────────────────┤
│ ab           │ abc                   │
└──────────────┴───────────────────────┘
```

### and shows anything else as a result would

```x
(sql "SELECT 'a' || 1 || true")
```
---
```output
┌──────────────────────┐
│ (('a' || 1) || true) │
│       varchar        │
├──────────────────────┤
│ a1true               │
└──────────────────────┘
```

### a NULL operand answers NULL

```x
(sql "SELECT NULL || 'a', 'a' || NULL")
```
---
```output
┌───────────────┬───────────────┐
│ (NULL || 'a') │ ('a' || NULL) │
│    "null"     │    "null"     │
├───────────────┼───────────────┤
│ NULL          │ NULL          │
└───────────────┴───────────────┘
```

### || binds looser than +

```x
(sql "SELECT 'n=' || 1 + 2")
```
---
```output
┌───────────────────┐
│ ('n=' || (1 + 2)) │
│      varchar      │
├───────────────────┤
│ n=3               │
└───────────────────┘
```

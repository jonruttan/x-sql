A SELECT with no FROM: one row of constants, shown in DuckDB's box.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## select constants

### a constant, under its own text and its type

```x
(sql "SELECT 42")
```
---
```output
┌───────┐
│  42   │
│ int32 │
├───────┤
│    42 │
└───────┘
```

### an alias after AS, and a bare one

```x
(sql "SELECT 1 AS a, 2 b")
```
---
```output
┌───────┬───────┐
│   a   │   b   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
```

### a quoted alias keeps its case and its blanks

```x
(sql "SELECT 1 AS \"Long Name\", 2 AS a, 3 AS A")
```
---
```output
┌───────────┬───────┬───────┐
│ Long Name │   a   │   A   │
│   int32   │ int32 │ int32 │
├───────────┼───────┼───────┤
│         1 │     2 │     3 │
└───────────┴───────┴───────┘
```

### a string, a quote in it written twice

```x
(sql "SELECT 'it''s'")
```
---
```output
┌─────────┐
│ 'it''s' │
│ varchar │
├─────────┤
│ it's    │
└─────────┘
```

### true, false and NULL

```x
(sql "SELECT true, false, NULL")
```
---
```output
┌─────────┬─────────┬────────┐
│  true   │  false  │  NULL  │
│ boolean │ boolean │ "null" │
├─────────┼─────────┼────────┤
│ true    │ false   │ NULL   │
└─────────┴─────────┴────────┘
```

### an empty string is not NULL

```x
(sql "SELECT '' AS e")
```
---
```output
┌─────────┐
│    e    │
│ varchar │
├─────────┤
│         │
└─────────┘
```

### keywords in any case

```x
(sql "select 1 As x")
```
---
```output
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

### comments are blanks

```x
(sql "SELECT 1 -- one\n , 2 /* two */ AS b")
```
---
```output
┌───────┬───────┐
│   1   │   b   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
```

### two statements, two tables

```x
(sql "SELECT 1; SELECT 'x' AS b;")
```
---
```output
┌───────┐
│   1   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ x       │
└─────────┘
```

## select types

### an integer constant is the narrowest type that holds it

```x
(sql "SELECT 2147483647, 2147483648, 9223372036854775808")
```
---
```output
┌────────────┬────────────┬─────────────────────┐
│ 2147483647 │ 2147483648 │ 9223372036854775808 │
│   int32    │   int64    │       int128        │
├────────────┼────────────┼─────────────────────┤
│ 2147483647 │ 2147483648 │ 9223372036854775808 │
└────────────┴────────────┴─────────────────────┘
```

### a minus on a constant is the constant, so the least INTEGER is one

```x
(sql "SELECT -2147483648")
```
---
```output
┌─────────────┐
│ -2147483648 │
│    int32    │
├─────────────┤
│ -2147483648 │
└─────────────┘
```

## select headings

### a column is as wide as its widest text, counted in terminal cells

```x
(sql "SELECT 'héllo wörld' AS s, 'x' AS wide_name_here")
```
---
```output
┌─────────────┬────────────────┐
│      s      │ wide_name_here │
│   varchar   │    varchar     │
├─────────────┼────────────────┤
│ héllo wörld │ x              │
└─────────────┴────────────────┘
```

### an expression is spelled out in full, every operator in parentheses

```x
(sql "SELECT 1+2, 2*3+4, (2+3)*4, 1 - -2, -(1+2)")
```
---
```output
┌─────────┬───────────────┬───────────────┬──────────┬──────────────┐
│ (1 + 2) │ ((2 * 3) + 4) │ ((2 + 3) * 4) │ (1 - -2) │ (-((1 + 2))) │
│  int32  │     int32     │     int32     │  int32   │    int32     │
├─────────┼───────────────┼───────────────┼──────────┼──────────────┤
│       3 │            10 │            20 │        3 │           -3 │
└─────────┴───────────────┴───────────────┴──────────┴──────────────┘
```

### = and != are the spellings a heading uses

```x
(sql "SELECT 1 == 1, 1 <> 2")
```
---
```output
┌─────────┬──────────┐
│ (1 = 1) │ (1 != 2) │
│ boolean │ boolean  │
├─────────┼──────────┤
│ true    │ true     │
└─────────┴──────────┘
```

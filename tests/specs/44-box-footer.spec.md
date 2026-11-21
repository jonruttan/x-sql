The line under a result's box (`lib/sql/render.x`): its rows counted when
there are ten or more, and its columns when there are several and the
box has room.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## rows counted

### nine rows have nothing under them

```x
(sql "SELECT unnest(range(9)) AS r, 1 AS b, 2 AS c")
```
---
```output
┌───────┬───────┬───────┐
│   r   │   b   │   c   │
│ int64 │ int32 │ int32 │
├───────┼───────┼───────┤
│     0 │     1 │     2 │
│     1 │     1 │     2 │
│     2 │     1 │     2 │
│     3 │     1 │     2 │
│     4 │     1 │     2 │
│     5 │     1 │     2 │
│     6 │     1 │     2 │
│     7 │     1 │     2 │
│     8 │     1 │     2 │
└───────┴───────┴───────┘
```

### ten have their rows and their columns counted

```x
(sql "SELECT unnest(range(10)) AS r, 1 AS b, 2 AS c")
```
---
```output
┌───────┬───────┬───────┐
│   r   │   b   │   c   │
│ int64 │ int32 │ int32 │
├───────┼───────┼───────┤
│     0 │     1 │     2 │
│     1 │     1 │     2 │
│     2 │     1 │     2 │
│     3 │     1 │     2 │
│     4 │     1 │     2 │
│     5 │     1 │     2 │
│     6 │     1 │     2 │
│     7 │     1 │     2 │
│     8 │     1 │     2 │
│     9 │     1 │     2 │
└───────┴───────┴───────┘
  10 rows     3 columns
```

### the columns as far right as the box goes

```x
(sql "SELECT unnest(range(11)) AS r, 1 AS b, 2 AS c, 'some text' AS d")
```
---
```output
┌───────┬───────┬───────┬───────────┐
│   r   │   b   │   c   │     d     │
│ int64 │ int32 │ int32 │  varchar  │
├───────┼───────┼───────┼───────────┤
│     0 │     1 │     2 │ some text │
│     1 │     1 │     2 │ some text │
│     2 │     1 │     2 │ some text │
│     3 │     1 │     2 │ some text │
│     4 │     1 │     2 │ some text │
│     5 │     1 │     2 │ some text │
│     6 │     1 │     2 │ some text │
│     7 │     1 │     2 │ some text │
│     8 │     1 │     2 │ some text │
│     9 │     1 │     2 │ some text │
│    10 │     1 │     2 │ some text │
└───────┴───────┴───────┴───────────┘
  11 rows                 4 columns
```

### a box with room for both and no more

```x
(sql "SELECT unnest(range(10)) AS r, 1 AS bbbbbbbbbb")
```
---
```output
┌───────┬────────────┐
│   r   │ bbbbbbbbbb │
│ int64 │   int32    │
├───────┼────────────┤
│     0 │          1 │
│     1 │          1 │
│     2 │          1 │
│     3 │          1 │
│     4 │          1 │
│     5 │          1 │
│     6 │          1 │
│     7 │          1 │
│     8 │          1 │
│     9 │          1 │
└───────┴────────────┘
  10 rows  2 columns
```

### a cell narrower has the rows alone, in the middle

```x
(sql "SELECT unnest(range(10)) AS r, 1 AS bbbbbbbbb")
```
---
```output
┌───────┬───────────┐
│   r   │ bbbbbbbbb │
│ int64 │   int32   │
├───────┼───────────┤
│     0 │         1 │
│     1 │         1 │
│     2 │         1 │
│     3 │         1 │
│     4 │         1 │
│     5 │         1 │
│     6 │         1 │
│     7 │         1 │
│     8 │         1 │
│     9 │         1 │
└───────┴───────────┘
       10 rows     
```

### one column has no columns counted

```x
(sql "SELECT unnest(range(10)) AS rrrrrrrrrrr")
```
---
```output
┌─────────────┐
│ rrrrrrrrrrr │
│    int64    │
├─────────────┤
│           0 │
│           1 │
│           2 │
│           3 │
│           4 │
│           5 │
│           6 │
│           7 │
│           8 │
│           9 │
└─────────────┘
    10 rows  
```

### a box with just room for the rows

```x
(sql "SELECT unnest(range(10)) AS rrrrrrr")
```
---
```output
┌─────────┐
│ rrrrrrr │
│  int64  │
├─────────┤
│       0 │
│       1 │
│       2 │
│       3 │
│       4 │
│       5 │
│       6 │
│       7 │
│       8 │
│       9 │
└─────────┘
  10 rows
```

### and one too narrow for them has nothing

```x
(sql "SELECT unnest(range(10)) AS rrrrrr; SELECT unnest(range(12)) AS r")
```
---
```output
┌────────┐
│ rrrrrr │
│ int64  │
├────────┤
│      0 │
│      1 │
│      2 │
│      3 │
│      4 │
│      5 │
│      6 │
│      7 │
│      8 │
│      9 │
└────────┘
┌───────┐
│   r   │
│ int64 │
├───────┤
│     0 │
│     1 │
│     2 │
│     3 │
│     4 │
│     5 │
│     6 │
│     7 │
│     8 │
│     9 │
│    10 │
│    11 │
└───────┘
```

### no rows, as before

```x
(sql "SELECT 1 AS a, 2 AS b WHERE false")
```
---
```output
┌───────┬───────┐
│   a   │   b   │
│ int32 │ int32 │
└───────┴───────┘
     0 rows    
```

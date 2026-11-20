A long result cut (`sql/render.x`), as DuckDB cuts one: `.maxrows N`
says the most rows shown.  With nothing said it is forty on a terminal,
and every row anywhere else, which is where the suite's output goes; so
each case here says its own, and DuckDB was given the same `.maxrows`.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -cmd '.maxrows N' -c`, unless a case says otherwise.

## a result cut

### a result longer than .maxrows is its first and last rows, dots between, and says how many it shows

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(30)) AS r, 'x' AS b, 2 AS c"))
```
---
```output
┌───────┬─────────┬───────┐
│   r   │    b    │   c   │
│ int64 │ varchar │ int32 │
├───────┼─────────┼───────┤
│     0 │ x       │     2 │
│     1 │ x       │     2 │
│     2 │ x       │     2 │
│     3 │ x       │     2 │
│     4 │ x       │     2 │
│     · │ ·       │     · │
│     · │ ·       │     · │
│     · │ ·       │     · │
│    25 │ x       │     2 │
│    26 │ x       │     2 │
│    27 │ x       │     2 │
│    28 │ x       │     2 │
│    29 │ x       │     2 │
└───────┴─────────┴───────┘
  30 rows       3 columns
  (10 shown)              
```

### four rows more than the most are still shown whole: the cut would take as many lines

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(14)) AS r, 'x' AS b"))
```
---
```output
┌───────┬─────────┐
│   r   │    b    │
│ int64 │ varchar │
├───────┼─────────┤
│     0 │ x       │
│     1 │ x       │
│     2 │ x       │
│     3 │ x       │
│     4 │ x       │
│     · │ ·       │
│     · │ ·       │
│     · │ ·       │
│     9 │ x       │
│    10 │ x       │
│    11 │ x       │
│    12 │ x       │
│    13 │ x       │
└───────┴─────────┘
      14 rows    
    (10 shown)    
```

### and five are cut

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(15)) AS r, 'x' AS b"))
```
---
```output
┌───────┬─────────┐
│   r   │    b    │
│ int64 │ varchar │
├───────┼─────────┤
│     0 │ x       │
│     1 │ x       │
│     2 │ x       │
│     3 │ x       │
│     4 │ x       │
│     · │ ·       │
│     · │ ·       │
│     · │ ·       │
│    10 │ x       │
│    11 │ x       │
│    12 │ x       │
│    13 │ x       │
│    14 │ x       │
└───────┴─────────┘
      15 rows    
    (10 shown)    
```

### an odd most shows one more first row than last

```x
(%seq (sql-eval-line ".maxrows 5") (sql "SELECT unnest(range(30)) AS r, 'x' AS b, 2 AS c"))
```
---
```output
┌───────┬─────────┬───────┐
│   r   │    b    │   c   │
│ int64 │ varchar │ int32 │
├───────┼─────────┼───────┤
│     0 │ x       │     2 │
│     1 │ x       │     2 │
│     2 │ x       │     2 │
│     · │ ·       │     · │
│     · │ ·       │     · │
│     · │ ·       │     · │
│    28 │ x       │     2 │
│    29 │ x       │     2 │
└───────┴─────────┴───────┘
  30 rows       3 columns
  (5 shown)               
```

### a dot is under the middle of the cell above it, and to the right in a column of numbers

```x
(%seq (sql-eval-line ".maxrows 4") (sql "SELECT unnest(range(20)) AS r, 'some text' AS t, [1, 2] AS l, NULL AS n, true AS b"))
```
---
```output
┌───────┬───────────┬─────────┬────────┬─────────┐
│   r   │     t     │    l    │   n    │    b    │
│ int64 │  varchar  │ int32[] │ "null" │ boolean │
├───────┼───────────┼─────────┼────────┼─────────┤
│     0 │ some text │ [1, 2]  │ NULL   │ true    │
│     1 │ some text │ [1, 2]  │ NULL   │ true    │
│     · │     ·     │   ·     │  ·     │  ·      │
│     · │     ·     │   ·     │  ·     │  ·      │
│     · │     ·     │   ·     │  ·     │  ·      │
│    18 │ some text │ [1, 2]  │ NULL   │ true    │
│    19 │ some text │ [1, 2]  │ NULL   │ true    │
└───────┴───────────┴─────────┴────────┴─────────┘
  20 rows (4 shown)                    5 columns
```

### a box with room says how many are shown beside the count

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(1000)) AS r, 1 AS bbbbbbbbbbbbbbbbbbbbbbbbbbb"))
```
---
```output
┌───────┬─────────────────────────────┐
│   r   │ bbbbbbbbbbbbbbbbbbbbbbbbbbb │
│ int64 │            int32            │
├───────┼─────────────────────────────┤
│     0 │                           1 │
│     1 │                           1 │
│     2 │                           1 │
│     3 │                           1 │
│     4 │                           1 │
│     · │                           · │
│     · │                           · │
│     · │                           · │
│   995 │                           1 │
│   996 │                           1 │
│   997 │                           1 │
│   998 │                           1 │
│   999 │                           1 │
└───────┴─────────────────────────────┘
  1000 rows (10 shown)      2 columns
```

### with exactly the room

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(1000)) AS r, 1 AS bbbbbbbbbbbbbbbbbbbbb"))
```
---
```output
┌───────┬───────────────────────┐
│   r   │ bbbbbbbbbbbbbbbbbbbbb │
│ int64 │         int32         │
├───────┼───────────────────────┤
│     0 │                     1 │
│     1 │                     1 │
│     2 │                     1 │
│     3 │                     1 │
│     4 │                     1 │
│     · │                     · │
│     · │                     · │
│     · │                     · │
│   995 │                     1 │
│   996 │                     1 │
│   997 │                     1 │
│   998 │                     1 │
│   999 │                     1 │
└───────┴───────────────────────┘
  1000 rows (10 shown)2 columns
```

### one column, wide

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(1000)) AS rrrrrrrrrrrrrrrrrrrrrrrrrrr"))
```
---
```output
┌─────────────────────────────┐
│ rrrrrrrrrrrrrrrrrrrrrrrrrrr │
│            int64            │
├─────────────────────────────┤
│                           0 │
│                           1 │
│                           2 │
│                           3 │
│                           4 │
│                           · │
│                           · │
│                           · │
│                         995 │
│                         996 │
│                         997 │
│                         998 │
│                         999 │
└─────────────────────────────┘
     1000 rows (10 shown)    
```

### one column too narrow to say it is made wide enough

```x
(%seq (sql-eval-line ".maxrows 10") (sql "SELECT unnest(range(100)) AS r"))
```
---
```output
┌────────────┐
│     r      │
│   int64    │
├────────────┤
│          0 │
│          1 │
│          2 │
│          3 │
│          4 │
│          · │
│          · │
│          · │
│         95 │
│         96 │
│         97 │
│         98 │
│         99 │
└────────────┘
   100 rows 
  (10 shown) 
```

### a most of one is one row and no dots

```x
(%seq (sql-eval-line ".maxrows 1") (sql "SELECT unnest(range(30)) AS r"))
```
---
```output
┌───────────┐
│     r     │
│   int64   │
├───────────┤
│         0 │
└───────────┘
   30 rows 
  (1 shown) 
```

### fewer than ten rows are counted too when they are cut

```x
(%seq (sql-eval-line ".maxrows 2") (sql "SELECT unnest(range(8)) AS r, 1 AS b, 2 AS c"))
```
---
```output
┌───────┬───────┬───────┐
│   r   │   b   │   c   │
│ int64 │ int32 │ int32 │
├───────┼───────┼───────┤
│     0 │     1 │     2 │
│     · │     · │     · │
│     · │     · │     · │
│     · │     · │     · │
│     7 │     1 │     2 │
└───────┴───────┴───────┘
```

## not cut

### a result no longer than the most is whole

```x
(%seq (sql-eval-line ".maxrows 40") (sql "SELECT unnest(range(12)) AS r, 1 AS b, 2 AS c"))
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
│    10 │     1 │     2 │
│    11 │     1 │     2 │
└───────┴───────┴───────┘
  12 rows     3 columns
```

### .maxrows wants a number

```x
(sql-eval-line ".maxrows many")
```
---
```output
usage: .maxrows N, the most rows of a result that are shown
```

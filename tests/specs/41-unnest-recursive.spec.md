unnest to more than one level: `recursive := true`, `max_depth := n`
and `keep_parent_names := true` (`lib/sql/exec.x`).

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## lists inside lists

### recursive := true unnests every level of lists

```x
(sql "SELECT unnest([[1, 2], [3]], recursive := true) AS u")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
```

### three levels

```x
(sql "SELECT unnest([[[1, 2], [3]], [[4]]], recursive := true) AS u")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
│     4 │
└───────┘
```

### max_depth says how many

```x
(sql "SELECT unnest([[[1, 2], [3]], [[4]]], max_depth := 2) AS u")
```
---
```output
┌─────────┐
│    u    │
│ int32[] │
├─────────┤
│ [1, 2]  │
│ [3]     │
│ [4]     │
└─────────┘
```

### max_depth of one is unnest as it is without

```x
(sql "SELECT unnest([[1, 2], [3]], max_depth := 1) AS u")
```
---
```output
┌─────────┐
│    u    │
│ int32[] │
├─────────┤
│ [1, 2]  │
│ [3]     │
└─────────┘
```

### more levels asked for than there are

```x
(sql "SELECT unnest([[1, 2], [3]], max_depth := 5) AS u")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
```

### recursive := false is one level

```x
(sql "SELECT unnest([[1, 2], [3]], recursive := false) AS u")
```
---
```output
┌─────────┐
│    u    │
│ int32[] │
├─────────┤
│ [1, 2]  │
│ [3]     │
└─────────┘
```

### max_depth is what counts when both are written

```x
(sql "SELECT unnest([[1, 2], [3]], recursive := true, max_depth := 1) AS u; SELECT unnest([[1, 2], [3]], max_depth := 2, recursive := false) AS v")
```
---
```output
┌─────────┐
│    u    │
│ int32[] │
├─────────┤
│ [1, 2]  │
│ [3]     │
└─────────┘
┌───────┐
│   v   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
```

### a NULL list and an empty one inside give nothing

```x
(sql "SELECT unnest([[1, 2], NULL, []], recursive := true) AS u")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
```

### a NULL element stays

```x
(sql "SELECT unnest([[1, NULL], [NULL]], recursive := true) AS u")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│  NULL │
│  NULL │
└───────┘
```

### a list of one level

```x
(sql "SELECT unnest([1, 2], recursive := true) AS u")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
```

### a NULL

```x
(sql "SELECT unnest(NULL, recursive := true) AS u; SELECT unnest(NULL::INT[][], recursive := true) AS v")
```
---
```output
┌────────┐
│   u    │
│ "null" │
└────────┘
  0 rows
┌────────┐
│   v    │
│ int32  │
└────────┘
  0 rows
```

### two beside each other, the shorter filled out with NULLs

```x
(sql "SELECT unnest([1, 2], recursive := true) AS u, unnest([[7], [8, 9, 10]], recursive := true) AS v")
```
---
```output
┌───────┬───────┐
│   u   │   v   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     7 │
│     2 │  NULL │
│     1 │     8 │
│     2 │     9 │
│  NULL │    10 │
└───────┴───────┘
```

### unlike depths: the deeper list has a level taken off first, and the other is unnested again beside each of its elements

```x
(sql "SELECT unnest([1, 2], recursive := true) AS u, unnest([[7], [8, 9]], recursive := true) AS v, unnest([[[5]], [[6, 4]]], recursive := true) AS w")
```
---
```output
┌───────┬───────┬───────┐
│   u   │   v   │   w   │
│ int32 │ int32 │ int32 │
├───────┼───────┼───────┤
│     1 │     7 │     5 │
│     2 │  NULL │  NULL │
│     1 │     8 │  NULL │
│     2 │     9 │  NULL │
│     1 │     7 │     6 │
│     2 │  NULL │     4 │
│     1 │     8 │  NULL │
│     2 │     9 │  NULL │
└───────┴───────┴───────┘
```

### a deeper list that is empty leaves no row

```x
(sql "SELECT unnest([1, 2]) AS u, unnest([]::INT[][], recursive := true) AS v; SELECT unnest([1, 2]) AS u, unnest([[], []]::INT[][], recursive := true) AS v")
```
---
```output
┌───────┬───────┐
│   u   │   v   │
│ int32 │ int32 │
└───────┴───────┘
     0 rows    
┌───────┬───────┐
│   u   │   v   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │  NULL │
│     2 │  NULL │
│     1 │  NULL │
│     2 │  NULL │
└───────┴───────┘
```

### the heading without an alias

```x
(sql "SELECT unnest([[1]], recursive := true); SELECT unnest([[1]], max_depth := 2)")
```
---
```output
┌────────────────────────────────────────────────────────┐
│ unnest(list_value(list_value(1)), "recursive" := true) │
│                         int32                          │
├────────────────────────────────────────────────────────┤
│                                                      1 │
└────────────────────────────────────────────────────────┘
┌───────────────────────────────────────────────────┐
│ unnest(list_value(list_value(1)), max_depth := 2) │
│                       int32                       │
├───────────────────────────────────────────────────┤
│                                                 1 │
└───────────────────────────────────────────────────┘
```

### a number and a truth for recursive

```x
(sql "SELECT unnest([[1, 2]], recursive := 1) AS u; SELECT unnest([[1, 2]], recursive := 0) AS v")
```
---
```output
┌───────┐
│   u   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
┌─────────┐
│    v    │
│ int32[] │
├─────────┤
│ [1, 2]  │
└─────────┘
```

### over a column, and in a subquery

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[][], s STRUCT(a INT, b STRUCT(c INT, d INT[]))); INSERT INTO t VALUES (1, [[1, 2], [3]], {'a': 1, 'b': {'c': 2, 'd': [5, 6]}}), (2, [[], NULL, [4]], NULL), (3, NULL, {'a': 7, 'b': NULL}); SELECT id, unnest(l, recursive := true) AS u FROM t ORDER BY id, u; SELECT sum(u) FROM (SELECT unnest(l, recursive := true) AS u FROM t)")
```
---
```output
┌───────┬───────┐
│  id   │   u   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     1 │
│     1 │     2 │
│     1 │     3 │
│     2 │     4 │
└───────┴───────┘
┌────────┐
│ sum(u) │
│ int128 │
├────────┤
│     10 │
└────────┘
```

## structs

### a struct inside a struct is its fields too

```x
(sql "SELECT unnest({'a': 1, 'b': {'c': 2, 'd': [5, 6]}}, recursive := true)")
```
---
```output
┌───────┬───────┬─────────┐
│   a   │   c   │    d    │
│ int32 │ int32 │ int32[] │
├───────┼───────┼─────────┤
│     1 │     2 │ [5, 6]  │
└───────┴───────┴─────────┘
```

### without, one level

```x
(sql "SELECT unnest({'a': 1, 'b': {'c': 2}})")
```
---
```output
┌───────┬───────────────────┐
│   a   │         b         │
│ int32 │ struct(c integer) │
├───────┼───────────────────┤
│     1 │ {'c': 2}          │
└───────┴───────────────────┘
```

### max_depth counts the levels of structs

```x
(sql "SELECT unnest({'a': 1, 'b': {'c': 2, 'e': {'f': 3}}}, max_depth := 2)")
```
---
```output
┌───────┬───────┬───────────────────┐
│   a   │   c   │         e         │
│ int32 │ int32 │ struct(f integer) │
├───────┼───────┼───────────────────┤
│     1 │     2 │ {'f': 3}          │
└───────┴───────┴───────────────────┘
```

### keep_parent_names names a field with the fields it is under

```x
(sql "SELECT unnest({'a': 1, 'b': {'c': 2, 'e': {'f': 3}}}, recursive := true, keep_parent_names := true)")
```
---
```output
┌───────┬───────┬───────┐
│   a   │  b.c  │ b.e.f │
│ int32 │ int32 │ int32 │
├───────┼───────┼───────┤
│     1 │     2 │     3 │
└───────┴───────┴───────┘
```

### a list of structs is a row for each, its fields the columns

```x
(sql "SELECT unnest([{'a': 1, 'b': [1, 2]}, {'a': 2, 'b': NULL}], recursive := true)")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ int32[] │
├───────┼─────────┤
│     1 │ [1, 2]  │
│     2 │ NULL    │
└───────┴─────────┘
```

### a list inside a struct stays a list

```x
(sql "SELECT unnest([{'a': {'x': 1, 'y': [{'z': 2}]}, 'b': [1, 2]}, {'a': NULL, 'b': NULL}], recursive := true)")
```
---
```output
┌───────┬─────────────────────┬─────────┐
│   x   │          y          │    b    │
│ int32 │ struct(z integer)[] │ int32[] │
├───────┼─────────────────────┼─────────┤
│     1 │ [{'z': 2}]          │ [1, 2]  │
│  NULL │ NULL                │ NULL    │
└───────┴─────────────────────┴─────────┘
```

### the levels are counted through the list and then the structs

```x
(sql "SELECT unnest([{'a': {'x': 1}}], max_depth := 2); SELECT unnest([{'a': {'x': 1}}], max_depth := 3); SELECT unnest([[{'a': {'x': 1}}]], max_depth := 2) AS u")
```
---
```output
┌───────────────────┐
│         a         │
│ struct(x integer) │
├───────────────────┤
│ {'x': 1}          │
└───────────────────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌─────────────────────────────┐
│              u              │
│ struct(a struct(x integer)) │
├─────────────────────────────┤
│ {'a': {'x': 1}}             │
└─────────────────────────────┘
```

### a list of structs with the parents' names

```x
(sql "SELECT unnest([{'a': {'x': 1}, 'b': 2}], recursive := true, keep_parent_names := true)")
```
---
```output
┌───────┬───────┐
│  a.x  │   b   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
```

### a column

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[][], s STRUCT(a INT, b STRUCT(c INT, d INT[]))); INSERT INTO t VALUES (1, [[1, 2], [3]], {'a': 1, 'b': {'c': 2, 'd': [5, 6]}}), (2, [[], NULL, [4]], NULL), (3, NULL, {'a': 7, 'b': NULL}); SELECT id, unnest(s, recursive := true) FROM t ORDER BY id")
```
---
```output
┌───────┬───────┬───────┬─────────┐
│  id   │   a   │   c   │    d    │
│ int32 │ int32 │ int32 │ int32[] │
├───────┼───────┼───────┼─────────┤
│     1 │     1 │     2 │ [5, 6]  │
│     2 │  NULL │  NULL │ NULL    │
│     3 │     7 │  NULL │ NULL    │
└───────┴───────┴───────┴─────────┘
```

## errors

### a name unnest does not have

```x
(sql "SELECT unnest([[1, 2], [3]], depth := 1)")
```
---
```output
Binder Error: Unsupported parameter "depth" for unnest
```

### a depth of nothing

```x
(sql "SELECT unnest([[1, 2], [3]], max_depth := 0)")
```
---
```output
Binder Error: UNNEST cannot have a max depth of 0
```

### a NULL for recursive

```x
(sql "SELECT unnest([[1, 2]], recursive := NULL)")
```
---
```output
Binder Error: UNNEST parameter "recursive" cannot be NULL
```

### a value that is not a constant

```x
(sql "SELECT unnest([[1, 2]], recursive := x) FROM (SELECT true AS x)")
```
---
```output
Binder Error: UNNEST - unsupported extra argument, unnest only supports recursive := [true/false], max_depth := # or keep_parent_names := [true/false]
```

### what is no list

```x
(sql "SELECT unnest(5, recursive := true)")
```
---
```output
Binder Error: UNNEST() can only be applied to lists, structs and NULL, not INTEGER
```

### in a FROM unnest takes no names

```x
(sql "SELECT * FROM unnest([[1, 2], [3]], recursive := true)")
```
---
```output
Binder Error: Invalid named parameter "recursive" for function unnest
```

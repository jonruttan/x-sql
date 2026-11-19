unnest: a row for each element of a list, in the list of a SELECT and
as a table in a FROM.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## unnest items

### unnest in the list of a SELECT is a row for each element

```x
(sql "SELECT unnest([1, 2, 3])")
```
---
```output
┌─────────────────────────────┐
│ unnest(list_value(1, 2, 3)) │
│            int32            │
├─────────────────────────────┤
│                           1 │
│                           2 │
│                           3 │
└─────────────────────────────┘
```

### what is beside it comes once with each

```x
(sql "SELECT unnest([1, 2, 3]) AS x, 'a' AS y")
```
---
```output
┌───────┬─────────┐
│   x   │    y    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ a       │
│     2 │ a       │
│     3 │ a       │
└───────┴─────────┘
```

### two of them go side by side, the shorter ending in NULLs

```x
(sql "SELECT unnest([1, 2]) a, unnest(['x', 'y', 'z']) b; SELECT unnest(range(3)) i, unnest(['a']) s")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ y       │
│  NULL │ z       │
└───────┴─────────┘
┌───────┬─────────┐
│   i   │    s    │
│ int64 │ varchar │
├───────┼─────────┤
│     0 │ a       │
│     1 │ NULL    │
│     2 │ NULL    │
└───────┴─────────┘
```

### an empty list and a NULL list are no row; a NULL in a list is a row

```x
(sql "SELECT unnest([]) a; SELECT unnest(NULL::INT[]) b; SELECT unnest([NULL, 2]) c")
```
---
```output
┌────────┐
│   a    │
│ "null" │
└────────┘
  0 rows
┌────────┐
│   b    │
│ int32  │
└────────┘
  0 rows
┌───────┐
│   c   │
│ int32 │
├───────┤
│  NULL │
│     2 │
└───────┘
```

### inside an expression

```x
(sql "SELECT unnest([1, 2]) + 10, len(unnest(['ab', 'c'])); SELECT coalesce(unnest([NULL, 2]), 0); SELECT CASE WHEN true THEN unnest([1, 2]) END; SELECT [unnest([1, 2])]")
```
---
```output
┌─────────────────────────────────┬────────────────────────────────────┐
│ (unnest(list_value(1, 2)) + 10) │ len(unnest(list_value('ab', 'c'))) │
│              int32              │               int64                │
├─────────────────────────────────┼────────────────────────────────────┤
│                              11 │                                  2 │
│                              12 │                                  1 │
└─────────────────────────────────┴────────────────────────────────────┘
┌──────────────────────────────────────────┐
│ COALESCE(unnest(list_value(NULL, 2)), 0) │
│                  int32                   │
├──────────────────────────────────────────┤
│                                        0 │
│                                        2 │
└──────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ CASE  WHEN (true) THEN (unnest(list_value(1, 2))) ELSE NULL END │
│                              int32                              │
├─────────────────────────────────────────────────────────────────┤
│                                                               1 │
│                                                               2 │
└─────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────┐
│ list_value(unnest(list_value(1, 2))) │
│               int32[]                │
├──────────────────────────────────────┤
│ [1]                                  │
│ [2]                                  │
└──────────────────────────────────────┘
```

### two in one expression

```x
(sql "SELECT unnest([1, 2]) AS a, unnest([10, 20]) + unnest([100, 200, 300]) AS b")
```
---
```output
┌───────┬───────┐
│   a   │   b   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   110 │
│     2 │   220 │
│  NULL │  NULL │
└───────┴───────┘
```

### a list of lists gives lists, and a list of structs structs

```x
(sql "SELECT unnest([[1, 2], [3]]) a; SELECT unnest([{'a': 1, 'b': 'x'}, {'a': 2, 'b': 'y'}])")
```
---
```output
┌─────────┐
│    a    │
│ int32[] │
├─────────┤
│ [1, 2]  │
│ [3]     │
└─────────┘
┌──────────────────────────────────────────────────────────────────────────────────┐
│ unnest(list_value(struct_pack(a := 1, b := 'x'), struct_pack(a := 2, b := 'y'))) │
│                           struct(a integer, b varchar)                           │
├──────────────────────────────────────────────────────────────────────────────────┤
│ {'a': 1, 'b': x}                                                                 │
│ {'a': 2, 'b': y}                                                                 │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### a struct is unnested into a column for each field

```x
(sql "SELECT unnest({'a': 1, 'b': 'x'}); SELECT unnest({'a': 1, 'b': 'x'}), 5 AS z")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
└───────┴─────────┘
┌───────┬─────────┬───────┐
│   a   │    b    │   z   │
│ int32 │ varchar │ int32 │
├───────┼─────────┼───────┤
│     1 │ x       │     5 │
└───────┴─────────┴───────┘
```

### the functions that make a list

```x
(sql "SELECT unnest(string_split('a,b', ',')) AS part; SELECT unnest(range(2, 5)) n")
```
---
```output
┌─────────┐
│  part   │
│ varchar │
├─────────┤
│ a       │
│ b       │
└─────────┘
┌───────┐
│   n   │
│ int64 │
├───────┤
│     2 │
│     3 │
│     4 │
└───────┘
```

## unnest of a column

### each row once for each element of its list; a row whose list is empty or NULL is gone

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT id, unnest(l) FROM t")
```
---
```output
┌───────┬───────────┐
│  id   │ unnest(l) │
│ int32 │   int32   │
├───────┼───────────┤
│     1 │        10 │
│     1 │        20 │
│     4 │        30 │
└───────┴───────────┘
```

### after WHERE and before ORDER BY, DISTINCT and LIMIT

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT id, unnest(l) AS x FROM t WHERE id < 4 ORDER BY x DESC; SELECT id, unnest(l) x FROM t ORDER BY id DESC, x LIMIT 2; SELECT DISTINCT unnest([1, 1, 2]) x ORDER BY x; SELECT unnest([3, 1, 2]) x ORDER BY x LIMIT 2")
```
---
```output
┌───────┬───────┐
│  id   │   x   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │    20 │
│     1 │    10 │
└───────┴───────┘
┌───────┬───────┐
│  id   │   x   │
│ int32 │ int32 │
├───────┼───────┤
│     4 │    30 │
│     1 │    10 │
└───────┴───────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
└───────┘
```

### after grouping: the unnest of what a group gathered

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT unnest(list(id)) FROM t; SELECT id, unnest(list(l)) FROM t WHERE id IN (1, 4) GROUP BY id ORDER BY id")
```
---
```output
┌──────────────────┐
│ unnest(list(id)) │
│      int32       │
├──────────────────┤
│                1 │
│                2 │
│                3 │
│                4 │
└──────────────────┘
┌───────┬─────────────────┐
│  id   │ unnest(list(l)) │
│ int32 │     int32[]     │
├───────┼─────────────────┤
│     1 │ [10, 20]        │
│     4 │ [30]            │
└───────┴─────────────────┘
```

### a window is answered before the rows are made

```x
(sql "SELECT unnest([1, 2]) x, row_number() OVER () r")
```
---
```output
┌───────┬───────┐
│   x   │   r   │
│ int32 │ int64 │
├───────┼───────┤
│     1 │     1 │
│     2 │     1 │
└───────┴───────┘
```

### in a subquery, a UNION, and a subquery that reads the row outside

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT * FROM (SELECT unnest([1, 2]) x) WHERE x > 1; SELECT unnest([1, 2]) x UNION ALL SELECT 9; SELECT id FROM t WHERE 20 IN (SELECT unnest(l)); SELECT x, unnest(x) FROM (SELECT [1, 2] AS x)")
```
---
```output
┌───────┐
│   x   │
│ int32 │
├───────┤
│     2 │
└───────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     9 │
└───────┘
┌───────┐
│  id   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌─────────┬───────────┐
│    x    │ unnest(x) │
│ int32[] │   int32   │
├─────────┼───────────┤
│ [1, 2]  │         1 │
│ [1, 2]  │         2 │
└─────────┴───────────┘
```

### the fields of unnested structs

```x
(sql "SELECT s.a, s.b FROM (SELECT unnest([{'a': 1, 'b': 'x'}, {'a': 2, 'b': 'y'}]) AS s)")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ y       │
└───────┴─────────┘
```

## unnest tables

### unnest in a FROM is a table of one column, named unnest unless an alias names it

```x
(sql "FROM unnest([1, 2, 3]); SELECT * FROM unnest([1, 2, 3]) AS t(x); SELECT x + 1 FROM unnest([1, 2]) t(x) WHERE x > 1; SELECT u.unnest FROM unnest(['a']) u")
```
---
```output
┌────────┐
│ unnest │
│ int32  │
├────────┤
│      1 │
│      2 │
│      3 │
└────────┘
┌───────┐
│   x   │
│ int32 │
├───────┤
│     1 │
│     2 │
│     3 │
└───────┘
┌─────────┐
│ (x + 1) │
│  int32  │
├─────────┤
│       3 │
└─────────┘
┌─────────┐
│ unnest  │
│ varchar │
├─────────┤
│ a       │
└─────────┘
```

### after a table it is read for each of the table's rows

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT id, x FROM t, unnest(l) AS u(x); SELECT id, x FROM t CROSS JOIN unnest(t.l) AS u(x) ORDER BY x DESC")
```
---
```output
┌───────┬───────┐
│  id   │   x   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │    10 │
│     1 │    20 │
│     4 │    30 │
└───────┴───────┘
┌───────┬───────┐
│  id   │   x   │
│ int32 │ int32 │
├───────┼───────┤
│     4 │    30 │
│     1 │    20 │
│     1 │    10 │
└───────┴───────┘
```

### a LEFT JOIN keeps the rows with no element

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT id, x FROM t LEFT JOIN unnest(l) AS u(x) ON true ORDER BY id, x")
```
---
```output
┌───────┬───────┐
│  id   │   x   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │    10 │
│     1 │    20 │
│     2 │  NULL │
│     3 │  NULL │
│     4 │    30 │
└───────┴───────┘
```

### grouped, and in a subquery that reads the row outside

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT id, sum(x), count(*) FROM t, unnest(l) u(x) GROUP BY id ORDER BY id; SELECT id, (SELECT max(x) FROM unnest(l) u(x)) FROM t ORDER BY id")
```
---
```output
┌───────┬────────┬──────────────┐
│  id   │ sum(x) │ count_star() │
│ int32 │ int128 │    int64     │
├───────┼────────┼──────────────┤
│     1 │     30 │            2 │
│     4 │     30 │            1 │
└───────┴────────┴──────────────┘
┌───────┬────────────────────────────────────────┐
│  id   │ (SELECT max(x) FROM unnest(l) AS u(x)) │
│ int32 │                 int32                  │
├───────┼────────────────────────────────────────┤
│     1 │                                     20 │
│     2 │                                   NULL │
│     3 │                                   NULL │
│     4 │                                     30 │
└───────┴────────────────────────────────────────┘
```

### two of them are every pair, and one joins another

```x
(sql "SELECT a, b FROM unnest([1, 2]) x(a), unnest(['p', 'q']) y(b) ORDER BY a, b; SELECT * FROM unnest([1, 2]) JOIN unnest([2, 3]) u(v) ON unnest = v")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ p       │
│     1 │ q       │
│     2 │ p       │
│     2 │ q       │
└───────┴─────────┘
┌────────┬───────┐
│ unnest │   v   │
│ int32  │ int32 │
├────────┼───────┤
│      2 │     2 │
└────────┴───────┘
```

### a list of structs is a column of structs

```x
(sql "SELECT * FROM unnest([{'a': 1, 'b': 2}])")
```
---
```output
┌──────────────────────────────┐
│            unnest            │
│ struct(a integer, b integer) │
├──────────────────────────────┤
│ {'a': 1, 'b': 2}             │
└──────────────────────────────┘
```

## column names of an alias

### an alias names a table's columns in parentheses, the first of them when it names fewer

```x
(sql "SELECT * FROM (SELECT 1 AS a, 2 AS b) AS s(p, q); SELECT s.p, b FROM (SELECT 1 AS a, 2 AS b) s(p); CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10]); SELECT k, v FROM t AS r(k, v)")
```
---
```output
┌───────┬───────┐
│   p   │   q   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
┌───────┬───────┐
│   p   │   b   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     2 │
└───────┴───────┘
┌───────┬─────────┐
│   k   │    v    │
│ int32 │ int32[] │
├───────┼─────────┤
│     1 │ [10]    │
└───────┴─────────┘
```

## unnest errors

### what is no list

```x
(sql "SELECT unnest(5)")
```
---
```output
Binder Error: UNNEST() can only be applied to lists, structs and NULL, not INTEGER
```

### no argument

```x
(sql "SELECT unnest()")
```
---
```output
Binder Error: UNNEST() requires at least one argument
```

### two arguments

```x
(sql "SELECT unnest([1], [2])")
```
---
```output
Binder Error: UNNEST - unsupported extra argument, unnest only supports recursive := [true/false], max_depth := # or keep_parent_names := [true/false]
```

### one inside another

```x
(sql "SELECT unnest(unnest([[1, 2], [3]]))")
```
---
```output
Binder Error: Nested UNNEST calls are not supported - use UNNEST(x, recursive := true) to unnest multiple levels
```

### in WHERE

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT id FROM t WHERE unnest(l) > 10")
```
---
```output
Binder Error: UNNEST not supported here
```

### inside an aggregate

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[]); INSERT INTO t VALUES (1, [10, 20]), (2, []), (3, NULL), (4, [30]); SELECT sum(unnest(l)) FROM t")
```
---
```output
Binder Error: UNNEST not supported here
```

### a struct in a FROM

```x
(sql "SELECT * FROM unnest({'a': 1, 'b': 2})")
```
---
```output
Binder Error: UNNEST requires a single list or array as input
```

### more names than columns

```x
(sql "SELECT * FROM (SELECT 1 AS a) s(p, q)")
```
---
```output
Binder Error: table "s" has 1 columns available but 2 columns specified
```

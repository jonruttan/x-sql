Tuples, the structs whose fields have no names, and list_zip, which
answers a list of them (`sql/eval.x`).

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## tuples

### values in parentheses with commas between are a tuple, a struct whose fields have no names

```x
(sql "SELECT (1, 'a') AS r, typeof((1, 'a')) AS t")
```
---
```output
┌─────────────────────────┬─────────────────────────┐
│            r            │            t            │
│ tuple(integer, varchar) │         varchar         │
├─────────────────────────┼─────────────────────────┤
│ (1, a)                  │ TUPLE(INTEGER, VARCHAR) │
└─────────────────────────┴─────────────────────────┘
```

### row is the same

```x
(sql "SELECT row(1, 2) AS w, row(1) AS o, row(NULL) AS n")
```
---
```output
┌─────────────────────────┬────────────────┬───────────────┐
│            w            │       o        │       n       │
│ tuple(integer, integer) │ tuple(integer) │ tuple("null") │
├─────────────────────────┼────────────────┼───────────────┤
│ (1, 2)                  │ (1,)           │ (NULL,)       │
└─────────────────────────┴────────────────┴───────────────┘
```

### its heading spelled out

```x
(sql "SELECT (1, 'a'), row(1.5, [1], {'a': 1})")
```
---
```output
┌─────────────────────────┬───────────────────────────────────────────────────┐
│      "row"(1, 'a')      │  "row"(1.5, list_value(1), struct_pack(a := 1))   │
│ tuple(integer, varchar) │ tuple(decimal(2,1), integer[], struct(a integer)) │
├─────────────────────────┼───────────────────────────────────────────────────┤
│ (1, a)                  │ (1.5, [1], {'a': 1})                              │
└─────────────────────────┴───────────────────────────────────────────────────┘
```

### a member is read by its place

```x
(sql "SELECT (1, 'a')[1] AS p, (1, 'a')[2] AS q, struct_extract(row(5, 6), 2) AS y")
```
---
```output
┌───────┬─────────┬───────┐
│   p   │    q    │   y   │
│ int32 │ varchar │ int32 │
├───────┼─────────┼───────┤
│     1 │ a       │     6 │
└───────┴─────────┴───────┘
```

### tuples are compared member by member

```x
(sql "SELECT row(1, 2) = row(1, 2) AS e, row(1, 2) < row(1, 3) AS l, row(2, 1) > row(1, 9) AS g, row(1, NULL) IS NULL AS n")
```
---
```output
┌─────────┬─────────┬─────────┬─────────┐
│    e    │    l    │    g    │    n    │
│ boolean │ boolean │ boolean │ boolean │
├─────────┼─────────┼─────────┼─────────┤
│ true    │ true    │ true    │ false   │
└─────────┴─────────┴─────────┴─────────┘
```

### as text

```x
(sql "SELECT row(1, 'a')::VARCHAR AS v, CAST((1, 2) AS VARCHAR) AS w")
```
---
```output
┌─────────┬─────────┐
│    v    │    w    │
│ varchar │ varchar │
├─────────┼─────────┤
│ (1, a)  │ (1, 2)  │
└─────────┴─────────┘
```

### cast to a struct, the members take the fields' names in order

```x
(sql "SELECT (1, 'a')::STRUCT(n INT, s VARCHAR) AS c, ((2, 'b')::STRUCT(n INT, s VARCHAR)).s AS f")
```
---
```output
┌──────────────────────────────┬─────────┐
│              c               │    f    │
│ struct(n integer, s varchar) │ varchar │
├──────────────────────────────┼─────────┤
│ {'n': 1, 's': a}             │ b       │
└──────────────────────────────┴─────────┘
```

### in a list, and sorted

```x
(sql "SELECT [row(1, 'a'), row(2, 'b')] AS l, list_sort([(2, 'b'), (1, 'z'), (1, 'a')]) AS s")
```
---
```output
┌───────────────────────────┬───────────────────────────┐
│             l             │             s             │
│ tuple(integer, varchar)[] │ tuple(integer, varchar)[] │
├───────────────────────────┼───────────────────────────┤
│ [(1, a), (2, b)]          │ [(1, a), (1, z), (2, b)]  │
└───────────────────────────┴───────────────────────────┘
```

### one in parentheses is still itself

```x
(sql "SELECT (1) AS a, ((2)) AS b, (1 + 2) * 3 AS c, 5 IN (1, 5) AS d")
```
---
```output
┌───────┬───────┬───────┬─────────┐
│   a   │   b   │   c   │    d    │
│ int32 │ int32 │ int32 │ boolean │
├───────┼───────┼───────┼─────────┤
│     1 │     2 │     9 │ true    │
└───────┴───────┴───────┴─────────┘
```

## list_zip

### list_zip is a list of tuples: the first elements, then the second

```x
(sql "SELECT list_zip([1, 2], ['a', 'b']) AS z, typeof(list_zip([1, 2], ['a'])) AS t")
```
---
```output
┌───────────────────────────┬───────────────────────────┐
│             z             │             t             │
│ tuple(integer, varchar)[] │          varchar          │
├───────────────────────────┼───────────────────────────┤
│ [(1, a), (2, b)]          │ TUPLE(INTEGER, VARCHAR)[] │
└───────────────────────────┴───────────────────────────┘
```

### a shorter list is filled out with NULLs

```x
(sql "SELECT list_zip([1, 2], ['a', 'b', 'c']) AS z")
```
---
```output
┌─────────────────────────────┐
│              z              │
│  tuple(integer, varchar)[]  │
├─────────────────────────────┤
│ [(1, a), (2, b), (NULL, c)] │
└─────────────────────────────┘
```

### a true last cuts to the shortest, and a false or a NULL does not

```x
(sql "SELECT list_zip([1, 2], [9], true) AS t, list_zip([1, 2], [9], false) AS f, list_zip([1], [2, 3], NULL::BOOLEAN) AS n")
```
---
```output
┌───────────────────────────┬───────────────────────────┬───────────────────────────┐
│             t             │             f             │             n             │
│ tuple(integer, integer)[] │ tuple(integer, integer)[] │ tuple(integer, integer)[] │
├───────────────────────────┼───────────────────────────┼───────────────────────────┤
│ [(1, 9)]                  │ [(1, 9), (2, NULL)]       │ [(1, 2), (NULL, 3)]       │
└───────────────────────────┴───────────────────────────┴───────────────────────────┘
```

### one list, and three

```x
(sql "SELECT list_zip([1, 2]) AS z, array_zip([1], [2], [3]) AS y")
```
---
```output
┌──────────────────┬────────────────────────────────────┐
│        z         │                 y                  │
│ tuple(integer)[] │ tuple(integer, integer, integer)[] │
├──────────────────┼────────────────────────────────────┤
│ [(1,), (2,)]     │ [(1, 2, 3)]                        │
└──────────────────┴────────────────────────────────────┘
```

### a NULL list is an empty one

```x
(sql "SELECT list_zip([1], NULL) AS z, list_zip(NULL::INT[], [1]) AS y, list_zip(NULL, NULL) AS x")
```
---
```output
┌──────────────────────────┬───────────────────────────┬─────────────────────────┐
│            z             │             y             │            x            │
│ tuple(integer, "null")[] │ tuple(integer, integer)[] │ tuple("null", "null")[] │
├──────────────────────────┼───────────────────────────┼─────────────────────────┤
│ [(1, NULL)]              │ [(NULL, 1)]               │ []                      │
└──────────────────────────┴───────────────────────────┴─────────────────────────┘
```

### lists of lists and of structs

```x
(sql "SELECT list_zip([[1], [2]], [{'a': 1}]) AS z")
```
---
```output
┌───────────────────────────────────────┐
│                   z                   │
│ tuple(integer[], struct(a integer))[] │
├───────────────────────────────────────┤
│ [([1], {'a': 1}), ([2], NULL)]        │
└───────────────────────────────────────┘
```

### a tuple of it, and a member of that

```x
(sql "SELECT (list_zip([1, 2], ['a', 'b']))[1] AS s, (list_zip([1, 2], ['a', 'b']))[2][1] AS f")
```
---
```output
┌─────────────────────────┬───────┐
│            s            │   f   │
│ tuple(integer, varchar) │ int32 │
├─────────────────────────┼───────┤
│ (1, a)                  │     2 │
└─────────────────────────┴───────┘
```

### unnested, a row for each tuple

```x
(sql "SELECT unnest(list_zip([1, 2], ['a', 'b'])) AS u; SELECT x FROM (SELECT unnest(list_zip([2, 1], ['b', 'a'])) AS x) ORDER BY x")
```
---
```output
┌─────────────────────────┐
│            u            │
│ tuple(integer, varchar) │
├─────────────────────────┤
│ (1, a)                  │
│ (2, b)                  │
└─────────────────────────┘
┌─────────────────────────┐
│            x            │
│ tuple(integer, varchar) │
├─────────────────────────┤
│ (1, a)                  │
│ (2, b)                  │
└─────────────────────────┘
```

### over columns

```x
(sql "CREATE OR REPLACE TABLE t (id INT, l INT[], m VARCHAR[]); INSERT INTO t VALUES (1, [1, 2], ['a', 'b']), (2, [3], NULL), (3, NULL, ['z']); SELECT id, list_zip(l, m) AS z FROM t ORDER BY id")
```
---
```output
┌───────┬───────────────────────────┐
│  id   │             z             │
│ int32 │ tuple(integer, varchar)[] │
├───────┼───────────────────────────┤
│     1 │ [(1, a), (2, b)]          │
│     2 │ [(3, NULL)]               │
│     3 │ [(NULL, z)]               │
└───────┴───────────────────────────┘
```

### with a lambda

```x
(sql "SELECT list_transform(list_zip([1, 2], [10, 20]), lambda p: p[1] + p[2]) AS s")
```
---
```output
┌──────────┐
│    s     │
│ int32[]  │
├──────────┤
│ [11, 22] │
└──────────┘
```

## errors

### a place a tuple has not

```x
(sql "SELECT row(1, 'a')[3]")
```
---
```output
Binder Error: Key index 3 for struct_extract out of range - expected an index between 1 and 2
```

### and place nothing

```x
(sql "SELECT row(1, 'a')[0]")
```
---
```output
Binder Error: Key index 0 for struct_extract out of range - expected an index between 1 and 2
```

### a place in a struct with names

```x
(sql "SELECT {'a': 1, 'b': 'x'}[1]")
```
---
```output
Binder Error: struct_extract with an integer key can only be used on unnamed structs, use a string key instead
```

### a cast to a struct of another size

```x
(sql "SELECT row(1, 'a')::STRUCT(n INT)")
```
---
```output
Mismatch Type Error: Type TUPLE(INTEGER, VARCHAR) does not match with STRUCT(n INTEGER). Cannot cast STRUCTs of different size
```

### list_zip of nothing

```x
(sql "SELECT list_zip()")
```
---
```output
Binder Error: Provide at least one argument to list_zip
```

### of a truth alone

```x
(sql "SELECT list_zip(true)")
```
---
```output
Binder Error: Provide at least one list argument to list_zip
```

### of what is no list

```x
(sql "SELECT list_zip([1, 2], 5)")
```
---
```output
Binder Error: Parameter type needs to be List
```

### a truth that is not last

```x
(sql "SELECT list_zip([1], true, [2])")
```
---
```output
Binder Error: Parameter type needs to be List
```

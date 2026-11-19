Structs: a value that holds named values, each of its own type.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## struct values

### a struct in braces: names and values

```x
(sql "SELECT {'a': 1, 'b': 'x'} s, typeof({'a': 1, 'b': 'x'})")
```
---
```output
┌──────────────────────────────┬───────────────────────────────────────┐
│              s               │ typeof(struct_pack(a := 1, b := 'x')) │
│ struct(a integer, b varchar) │                varchar                │
├──────────────────────────────┼───────────────────────────────────────┤
│ {'a': 1, 'b': x}             │ STRUCT(a INTEGER, b VARCHAR)          │
└──────────────────────────────┴───────────────────────────────────────┘
```

### structs and lists inside one another

```x
(sql "SELECT {'a': [1, 2], 'b': {'c': NULL}} s, typeof({'a': [1, 2], 'b': {'c': NULL}}), [{'a': 1}, {'a': 2}] l, typeof([{'a': 1}]), {'a': [1.5]} d")
```
---
```output
┌─────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────┬──────────────────────┬─────────────────────────────────────────┬──────────────────────────┐
│                    s                    │ typeof(struct_pack(a := list_value(1, 2), b := struct_pack(c := NULL))) │          l           │ typeof(list_value(struct_pack(a := 1))) │            d             │
│ struct(a integer[], b struct(c "null")) │                                 varchar                                 │ struct(a integer)[]  │                 varchar                 │ struct(a decimal(2,1)[]) │
├─────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────┼──────────────────────┼─────────────────────────────────────────┼──────────────────────────┤
│ {'a': [1, 2], 'b': {'c': NULL}}         │ STRUCT(a INTEGER[], b STRUCT(c "NULL"))                                 │ [{'a': 1}, {'a': 2}] │ STRUCT(a INTEGER)[]                     │ {'a': [1.5]}             │
└─────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────┴──────────────────────┴─────────────────────────────────────────┴──────────────────────────┘
```

### struct_pack is the same

```x
(sql "SELECT struct_pack(a := 1, b := 'x'), struct_pack(a := 1, \"b c\" := 2)")
```
---
```output
┌───────────────────────────────┬──────────────────────────────────┐
│ struct_pack(a := 1, b := 'x') │ struct_pack(a := 1, "b c" := 2)  │
│ struct(a integer, b varchar)  │ struct(a integer, "b c" integer) │
├───────────────────────────────┼──────────────────────────────────┤
│ {'a': 1, 'b': x}              │ {'a': 1, 'b c': 2}               │
└───────────────────────────────┴──────────────────────────────────┘
```

### text in a struct is in quotes when it could be mistaken, and a name that is no plain word in its type

```x
(sql "SELECT {'k': ' a', 'l': 'a:b', 'm': 'x y', 'n': '', 'o': 'null', 't': 'a''b', 'u': DATE '2026-01-01', 'v': 1.50, 'w': true, 'x': NULL} s; SELECT {'a b': 1, 'c': 2.5} s")
```
---
```output
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                           s                                                            │
│ struct(k varchar, l varchar, m varchar, n varchar, o varchar, t varchar, u date, v decimal(3,2), w boolean, x "null")  │
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ {'k': ' a', 'l': 'a:b', 'm': x y, 'n': '', 'o': 'null', 't': 'a\'b', 'u': 2026-01-01, 'v': 1.50, 'w': true, 'x': NULL} │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
┌───────────────────────────────────────┐
│                   s                   │
│ struct("a b" integer, c decimal(2,1)) │
├───────────────────────────────────────┤
│ {'a b': 1, 'c': 2.5}                  │
└───────────────────────────────────────┘
```

## struct fields

### a field after a point, in brackets, and by struct_extract

```x
(sql "SELECT ({'a': 1, 'b': 'x'}).a, ({'a': 1, 'b': 'x'})['b'], struct_extract({'a': 1, 'b': 'x'}, 'a'), {'a': 1}.a, ({'a': {'c': 5}}).a.c")
```
---
```output
┌───────────────────────────────────┬────────────────────────────────────┬────────────────────────────────────────────────────┬─────────────────────────┬───────────────────────────────────────────────┐
│ (struct_pack(a := 1, b := 'x')).a │ struct_pack(a := 1, b := 'x')['b'] │ struct_extract(struct_pack(a := 1, b := 'x'), 'a') │ (struct_pack(a := 1)).a │ ((struct_pack(a := struct_pack(c := 5))).a).c │
│               int32               │              varchar               │                       int32                        │          int32          │                     int32                     │
├───────────────────────────────────┼────────────────────────────────────┼────────────────────────────────────────────────────┼─────────────────────────┼───────────────────────────────────────────────┤
│                                 1 │ x                                  │                                                  1 │                       1 │                                             5 │
└───────────────────────────────────┴────────────────────────────────────┴────────────────────────────────────────────────────┴─────────────────────────┴───────────────────────────────────────────────┘
```

### a field of a column, with its table or without, headed by the field

```x
(sql "CREATE OR REPLACE TABLE t (id INT, s STRUCT(a INT, b VARCHAR)); INSERT INTO t VALUES (1, {'a': 1, 'b': 'x'}), (2, NULL), (3, {'a': NULL, 'b': 'y'}); SELECT s.a, t.s.b FROM t ORDER BY id; SELECT s.a + 1, (s).a, s['a'] FROM t ORDER BY id")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│  NULL │ NULL    │
│  NULL │ y       │
└───────┴─────────┘
┌───────────┬───────┬────────┐
│ (s.a + 1) │ (s).a │ s['a'] │
│   int32   │ int32 │ int32  │
├───────────┼───────┼────────┤
│         2 │     1 │      1 │
│      NULL │  NULL │   NULL │
│      NULL │  NULL │   NULL │
└───────────┴───────┴────────┘
```

### in WHERE, GROUP BY, HAVING and ORDER BY

```x
(sql "CREATE OR REPLACE TABLE t (id INT, s STRUCT(a INT, b VARCHAR)); INSERT INTO t VALUES (1, {'a': 1, 'b': 'x'}), (2, NULL), (3, {'a': NULL, 'b': 'y'}); SELECT id FROM t WHERE s.a = 1; SELECT s.b, count(*) FROM t GROUP BY s.b ORDER BY s.b; SELECT id FROM t ORDER BY s.b DESC, id; SELECT s.a AS k FROM t WHERE t.s.b = 'x'")
```
---
```output
┌───────┐
│  id   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌─────────┬──────────────┐
│    b    │ count_star() │
│ varchar │    int64     │
├─────────┼──────────────┤
│ x       │            1 │
│ y       │            1 │
│ NULL    │            1 │
└─────────┴──────────────┘
┌───────┐
│  id   │
│ int32 │
├───────┤
│     3 │
│     1 │
│     2 │
└───────┘
┌───────┐
│   k   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

### fields of fields, and of the elements of a list

```x
(sql "SELECT x[1], x[2].a FROM (SELECT [{'a': 1}, {'a': 2}] AS x); SELECT s.l[2], s.t.u FROM (SELECT {'l': [7, 8], 't': {'u': 'v'}} AS s)")
```
---
```output
┌───────────────────┬──────────┐
│       x[1]        │ (x[2]).a │
│ struct(a integer) │  int32   │
├───────────────────┼──────────┤
│ {'a': 1}          │        2 │
└───────────────────┴──────────┘
┌────────┬─────────┐
│ s.l[2] │    u    │
│ int32  │ varchar │
├────────┼─────────┤
│      8 │ v       │
└────────┴─────────┘
```

## struct comparison

### structs compare field by field; a NULL inside is after every value

```x
(sql "SELECT {'a': 1, 'b': 2} = {'a': 1, 'b': 2}, {'a': 1, 'b': 2} < {'a': 1, 'b': 3}, {'a': 1, 'b': NULL} = {'a': 1, 'b': NULL}, {'a': NULL} IS NULL, {'a': 1, 'b': NULL} > {'a': 1, 'b': 2}")
```
---
```output
┌─────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────┬──────────────────────────────────┬────────────────────────────────────────────────────────────────┐
│ (struct_pack(a := 1, b := 2) = struct_pack(a := 1, b := 2)) │ (struct_pack(a := 1, b := 2) < struct_pack(a := 1, b := 3)) │ (struct_pack(a := 1, b := NULL) = struct_pack(a := 1, b := NULL)) │ (struct_pack(a := NULL) IS NULL) │ (struct_pack(a := 1, b := NULL) > struct_pack(a := 1, b := 2)) │
│                           boolean                           │                           boolean                           │                              boolean                              │             boolean              │                            boolean                             │
├─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ true                                                        │ true                                                        │ true                                                              │ false                            │ true                                                           │
└─────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────┴──────────────────────────────────┴────────────────────────────────────────────────────────────────┘
```

## struct columns

### a column of structs: STRUCT(name type, ...)

```x
(sql "CREATE OR REPLACE TABLE t (id INT, s STRUCT(a INT, b VARCHAR)); INSERT INTO t VALUES (1, {'a': 1, 'b': 'x'}), (2, NULL), (3, {'a': NULL, 'b': 'y'}); SELECT * FROM t ORDER BY id; SELECT typeof(s) FROM t LIMIT 1")
```
---
```output
┌───────┬──────────────────────────────┐
│  id   │              s               │
│ int32 │ struct(a integer, b varchar) │
├───────┼──────────────────────────────┤
│     1 │ {'a': 1, 'b': x}             │
│     2 │ NULL                         │
│     3 │ {'a': NULL, 'b': y}          │
└───────┴──────────────────────────────┘
┌──────────────────────────────┐
│          typeof(s)           │
│           varchar            │
├──────────────────────────────┤
│ STRUCT(a INTEGER, b VARCHAR) │
└──────────────────────────────┘
```

### what goes in is fitted by name: a field not given is NULL, and one the column has not is left out

```x
(sql "CREATE OR REPLACE TABLE t (s STRUCT(a INT, b VARCHAR)); INSERT INTO t VALUES ({'b': 'x', 'a': 1}), ({'a': 1}), ({'a': 2, 'c': 'x'}), ({'a': '5', 'b': 7}); SELECT * FROM t")
```
---
```output
┌──────────────────────────────┐
│              s               │
│ struct(a integer, b varchar) │
├──────────────────────────────┤
│ {'a': 1, 'b': x}             │
│ {'a': 1, 'b': NULL}          │
│ {'a': 2, 'b': NULL}          │
│ {'a': 5, 'b': 7}             │
└──────────────────────────────┘
```

### casts by name

```x
(sql "SELECT {'a': 1, 'b': 2}::STRUCT(b INT, a INT), {'a': 1, 'b': 2}::STRUCT(a INT), CAST({'a': 1} AS STRUCT(a VARCHAR)), {'a': 1}::VARCHAR")
```
---
```output
┌───────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────┬────────────────────────────────────────────────┬──────────────────────────────────────┐
│ CAST(struct_pack(a := 1, b := 2) AS STRUCT(b INTEGER, a INTEGER)) │ CAST(struct_pack(a := 1, b := 2) AS STRUCT(a INTEGER)) │ CAST(struct_pack(a := 1) AS STRUCT(a VARCHAR)) │ CAST(struct_pack(a := 1) AS VARCHAR) │
│                   struct(b integer, a integer)                    │                   struct(a integer)                    │               struct(a varchar)                │               varchar                │
├───────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────┼────────────────────────────────────────────────┼──────────────────────────────────────┤
│ {'b': 2, 'a': 1}                                                  │ {'a': 1}                                               │ {'a': 1}                                       │ {'a': 1}                             │
└───────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────┴────────────────────────────────────────────────┴──────────────────────────────────────┘
```

### sorted and grouped as structs; UNION takes the type both sides go into

```x
(sql "CREATE OR REPLACE TABLE t (id INT, s STRUCT(a INT, b VARCHAR)); INSERT INTO t VALUES (1, {'a': 1, 'b': 'x'}), (2, NULL), (3, {'a': NULL, 'b': 'y'}); SELECT s FROM t ORDER BY s DESC NULLS LAST; SELECT s, count(*) FROM t GROUP BY s ORDER BY s; SELECT {'a': 1} UNION ALL SELECT {'a': 2.5}")
```
---
```output
┌──────────────────────────────┐
│              s               │
│ struct(a integer, b varchar) │
├──────────────────────────────┤
│ {'a': NULL, 'b': y}          │
│ {'a': 1, 'b': x}             │
│ NULL                         │
└──────────────────────────────┘
┌──────────────────────────────┬──────────────┐
│              s               │ count_star() │
│ struct(a integer, b varchar) │    int64     │
├──────────────────────────────┼──────────────┤
│ {'a': 1, 'b': x}             │            1 │
│ {'a': NULL, 'b': y}          │            1 │
│ NULL                         │            1 │
└──────────────────────────────┴──────────────┘
┌─────────────────────────┐
│   struct_pack(a := 1)   │
│ struct(a decimal(11,1)) │
├─────────────────────────┤
│ {'a': 1.0}              │
│ {'a': 2.5}              │
└─────────────────────────┘
```

### a struct of lists in a table

```x
(sql "CREATE OR REPLACE TABLE t (s STRUCT(n VARCHAR, tags VARCHAR[])); INSERT INTO t VALUES ({'n': 'x', 'tags': ['a', 'b']}), ({'n': 'y', 'tags': []}); SELECT s.n, s.tags[1], len(s.tags) FROM t ORDER BY 1")
```
---
```output
┌─────────┬───────────┬─────────────┐
│    n    │ s.tags[1] │ len(s.tags) │
│ varchar │  varchar  │    int64    │
├─────────┼───────────┼─────────────┤
│ x       │ a         │           2 │
│ y       │ NULL      │           0 │
└─────────┴───────────┴─────────────┘
```

## struct errors

### a field the struct has not

```x
(sql "SELECT ({'a': 1}).z")
```
---
```output
Binder Error: Could not find key "z" in struct
```

### in brackets

```x
(sql "SELECT ({'a': 1})['z']")
```
---
```output
Binder Error: Could not find key "z" in struct
```

### of a column

```x
(sql "CREATE OR REPLACE TABLE t (id INT, s STRUCT(a INT, b VARCHAR)); INSERT INTO t VALUES (1, {'a': 1, 'b': 'x'}), (2, NULL), (3, {'a': NULL, 'b': 'y'}); SELECT s.z FROM t")
```
---
```output
Binder Error: Could not find key "z" in struct
```

### a cast with no field in common

```x
(sql "SELECT {'a': 1}::STRUCT(b INT)")
```
---
```output
Binder Error: STRUCT to STRUCT cast must have at least one matching member, inputs are (STRUCT(a INTEGER)) and (STRUCT(b INTEGER))
```

### a struct made a number

```x
(sql "SELECT {'a': 1}::INT")
```
---
```output
Conversion Error: Unimplemented type for cast (STRUCT(a INTEGER) -> INTEGER)
```

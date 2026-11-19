The lists and objects of a JSON file, read as lists and structs, and
lists and structs written to one.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## json lists

### an array is a list and an object a struct, its fields in the order the file first has them

```x
(sql-files "FROM '{F}orders.json'")
```
---
```output
┌───────┬─────────────┬──────────────────────────────────────────────────┬────────────┬───────────────┬────────────┬──────────────────────────────────────────────────────────────────────────────┬──────────────┐
│  id   │    tags     │                      buyer                       │   prices   │     grid      │    day     │                                    lines                                     │     days     │
│ int64 │  varchar[]  │ struct("name" varchar, age bigint, city varchar) │  double[]  │   int64[][]   │    date    │                struct(sku varchar, n bigint, note varchar)[]                 │    date[]    │
├───────┼─────────────┼──────────────────────────────────────────────────┼────────────┼───────────────┼────────────┼──────────────────────────────────────────────────────────────────────────────┼──────────────┤
│     1 │ [new, gift] │ {'name': Ann, 'age': 30, 'city': NULL}           │ [1.0, 2.5] │ [[1], [2, 3]] │ 2026-01-31 │ NULL                                                                         │ NULL         │
│     2 │ []          │ {'name': Bob, 'age': 41, 'city': Oslo}           │ []         │ []            │ 2026-02-01 │ NULL                                                                         │ NULL         │
│     3 │ NULL        │ NULL                                             │ [3.0]      │ NULL          │ NULL       │ NULL                                                                         │ NULL         │
│     4 │ NULL        │ {'name': NULL, 'age': NULL, 'city': NULL}        │ NULL       │ NULL          │ NULL       │ [{'sku': a1, 'n': 2, 'note': NULL}, {'sku': NULL, 'n': 1, 'note': last one}] │ [2026-01-31] │
└───────┴─────────────┴──────────────────────────────────────────────────┴────────────┴───────────────┴────────────┴──────────────────────────────────────────────────────────────────────────────┴──────────────┘
```

### a struct's field no object has here is NULL; a list is of the type its elements all go into

```x
(sql-files "SELECT id, typeof(tags), typeof(buyer), typeof(prices), typeof(grid), typeof(lines) FROM '{F}orders.json' WHERE id = 4")
```
---
```output
┌───────┬──────────────┬──────────────────────────────────────────────────┬────────────────┬──────────────┬───────────────────────────────────────────────┐
│  id   │ typeof(tags) │                  typeof(buyer)                   │ typeof(prices) │ typeof(grid) │                 typeof(lines)                 │
│ int64 │   varchar    │                     varchar                      │    varchar     │   varchar    │                    varchar                    │
├───────┼──────────────┼──────────────────────────────────────────────────┼────────────────┼──────────────┼───────────────────────────────────────────────┤
│     4 │ VARCHAR[]    │ STRUCT("name" VARCHAR, age BIGINT, city VARCHAR) │ DOUBLE[]       │ BIGINT[][]   │ STRUCT(sku VARCHAR, n BIGINT, note VARCHAR)[] │
└───────┴──────────────┴──────────────────────────────────────────────────┴────────────────┴──────────────┴───────────────────────────────────────────────┘
```

### places, fields and functions over what was read

```x
(sql-files "SELECT id, tags[1], buyer.name, buyer.city, len(prices), list_sum(prices), grid[2][1], lines[2].note FROM '{F}orders.json' ORDER BY id")
```
---
```output
┌───────┬─────────┬─────────┬─────────┬─────────────┬──────────────────┬────────────┬─────────────────┐
│  id   │ tags[1] │  name   │  city   │ len(prices) │ list_sum(prices) │ grid[2][1] │ (lines[2]).note │
│ int64 │ varchar │ varchar │ varchar │    int64    │      double      │   int64    │     varchar     │
├───────┼─────────┼─────────┼─────────┼─────────────┼──────────────────┼────────────┼─────────────────┤
│     1 │ new     │ Ann     │ NULL    │           2 │              3.5 │          2 │ NULL            │
│     2 │ NULL    │ Bob     │ Oslo    │           0 │             NULL │       NULL │ NULL            │
│     3 │ NULL    │ NULL    │ NULL    │           1 │              3.0 │       NULL │ NULL            │
│     4 │ NULL    │ NULL    │ NULL    │        NULL │             NULL │       NULL │ last one        │
└───────┴─────────┴─────────┴─────────┴─────────────┴──────────────────┴────────────┴─────────────────┘
```

### in WHERE and GROUP BY

```x
(sql-files "SELECT id FROM '{F}orders.json' WHERE list_contains(tags, 'gift') OR buyer.age > 40 ORDER BY id; SELECT buyer.name IS NULL, count(*) FROM '{F}orders.json' GROUP BY ALL ORDER BY 1")
```
---
```output
┌───────┐
│  id   │
│ int64 │
├───────┤
│     1 │
│     2 │
└───────┘
┌────────────────────────┬──────────────┐
│ (buyer."name" IS NULL) │ count_star() │
│        boolean         │    int64     │
├────────────────────────┼──────────────┤
│ false                  │            2 │
│ true                   │            2 │
└────────────────────────┴──────────────┘
```

### a date is found among strings, inside a list too

```x
(sql-files "SELECT typeof(day), typeof(days) FROM '{F}orders.json' LIMIT 1")
```
---
```output
┌───────────────┬────────────────┐
│ typeof("day") │ typeof("days") │
│    varchar    │    varchar     │
├───────────────┼────────────────┤
│ DATE          │ DATE[]         │
└───────────────┴────────────────┘
```

### one object alone

```x
(sql-files "FROM '{F}nested.json'; SELECT b.c, d[2] FROM '{F}nested.json'")
```
---
```output
┌───────┬──────────────────┬─────────┐
│   a   │        b         │    d    │
│ int64 │ struct(c bigint) │ int64[] │
├───────┼──────────────────┼─────────┤
│     1 │ {'c': 2}         │ [1, 2]  │
└───────┴──────────────────┴─────────┘
┌───────┬───────┐
│   c   │ d[2]  │
│ int64 │ int64 │
├───────┼───────┤
│     2 │     2 │
└───────┴───────┘
```

### a whole number too wide for a BIGINT is a DOUBLE

```x
(sql-files "SELECT c, typeof(c) FROM '{F}mixed.ndjson'")
```
---
```output
┌────────────────────────┬───────────┐
│           c            │ typeof(c) │
│         double         │  varchar  │
├────────────────────────┼───────────┤
│ 1.8446744073709552e+19 │ DOUBLE    │
│                    1.0 │ DOUBLE    │
└────────────────────────┴───────────┘
```

### a table made from a file keeps the types

```x
(sql-files "CREATE OR REPLACE TABLE o AS FROM '{F}orders.json'; SELECT id, buyer, tags FROM o WHERE buyer.name = 'Ann'")
```
---
```output
┌───────┬──────────────────────────────────────────────────┬─────────────┐
│  id   │                      buyer                       │    tags     │
│ int64 │ struct("name" varchar, age bigint, city varchar) │  varchar[]  │
├───────┼──────────────────────────────────────────────────┼─────────────┤
│     1 │ {'name': Ann, 'age': 30, 'city': NULL}           │ [new, gift] │
└───────┴──────────────────────────────────────────────────┴─────────────┘
```

## json mixed

### values that are not all a list, all an object or all scalars are text: each as JSON

DuckDB has a JSON type for these, and a MAP for an object with no key; here they are VARCHAR, holding the same text.

```x
(sql-files "SELECT a, b, d, typeof(a), typeof(b), typeof(d) FROM '{F}mixed.ndjson'")
```
---
```output
┌─────────┬─────────┬─────────┬───────────┬───────────┬───────────┐
│    a    │    b    │    d    │ typeof(a) │ typeof(b) │ typeof(d) │
│ varchar │ varchar │ varchar │  varchar  │  varchar  │  varchar  │
├─────────┼─────────┼─────────┼───────────┼───────────┼───────────┤
│ {"p":1} │ [1,2]   │ {}      │ VARCHAR   │ VARCHAR   │ VARCHAR   │
│ 5       │ "x"     │ {}      │ VARCHAR   │ VARCHAR   │ VARCHAR   │
└─────────┴─────────┴─────────┴───────────┴───────────┴───────────┘
```

## json written

### a list is written as an array and a struct as an object

```x
(%seq (sql-files "COPY (SELECT 1 AS a, [1, 2] AS l, {'x': 'q\"r', 'y': [NULL, 1.5], 'z': DATE '2026-01-01'} AS s, ['a', NULL] AS t, NULL::INT[] AS n, [] AS e, [{'k': true}] AS ls) TO '{S}36-a.json'") (display (File read-all (Str8 append sql-scratch "36-a.json"))))
```
---
```output
{"a":1,"l":[1,2],"s":{"x":"q\"r","y":[null,1.5],"z":"2026-01-01"},"t":["a",null],"n":null,"e":[],"ls":[{"k":true}]}
```

### and read back as it was

```x
(sql-files "COPY (SELECT [1, 2] AS l, {'x': 'q', 'y': [NULL, 1.5]} AS s, [{'k': true}, {'k': false}] AS ls) TO '{S}36-b.json'; FROM '{S}36-b.json'")
```
---
```output
┌─────────┬───────────────────────────────┬─────────────────────────────┐
│    l    │               s               │             ls              │
│ int64[] │ struct(x varchar, y double[]) │     struct(k boolean)[]     │
├─────────┼───────────────────────────────┼─────────────────────────────┤
│ [1, 2]  │ {'x': q, 'y': [NULL, 1.5]}    │ [{'k': true}, {'k': false}] │
└─────────┴───────────────────────────────┴─────────────────────────────┘
```

### a file to a file

```x
(sql-files "COPY (SELECT id, buyer, tags FROM '{F}orders.json' WHERE id < 3) TO '{S}36-c.json'; FROM '{S}36-c.json'")
```
---
```output
┌───────┬──────────────────────────────────────────────────┬─────────────┐
│  id   │                      buyer                       │    tags     │
│ int64 │ struct("name" varchar, age bigint, city varchar) │  varchar[]  │
├───────┼──────────────────────────────────────────────────┼─────────────┤
│     1 │ {'name': Ann, 'age': 30, 'city': NULL}           │ [new, gift] │
│     2 │ {'name': Bob, 'age': 41, 'city': Oslo}           │ []          │
└───────┴──────────────────────────────────────────────────┴─────────────┘
```

## json errors

### text that is not JSON

DuckDB's error names the file and the place.

```x
(sql-files "FROM '{F}broken.json'")
```
---
```output
Invalid Input Error: Malformed JSON
```

The colour a value has in a result's box (`sql/render.x`): the class of
the theme its type is drawn as, where colour is on.  Nothing here is
coloured, the suite's output being no terminal; the cases read the
classes the colours come from.

## result colours

### a number of any kind is a number

```x
(write (List map sql-value-class (list (lit integer) (lit ubigint) (lit double) (list (lit decimal) 4 1))))
```
---
    ('number 'number 'number 'number)

### a truth is the constant it is written as

```x
(write (sql-value-class (lit boolean)))
```
---
    'constant

### text, and what a statement writes in quotes, is a string

```x
(write (List map sql-value-class (list (lit varchar) (lit date) (lit timestamp) (lit interval))))
```
---
    ('string 'string 'string 'string)

### a list, a struct and a NULL of no type have no colour

```x
(write (List map sql-value-class (list (list (lit list) (lit integer)) (list (lit struct) (list "a" (lit integer))) (lit null))))
```
---
    (() () ())

### with colour off a box is DuckDB's bytes

```x
(sql "SELECT 1 AS a, 'x' AS b, true AS c, NULL::INT AS d")
```
---
```output
┌───────┬─────────┬─────────┬───────┐
│   a   │    b    │    c    │   d   │
│ int32 │ varchar │ boolean │ int32 │
├───────┼─────────┼─────────┼───────┤
│     1 │ x       │ true    │  NULL │
└───────┴─────────┴─────────┴───────┘
```

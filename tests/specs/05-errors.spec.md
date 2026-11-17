What is refused, and how it is said.  The first line is DuckDB's where it
has one; its second, the statement with a caret under the place, is not
built.

## errors parser

### no selection list

```x
(sql "SELECT")
```
---
```output
Parser Error: SELECT clause without selection list
```

### two expressions with nothing between them

```x
(sql "SELECT 1 2")
```
---
```output
Parser Error: syntax error at or near "2"
```

### a byte that starts no token

```x
(sql "SELECT @")
```
---
```output
Parser Error: syntax error at or near "@"
```

### a string left open

```x
(sql "SELECT 'abc")
```
---
```output
Parser Error: unterminated string literal
```

### a statement that is not built

```x
(sql "UPDATE t SET a = 1")
```
---
```output
Parser Error: syntax error at or near "UPDATE"
```

### an expression that stops short

DuckDB names the last token it read, "+".

```x
(sql "SELECT 1 +")
```
---
```output
Parser Error: syntax error at end of input
```

### a parenthesis left open

DuckDB names "1".

```x
(sql "SELECT (1")
```
---
```output
Parser Error: syntax error at end of input
```

## errors binder

### a column with no FROM

```x
(sql "SELECT a")
```
---
```output
Binder Error: Referenced column "a" was not found because the FROM clause is missing
```

## errors not built

### GROUP BY

```x
(sql "SELECT 1 GROUP BY 1")
```
---
```output
Not implemented Error: GROUP
```

### DISTINCT

```x
(sql "SELECT DISTINCT 1")
```
---
```output
Not implemented Error: DISTINCT
```

### a comparison across types

DuckDB reads the string as an integer and answers true.

```x
(sql "SELECT 1 = '1'")
```
---
```output
Not implemented Error: comparing INTEGER with VARCHAR
```

### the caret line under a parser error

```x
(sql "SELECT 1 2")
```

# A session opened on a SQLite file
# @weight 3

`x -l sql -- file.db` and `.open file.db` open the session on a SQLite
file (`lib/sql/base.x`, `lib/sql/exec.x`): the file is attached under its
own name, and its tables are read by their bare names as well. The file is
read, never written.

This is x-sql's own: DuckDB's shell opens a DuckDB file this way, not a
SQLite one.

## the operand

### a path names a file, with or without sqlite:// or sqlite3:// before it

```x
(import sql/base sql-operand-file sql-open!)
(write (List map sql-operand-file
         (list "shop.sqlite3" "data/shop.db" "sqlite://shop.db" "sqlite3://data/shop.db")))
```
---
    ("shop.sqlite3" "data/shop.db" "shop.db" "data/shop.db")

### a server's URL, an option and an empty operand name none

```x
(write (List map sql-operand-file (list "postgres://me@host/shop" "-c" "")))
```
---
    (() () ())

## opened

### opening answers the name the file is attached under

```x
(write (sql-open! (Str8 append sql-fixtures "shop.sqlite3")))
```
---
    "shop"

### a table of the file is read by its bare name

```x
(sql "SELECT name FROM customers ORDER BY id LIMIT 2")
```
---
```output
┌─────────┐
│  name   │
│ varchar │
├─────────┤
│ Ida     │
│ Bo      │
└─────────┘
```

### and by the file's name before it

```x
(sql "SELECT count(*) AS n FROM shop.orders")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│     4 │
└───────┘
```

### a join reads two of its tables

```x
(sql "SELECT count(*) AS n FROM orders o JOIN customers c ON o.customer_id = c.id")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│     4 │
└───────┘
```

### a table made in the session with the same name is read first

```x
(sql "CREATE OR REPLACE TABLE customers AS SELECT 'here' AS name; SELECT name FROM customers; DROP TABLE customers")
```
---
```output
┌─────────┐
│  name   │
│ varchar │
├─────────┤
│ here    │
└─────────┘
```

### a name the file has no table for is refused as any other

```x
(sql "SELECT * FROM nope")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

### DETACH by the file's name lets it go

```x
(sql "DETACH shop; SELECT name FROM customers")
```
---
```output
Catalog Error: Table with name customers does not exist!
```

### a file that is not there is refused

```x
(write (guard (e (Str8 str e)) (sql-open! "nope.sqlite3")))
```
---
    "Invalid Error: Unable to open database \"nope.sqlite3\": unable to open database file"

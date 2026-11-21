A SQLite file attached under a name (`lib/sql/exec.x`, `lib/sql/sqlite.x`):
`ATTACH 'file' AS name`, its tables then `name.table`, and `DETACH name`.
The session of a spec file is one, so each case lets go of the name it
attaches before it attaches it.

Expected output is DuckDB 2.0.0's own with its sqlite extension, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## attached

### ATTACH names a SQLite file, and its tables are read as name.table

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop (TYPE sqlite); SELECT name FROM shop.customers ORDER BY id LIMIT 2")
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

### TYPE need not be said, nor DATABASE left out, and READ_ONLY is what it is

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH DATABASE '{F}shop.sqlite3' AS shop (READ_ONLY); SELECT count(*) AS n FROM shop.orders")
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

### with no AS the name is the file's own, without its directories and its ending

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3'; SELECT count(*) AS n FROM shop.orders")
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

### a table's columns are under its name, or its alias

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT orders.id FROM shop.orders ORDER BY 1 LIMIT 1; SELECT o.id, o.note FROM shop.orders AS o WHERE o.id = 12")
```
---
```output
┌───────┐
│  id   │
│ int64 │
├───────┤
│    10 │
└───────┘
┌───────┬─────────┐
│  id   │  note   │
│ int64 │ varchar │
├───────┼─────────┤
│    12 │ gift    │
└───────┴─────────┘
```

### main is the schema a file's tables are in

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT count(*) AS n FROM shop.main.orders")
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

### attached tables joined to each other, and to a table of the session

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; CREATE OR REPLACE TABLE vips (id INT); INSERT INTO vips VALUES (1), (5); SELECT c.name, count(*) AS orders FROM shop.customers c JOIN shop.orders o ON o.customer_id = c.id JOIN vips v ON v.id = c.id GROUP BY ALL ORDER BY 1")
```
---
```output
┌───────────┬────────┐
│   name    │ orders │
│  varchar  │ int64  │
├───────────┼────────┤
│ Ida       │      2 │
│ Åsa Öberg │      1 │
└───────────┴────────┘
```

### a name in any case

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT count(*) AS n FROM SHOP.Customers")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│     5 │
└───────┘
```

### IF NOT EXISTS leaves a name that is attached as it is

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; ATTACH IF NOT EXISTS '{F}shop.sqlite3' AS shop; SELECT count(*) AS n FROM shop.customers")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│     5 │
└───────┘
```

### DETACH lets a name go, and IF EXISTS one that is not there

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; DETACH shop; DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT count(*) AS n FROM shop.customers")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│     5 │
└───────┘
```

### a table made WITHOUT ROWID

DuckDB reads such a table with sqlite_scan and not when the file is attached; the output here is its sqlite_scan's.

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT sku, title FROM shop.products ORDER BY sku")
```
---
```output
┌─────────┬─────────┐
│   sku   │  title  │
│ varchar │ varchar │
├─────────┼─────────┤
│ A-1     │ Anvil   │
│ B-2     │ Bellows │
│ C-3     │ Chisel  │
└─────────┴─────────┘
```

## attached at the prompt

### .tables lists an attached database's tables after the session's own, each database.table

```x
(%seq (sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; DROP TABLE IF EXISTS vips") (sql-eval-line ".tables"))
```
---
```output
shop.big_spenders
shop.customers
shop.documents
shop.loose
shop.measurements
shop.order_lines
shop.orders
shop.products
shop.shelves
```

### .schema database.table is its columns in the types they are read as

```x
(%seq (sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; DROP TABLE IF EXISTS vips") (sql-eval-line ".schema shop.customers"))
```
---
```output
CREATE TABLE shop.customers(id BIGINT, name VARCHAR, email VARCHAR, joined DATE, vip BIGINT, balance DOUBLE);
```

### a column DuckDB reads as a BLOB is shown as one, though its table is not read

```x
(%seq (sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; DROP TABLE IF EXISTS vips") (sql-eval-line ".schema shop.loose"))
```
---
```output
CREATE TABLE shop.loose(a BLOB, b BLOB);
```

## attached errors

### a name that is attached already

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; ATTACH '{F}shop.sqlite3' AS shop")
```
---
```output
Binder Error: Failed to attach database: database with name "shop" already exists
```

### a name that is not attached, detached

```x
(sql-files "DETACH DATABASE IF EXISTS shop; DETACH nope")
```
---
```output
Binder Error: Failed to detach database with name "nope": database not found
```

### a table of a database that was detached

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; DETACH shop; SELECT 1 FROM shop.orders")
```
---
```output
Catalog Error: Table with name "shop.orders" does not exist because schema "shop" does not exist.
```

### a table of a database that was never attached

```x
(sql-files "SELECT * FROM nope.orders")
```
---
```output
Catalog Error: Table with name "nope.orders" does not exist because schema "nope" does not exist.
```

### a table the database has not

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop; SELECT * FROM shop.nope")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

### a file that is not there

DuckDB makes a new, empty database of the name; x-sql reads SQLite files and does not write them.

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH 'nope.sqlite3' AS shop")
```
---
```output
Invalid Error: Unable to open database "nope.sqlite3": unable to open database file
```

### a file that is no SQLite file

DuckDB takes it for a database of its own.

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}people.csv' AS shop")
```
---
```output
Invalid Input Error: the file is not a SQLite database
```

### an option that is not built

```x
(sql-files "DETACH DATABASE IF EXISTS shop; ATTACH '{F}shop.sqlite3' AS shop (TYPE postgres)")
```
---
```output
Not implemented Error: the ATTACH option TYPE
```

Tables in memory: CREATE TABLE, INSERT and DROP TABLE.  A table lasts as
long as the process, so every case makes its own with CREATE OR REPLACE.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## tables create

### a new table has its columns and no rows

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); FROM t")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ boolean │
└───────┴─────────┴─────────┘
           0 rows          
```

### a lone narrow column is widened for the row count

```x
(sql "CREATE OR REPLACE TABLE t (a INT); FROM t")
```
---
```output
┌────────┐
│   a    │
│ int32  │
└────────┘
  0 rows
```

### the type names DuckDB takes for these types

```x
(sql "CREATE OR REPLACE TABLE t (b TEXT, c BIGINT, d BOOL, e HUGEINT, f STRING, g INT8, h INT4); FROM t")
```
---
```output
┌─────────┬───────┬─────────┬────────┬─────────┬───────┬───────┐
│    b    │   c   │    d    │   e    │    f    │   g   │   h   │
│ varchar │ int64 │ boolean │ int128 │ varchar │ int64 │ int32 │
└─────────┴───────┴─────────┴────────┴─────────┴───────┴───────┘
                             0 rows                           
```

### a name taken is an error

```x
(sql "CREATE OR REPLACE TABLE t (a INT); CREATE TABLE t (x INT)")
```
---
```output
Catalog Error: Table with name "t" already exists!
```

### unless IF NOT EXISTS, which leaves the table as it was

```x
(sql "CREATE OR REPLACE TABLE t (a INT); CREATE TABLE IF NOT EXISTS t (x VARCHAR); FROM t")
```
---
```output
┌────────┐
│   a    │
│ int32  │
└────────┘
  0 rows
```

### a table name matches in any case

```x
(sql "CREATE OR REPLACE TABLE Mixed (a INT); FROM MIXED; DROP TABLE mixed")
```
---
```output
┌────────┐
│   a    │
│ int32  │
└────────┘
  0 rows
```

### a column named twice

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, A VARCHAR)")
```
---
```output
Catalog Error: Column with name "a" already exists!
```

### a type that is not built

DuckDB makes the table.

```x
(sql "CREATE OR REPLACE TABLE t (a UUID)")
```
---
```output
Not implemented Error: the type UUID
```

### a constraint is not built

DuckDB makes the table.

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER PRIMARY KEY)")
```
---
```output
Not implemented Error: PRIMARY in a column definition
```

## tables insert

### rows go in in order, a NULL in any column

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (2, 'two', true), (1, 'one', false), (NULL, NULL, NULL), (3, 'three', NULL); FROM t")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ boolean │
├───────┼─────────┼─────────┤
│     2 │ two     │ true    │
│     1 │ one     │ false   │
│  NULL │ NULL    │ NULL    │
│     3 │ three   │ NULL    │
└───────┴─────────┴─────────┘
```

### named columns take the values and the rest are NULL

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t (b, a) VALUES ('x', 1); FROM t")
```
---
```output
┌───────┬─────────┬─────────┐
│   a   │    b    │    c    │
│ int32 │ varchar │ boolean │
├───────┼─────────┼─────────┤
│     1 │ x       │ NULL    │
└───────┴─────────┴─────────┘
```

### a value is cast to its column: a number to text, text to a number

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES ('7', 5), (' -3 ', true); FROM t")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int32 │ varchar │
├───────┼─────────┤
│     7 │ 5       │
│    -3 │ true    │
└───────┴─────────┘
```

### an INTEGER widens into a BIGINT column

```x
(sql "CREATE OR REPLACE TABLE t (a BIGINT); INSERT INTO t VALUES (1), (2147483648); FROM t")
```
---
```output
┌────────────┐
│     a      │
│   int64    │
├────────────┤
│          1 │
│ 2147483648 │
└────────────┘
```

### too few values

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t VALUES (1, 'a')")
```
---
```output
Binder Error: table "t" has 3 columns but 2 values were supplied
```

### too many for the columns named

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t (a) VALUES (1, 2)")
```
---
```output
Binder Error: Column name/value mismatch for insert on "t": expected 1 columns but 2 values were supplied
```

### a column the table does not have

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR, c BOOLEAN); INSERT INTO t (zz) VALUES (1)")
```
---
```output
Binder Error: Table "t" does not have a column with name "zz"
```

### text that is no number

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER); INSERT INTO t VALUES ('x')")
```
---
```output
Conversion Error: Could not convert string 'x' to INT32
```

### a number too wide for the column

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER); INSERT INTO t VALUES (2147483648)")
```
---
```output
Conversion Error: Type INT64 with value 2147483648 can't be cast because the value is out of range for the destination type INT32
```

### a statement that fails stores none of its rows

The first statement to fail ends a run, in DuckDB as here, so the table is
read by a second run.  The expectation is written by hand.

```x
(%seq (sql "CREATE OR REPLACE TABLE t (a INTEGER); INSERT INTO t VALUES (1), ('x')") (sql "FROM t"))
```
---
```output
Conversion Error: Could not convert string 'x' to INT32
┌────────┐
│   a    │
│ int32  │
└────────┘
  0 rows
```

### a table that is not there

```x
(sql "INSERT INTO nope VALUES (1)")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

## tables drop

### a dropped table is gone

```x
(sql "CREATE OR REPLACE TABLE t (a INT); DROP TABLE t; FROM t")
```
---
```output
Catalog Error: Table with name t does not exist!
```

### dropping what is not there is an error

```x
(sql "DROP TABLE nope")
```
---
```output
Catalog Error: Table with name nope does not exist!
```

### unless IF EXISTS

```x
(sql "DROP TABLE IF EXISTS nope; SELECT 'ok' AS still")
```
---
```output
┌─────────┐
│  still  │
│ varchar │
├─────────┤
│ ok      │
└─────────┘
```

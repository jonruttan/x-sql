What the prompt does with a line (`sql/repl.x`).  The line editor reads
the line and hands it to `sql-eval-line`; a statement that does not end on
its first line asks the editor for more, which no case here does.

## prompt lines

### a line ending in a semicolon is run

```x
(sql-eval-line "SELECT 1 AS a;")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

### a comment after the semicolon does not hold the statement open

```x
(sql-eval-line "SELECT 2 AS b; -- done")
```
---
```output
┌───────┐
│   b   │
│ int32 │
├───────┤
│     2 │
└───────┘
```

### an error is shown and the prompt goes on

```x
(%seq (sql-eval-line "SELECT 1 2;") (sql-eval-line "SELECT 3 AS c;"))
```
---
```output
Parser Error: syntax error at or near "2"
┌───────┐
│   c   │
│ int32 │
├───────┤
│     3 │
└───────┘
```

### a blank line is nothing

```x
(%seq (sql-eval-line "   ") (display "ok") (newline))
```
---
    ok

## prompt commands

### .help lists the topics

```x
(sql-eval-line ".help")
```
---
      prompt    The prompt's own commands, each on a line starting with a dot.

### .help TOPIC is one topic in full, in any case

```x
(sql-eval-line ".help DROP")
```
---
```output
drop: A table gone.
  DROP TABLE [IF EXISTS] name
For example:
  DROP TABLE IF EXISTS t;
```

### a topic there is not

```x
(sql-eval-line ".help nope")
```
---
    no help on nope; .help lists the topics

### a command it does not have is named

```x
(sql-eval-line ".nope")
```
---
    unknown command: .nope; try .help

### .schema is a table as the statement that would make it

```x
(%seq (sql-eval-line "CREATE OR REPLACE TABLE prices (item VARCHAR, price DECIMAL(8,2), n BIGINT);") (sql-eval-line ".schema prices"))
```
---
    CREATE TABLE prices(item VARCHAR, price DECIMAL(8,2), n BIGINT);

### .schema of a table there is not

```x
(sql-eval-line ".schema nope")
```
---
    Catalog Error: Table with name nope does not exist!

### .tables names the tables, in order

```x
(%seq (sql-eval-line "DROP TABLE IF EXISTS prices; CREATE OR REPLACE TABLE zebra (a INT); CREATE OR REPLACE TABLE ant (a INT);") (sql-eval-line ".tables"))
```
---
```output
ant
zebra
```

## prompt servers

### .connect refuses a URL of a server it has no driver for

```x
(sql-eval-line ".connect oracle://me@h/d")
```
---
    Connection Error: not a postgres://, mysql:// or mariadb:// URL, oracle://me@h/d

### .disconnect with no server is nothing, and statements still run here

```x
(%seq (sql-eval-line ".disconnect") (sql-eval-line "SELECT 1 AS here;"))
```
---
```output
┌───────┐
│ here  │
│ int32 │
├───────┤
│     1 │
└───────┘
```

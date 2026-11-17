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

### .help says what the prompt takes

```x
(sql-eval-line ".help")
```
---
```output
A statement ends with a semicolon and may span lines.
  .help    this text
  .quit    leave (.exit and ctrl-d do the same)
```

### a command it does not have is named

```x
(sql-eval-line ".tables")
```
---
    unknown command: .tables; try .help

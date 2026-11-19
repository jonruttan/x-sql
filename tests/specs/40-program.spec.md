A program: a file's lines run as `x -l sql -f FILE` runs them
(`sql-program` in `sql/repl.x`).  The cases hand the lines over from a
list; the entry hands them over from standard input, where x.sh puts the
file.  DuckDB's `-f` is the model: statements in order, and the first one
that fails ends the run.  Statements piped in are read the same way and
go on after a failure, which is the second argument.

## program

### statements run in order, and the answer is whether all of them ran

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a;" "SELECT 2 AS b;")) #t))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌───────┐
│   b   │
│ int32 │
├───────┤
│     2 │
└───────┘
#t
```

### a statement over several lines runs at its semicolon

```x
(write (sql-program (sql-lines (list "SELECT" "  3 AS c" ";")) #t))
```
---
```output
┌───────┐
│   c   │
│ int32 │
├───────┤
│     3 │
└───────┘
#t
```

### two statements on a line

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a; SELECT 2 AS b;")) #t))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌───────┐
│   b   │
│ int32 │
├───────┤
│     2 │
└───────┘
#t
```

### a statement opened on the line another closes

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a; SELECT" "2 AS b;")) #t))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌───────┐
│   b   │
│ int32 │
├───────┤
│     2 │
└───────┘
#t
```

### the last statement needs no semicolon

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a;" "SELECT 2 AS b")) #t))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌───────┐
│   b   │
│ int32 │
├───────┤
│     2 │
└───────┘
#t
```

### a semicolon in a string or a comment closes nothing

```x
(write (sql-program (sql-lines (list "SELECT 4 AS d -- one; two" "WHERE ';' = ';'" ";")) #t))
```
---
```output
┌───────┐
│   d   │
│ int32 │
├───────┤
│     4 │
└───────┘
#t
```

### the first statement to fail ends the program

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a;" "SELECT 1 2;" "SELECT 3 AS c;")) #t))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
Parser Error: syntax error at or near "2"
#f
```

### a statement that fails at the end of the lines

```x
(write (sql-program (sql-lines (list "SELECT 1 2")) #t))
```
---
```output
Parser Error: syntax error at or near "2"
#f
```

### a line starting with a dot is a command of the prompt's

```x
(write (sql-program (sql-lines (list "CREATE OR REPLACE TABLE prog (a INT);" ".schema prog" "SELECT 5 AS e;")) #t))
```
---
```output
CREATE TABLE prog(a INTEGER);
┌───────┐
│   e   │
│ int32 │
├───────┤
│     5 │
└───────┘
#t
```

### inside a statement a line starting with a dot is part of it

```x
(write (sql-program (sql-lines (list "CREATE OR REPLACE TABLE prog (a INT); INSERT INTO prog VALUES (6);" "SELECT prog" ".a AS f FROM prog;")) #t))
```
---
```output
┌───────┐
│   f   │
│ int32 │
├───────┤
│     6 │
└───────┘
#t
```

### a command after a comment is still a command

```x
(write (sql-program (sql-lines (list "-- the table" ".schema prog")) #t))
```
---
```output
CREATE TABLE prog(a INTEGER);
#t
```

### blank lines and comments alone are no statement

```x
(write (sql-program (sql-lines (list "" "-- nothing" "  ")) #t))
```
---
```output
#t
```

### no lines at all

```x
(write (sql-program (sql-lines (list )) #t))
```
---
```output
#t
```

### piped statements go on after one that fails, and the answer says one did

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a;" "SELECT 1 2;" "SELECT 3 AS c;")) #f))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
Parser Error: syntax error at or near "2"
┌───────┐
│   c   │
│ int32 │
├───────┤
│     3 │
└───────┘
#f
```

### a blank line between statements

```x
(write (sql-program (sql-lines (list "SELECT 1 AS a;" "" "SELECT 3 AS c;")) #t))
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
└───────┘
┌───────┐
│   c   │
│ int32 │
├───────┤
│     3 │
└───────┘
#t
```

What the prompt knows about a line besides what it means: its colours,
its brackets, and what Tab offers.  The harness has no terminal, so
nothing here is coloured; the cases read the classes the colours come
from.  The expectations are written by hand.

## colour grammar

`sql-spans` is the harness's: each span of the `sql` grammar
(`lib/sql/syntax.x`) as its class and its bytes.  A token with no class is
left out.

### keywords, a function, punctuation, operators, a number, a string and a comment

```x
(%seq (write (sql-spans "SELECT a, count(*) FROM t WHERE b >= 1.5 -- hi")) (newline))
```
---
    (('keyword "SELECT") ('punct ",") ('name "count") ('punct "(") ('operator "*") ('punct ")") ('keyword "FROM") ('keyword "WHERE") ('operator ">=") ('number "1.5") ('comment "-- hi"))

### a word is classed in any case: a type a class, TRUE, FALSE and NULL constants

```x
(%seq (write (sql-spans "select x::Integer, null, True from t")) (newline))
```
---
    (('keyword "select") ('operator "::") ('class "Integer") ('punct ",") ('constant "null") ('punct ",") ('constant "True") ('keyword "from"))

### the words the parser reads only in their place are keywords too

```x
(%seq (write (sql-spans "insert into t values (1) order by 1 desc")) (newline))
```
---
    (('keyword "insert") ('keyword "into") ('keyword "values") ('punct "(") ('number "1") ('punct ")") ('keyword "order") ('keyword "by") ('number "1") ('keyword "desc"))

### a quote written twice is two strings side by side

```x
(%seq (write (sql-spans "'it''s'")) (newline))
```
---
    (('string "'it'") ('string "'s'"))

### a string left open runs to the end, as a line being typed leaves it

```x
(%seq (write (sql-spans "select 'abc -- not a comment")) (newline))
```
---
    (('keyword "select") ('string "'abc -- not a comment"))

### and so does a block comment

```x
(%seq (write (sql-spans "select 1 /* open")) (newline))
```
---
    (('keyword "select") ('number "1") ('comment "/* open"))

### a quoted identifier is a name, whatever it spells

```x
(%seq (write (sql-spans "\"select\"")) (newline))
```
---
    (('name "\"select\""))

### a file ending .sql is the grammar's

```x
(%seq (write ((Syntax for-file "report.sql") name)) (newline))
```
---
    'sql

## colour painting

### with no terminal a line is painted as it is

```x
(let ((s "SELECT 'a' FROM t; -- c")) (%seq (write (Str8 =? (sql-paint s) s)) (newline)))
```
---
    #t

## colour brackets

`sql-marks` answers a mark for every bracket as (offset depth focused).

### a pair shares a depth, and an inner pair is one deeper

```x
(%seq (write (sql-marks "((1) + (2))" -1)) (newline))
```
---
    ((0 0 #f) (1 1 #f) (3 1 #f) (7 1 #f) (9 1 #f) (10 0 #f))

### the pair the cursor is just after, or on, is focused

```x
(%seq (write (sql-marks "(a (b))" 6)) (newline) (write (sql-marks "(a (b))" 0)) (newline))
```
---
```output
((0 0 #f) (3 1 #t) (5 1 #t) (6 0 #f))
((0 0 #t) (3 1 #f) (5 1 #f) (6 0 #t))
```

### a close with nothing to close is at depth -1, and an open left open keeps its depth

```x
(%seq (write (sql-marks ") (" -1)) (newline))
```
---
    ((0 -1 #f) (2 0 #f))

### a bracket in a string or a comment is no bracket

```x
(%seq (write (sql-marks "('(' /* ) */)" -1)) (newline))
```
---
    ((0 0 #f) (12 0 #f))

## colour completion

`sql-complete` answers the word before the cursor and what it could
become.  `SqlLine` is the harness's stand-in for the editor's buffer.

### a keyword completes in the case it is typed in

```x
(%seq (write (sql-complete (new SqlLine text "sel"))) (newline) (write (sql-complete (new SqlLine text "x WHE"))) (newline))
```
---
```output
("sel" "select")
("WHE" "WHEN" "WHERE")
```

### a type and a function complete

```x
(%seq (write (sql-complete (new SqlLine text "x::dec"))) (newline) (write (sql-complete (new SqlLine text "select cou"))) (newline))
```
---
```output
("dec" "decimal")
("cou" "count")
```

### a table and its columns complete, in any case

```x
(%seq (sql "CREATE OR REPLACE TABLE zebra (zstripes INT, zname VARCHAR)") (write (sql-complete (new SqlLine text "from Z"))) (newline))
```
---
    ("Z" "zebra" "zname" "zstripes")

### an empty word completes to nothing

```x
(%seq (write (sql-complete (new SqlLine text "select "))) (newline))
```
---
    ("")

### a line starting with a dot completes the prompt's commands

```x
(%seq (write (sql-complete (new SqlLine text ".s"))) (newline) (write (sql-complete (new SqlLine text "."))) (newline))
```
---
```output
(".s" ".schema")
("." ".connect" ".disconnect" ".exit" ".help" ".maxrows" ".quit" ".schema" ".tables")
```

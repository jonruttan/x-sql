Statement text to tokens (`lib/sql/lex.x`).  `sql-lex` keeps every byte, which
is what a painter colours; `sql-tokenize` is what the parser reads.

## lex raw

### every byte is in a token, blanks and comments included

```x
(%seq (write (sql-lex "SELECT 1 -- one\n")) (newline))
```
---
    (('id "SELECT") ('blank " ") ('num "1" 1) ('blank " ") ('comment "-- one") ('blank "\n"))

### blanks at the end of the text are a token like any other

```x
(%seq (write (sql-lex "SELECT 1;\n  ")) (newline))
```
---
    (('id "SELECT") ('blank " ") ('num "1" 1) ('op ";") ('blank "\n  "))

### a form feed is a blank, in the one run with the others

```x
(%seq (write (sql-lex (Str8 append "a" (Str8 append (Str8 make 1 (Char from-int 12)) " b")))) (newline))
```
---
    (('id "a") ('blank "\x0c ") ('id "b"))

### a word or a number that ends the text is a token

```x
(%seq (write (sql-lex "SELECT x1")) (write (sql-tokenize "SELECT 42")) (newline))
```
---
    (('id "SELECT") ('blank " ") ('id "x1"))(('kw "SELECT") ('num "42" 1))

### a quote written twice is inside the literal

```x
(%seq (write (sql-lex "'it''s'")) (newline))
```
---
    (('str "'it''s'"))

## lex tokens

### a reserved word is a keyword in any case, and blanks and comments are gone

```x
(%seq (write (sql-tokenize "select x /* c */ From t")) (newline))
```
---
    (('kw "SELECT") ('id "x") ('kw "FROM") ('id "t"))

### a string loses its quotes, and a quote written twice is one quote

```x
(%seq (write (sql-tokenize "'it''s' 'a' 'b'")) (newline))
```
---
    (('str "it's") ('str "a") ('str "b"))

### a blank or a comment between two literals keeps them apart

```x
(%seq (write (sql-tokenize "'a''' 'b'/* c */'c'--d")) (newline))
```
---
    (('str "a'") ('str "b") ('str "c"))

### a quoted identifier is never a keyword

```x
(%seq (write (sql-tokenize "\"select\" \"a\"\"b\"")) (newline))
```
---
    (('qid "select") ('qid "a\"b"))

### a number keeps its text and says what kind it is

```x
(%seq (write (sql-tokenize "42 1.5 1e3 0x1F")) (newline))
```
---
    (('num "42" 1) ('num "1.5" 2) ('num "1e3" 2) ('num "0x1F" 3))

### the longest operator present is the token

```x
(%seq (write (sql-tokenize "a<=b<>c||d::e//f")) (newline))
```
---
    (('id "a") ('op "<=") ('id "b") ('op "<>") ('id "c") ('op "||") ('id "d") ('op "::") ('id "e") ('op "//") ('id "f"))

Statement text to tokens (`sql/lex.x`).  `sql-lex` keeps every byte, which
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

; # x-sql -- SQL on x-lang
;
; ## lib/sql/syntax.x -- the SQL highlighting grammar
;
; @description The grammar x/tool/syntax colours SQL with: comments,
;   strings, numbers, keywords, types, the constants and the functions.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; bundle.xon's (grammar sql ...) form names this module, and x/tool/syntax
; imports it the first time a file needs the grammar, in whatever process
; is colouring.  So it imports x-lang libraries and sql/words only, never
; the interpreter.  The prompt paints a line with the same rules.
;
; These are not sql/lex's rules.  A string or a comment still open at the
; end of the text runs to it, as a line being typed leaves one, where the
; parser's lexer has an error to report.  A quote written twice inside a
; string is two strings side by side, coloured alike.
;
; A word is a constant when it is TRUE, FALSE or NULL, a keyword when the
; parser reads it as one, a class when it names a type, a name when it is a
; function, and plain otherwise, in any case.  A parenthesis, a comma, a
; semicolon or a point is punctuation, every other operator an operator.
; A string and a block comment span lines, so a text is read from its
; start.

(module sql/syntax)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import sql/words
  sql-lower sql-upper sql-reserved sql-words sql-constants sql-type-words sql-aggregates sql-window-functions sql-ops)

(def %sql-syntax-blanks (list 32 9 13 10 12))
(def %sql-syntax-name-start (list (pair 97 122) (pair 65 90) 95))
(def %sql-syntax-name-rest (list (pair 97 122) (pair 65 90) (pair 48 57) 95 36))

(def sql-syntax-rules
  (fn (_)
    (list (Lexer run (lit blank) %sql-syntax-blanks %sql-syntax-blanks)
          (Lexer until (lit comment) "--" "\n" (lit to-end))
          (Lexer until (lit comment) "/*" "*/" (lit to-end))
          (Lexer until (lit string) "'" "'" (lit take) (lit to-end))
          (Lexer until (lit quoted) "\"" "\"" (lit take) (lit to-end))
          (Lexer run (lit name) %sql-syntax-name-start %sql-syntax-name-rest)
          (Lexer number (lit number) ())
          (Lexer table (lit op) sql-ops)
          (Lexer any (lit plain)))))

(def %sql-syntax-name-class
  (fn (_ text)
    (let ((upper (sql-upper text)))
      (match
        ((List includes? upper sql-constants) (lit constant))
        ((List includes? upper sql-reserved) (lit keyword))
        ((List includes? upper sql-words) (lit keyword))
        ((List any? (fn (_ row) (str=? (first row) upper)) sql-type-words)
          (lit class))
        ((List includes? (sql-lower text) sql-aggregates) (lit name))
        ((List includes? (sql-lower text) sql-window-functions) (lit name))
        (#t ())))))

(def %sql-syntax-punct (list "(" ")" "," ";" "." "[" "]" "{" "}"))

(def %sql-syntax-op-class
  (fn (_ text)
    (if (List includes? text %sql-syntax-punct) (lit punct) (lit operator))))

; Each token's tag and its class, or the function of its text that answers
; one
(def sql-syntax-classes
  (fn (_)
    (list (pair (lit comment) (lit comment))
          (pair (lit string) (lit string))
          (pair (lit quoted) (lit name))
          (pair (lit number) (lit number))
          (pair (lit name) %sql-syntax-name-class)
          (pair (lit op) %sql-syntax-op-class))))

(Syntax register!
  (let ((g (Syntax make (lit sql) (sql-syntax-rules) (sql-syntax-classes))))
    (g files (list ".sql"))
    g))

(provide sql/syntax sql-syntax-rules sql-syntax-classes)

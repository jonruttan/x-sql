; # x-sql -- SQL on x-lang
;
; ## sql/words.x -- the words the reader and the parser share
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A reserved word is a keyword wherever it stands, in any case, and is an
; identifier only inside double quotes.  Every other word is an identifier
; the parser may read as a keyword where the grammar asks for one.

(module sql/words)

(def sql-reserved
  (list "SELECT" "FROM" "WHERE" "AS" "AND" "OR" "NOT" "IS" "NULL" "TRUE"
        "FALSE" "GROUP" "ORDER" "HAVING" "LIMIT" "OFFSET" "UNION" "EXCEPT"
        "INTERSECT" "ON" "USING" "JOIN" "CASE" "WHEN" "THEN" "ELSE" "END"
        "IN" "DISTINCT" "ALL" "CREATE" "TABLE" "INTO" "WITH"))

; Longest first where one operator starts another: the Lexer's table takes
; the longest literal present.
(def sql-ops
  (list "(" ")" "," ";" "." "+" "-" "*" "/" "//" "%" "||" "=" "==" "<>"
        "!=" "<" "<=" ">" ">=" "::" "[" "]" "{" "}" ":" "**" "^"))

; A binary operator as written, the name the evaluator knows it by, and how
; a column heading spells it.
(def sql-binary-ops
  (list (list "+" (lit add) "+") (list "-" (lit sub) "-")
        (list "*" (lit mul) "*") (list "/" (lit div) "/")
        (list "//" (lit idiv) "//") (list "%" (lit mod) "%")
        (list "||" (lit concat) "||")
        (list "=" (lit eq) "=") (list "==" (lit eq) "=")
        (list "<>" (lit ne) "!=") (list "!=" (lit ne) "!=")
        (list "<" (lit lt) "<") (list "<=" (lit le) "<=")
        (list ">" (lit gt) ">") (list ">=" (lit ge) ">=")))

(provide sql/words sql-reserved sql-ops sql-binary-ops)

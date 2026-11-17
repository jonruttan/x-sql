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
(import x/type/str)
(import x/type/dict)

; A name in one case, each distinct spelling folded once: the platform's
; case conversion costs thousands of objects a word, and a name is
; compared for every column of every row
(def %sql-lowered (Dict make))
(def %sql-uppered (Dict make))

(def sql-lower
  (fn (_ text)
    (unless (%sql-lowered has? text) (%sql-lowered set! text (Str8 downcase text)))
    (%sql-lowered get text)))

(def sql-upper
  (fn (_ text)
    (unless (%sql-uppered has? text) (%sql-uppered set! text (Str8 upcase text)))
    (%sql-uppered get text)))

; Two names are one, whatever their case
(def sql-same-name?
  (fn (_ a b) (str=? (sql-lower a) (sql-lower b))))

(def sql-reserved
  (list "SELECT" "FROM" "WHERE" "AS" "AND" "OR" "NOT" "IS" "NULL" "TRUE"
        "FALSE" "GROUP" "ORDER" "HAVING" "LIMIT" "OFFSET" "UNION" "EXCEPT"
        "INTERSECT" "ON" "USING" "JOIN" "CASE" "WHEN" "THEN" "ELSE" "END"
        "IN" "DISTINCT" "ALL" "CREATE" "TABLE" "INTO" "WITH" "INNER" "LEFT"
        "RIGHT" "FULL" "CROSS" "OUTER" "NATURAL" "BETWEEN" "LIKE" "ILIKE"))

; The words the parser reads where the grammar asks for them and that are
; names everywhere else
(def sql-words
  (list "INSERT" "VALUES" "DROP" "BY" "ASC" "DESC" "NULLS" "FIRST" "LAST"
        "CAST" "REPLACE" "IF" "EXISTS" "UPDATE" "SET" "DELETE" "COPY" "TO"
        "FORMAT" "HEADER" "INTERVAL" "EXTRACT"))

; The functions that read a file as a table, and the format each reads it
; as: nil for the one its name's ending says
(def sql-file-functions
  (list (list "read_csv" "csv") (list "read_csv_auto" "csv")
        (list "read_json" "json") (list "read_json_auto" "json")
        (list "read_ndjson" "json")))

; The reserved words that are values
(def sql-constants (list "TRUE" "FALSE" "NULL"))

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

; A type as written, upper case, the type it names, and how a heading
; spells it: nil for as it was written, which is how DuckDB heads a name
; its grammar does not know as a keyword.  DECIMAL and NUMERIC name a type
; only with their width and scale, which the parser reads.
(def sql-type-words
  (list (list "INTEGER" (lit integer) "INTEGER") (list "INT" (lit integer) "INTEGER")
        (list "INT4" (lit integer) ()) (list "SIGNED" (lit integer) ())
        (list "BIGINT" (lit bigint) "BIGINT") (list "INT8" (lit bigint) ())
        (list "LONG" (lit bigint) ())
        (list "HUGEINT" (lit hugeint) ())
        (list "VARCHAR" (lit varchar) "VARCHAR") (list "CHAR" (lit varchar) "VARCHAR")
        (list "TEXT" (lit varchar) ()) (list "STRING" (lit varchar) ())
        (list "BPCHAR" (lit varchar) ())
        (list "BOOLEAN" (lit boolean) "BOOLEAN") (list "BOOL" (lit boolean) ())
        (list "LOGICAL" (lit boolean) ())
        (list "DOUBLE" (lit double) ()) (list "FLOAT8" (lit double) ())
        (list "DECIMAL" (lit decimal) "DECIMAL") (list "NUMERIC" (lit decimal) "DECIMAL")
        (list "DATE" (lit date) "DATE") (list "TIME" (lit time) "TIME")
        (list "TIMESTAMP" (lit timestamp) "TIMESTAMP") (list "DATETIME" (lit timestamp) ())
        (list "INTERVAL" (lit interval) "INTERVAL")))

; The functions that answer one value for a group of rows
(def sql-aggregates (list "count" "sum" "min" "max" "avg"))

(provide sql/words
  sql-lower sql-upper sql-same-name? sql-reserved sql-words sql-constants sql-ops sql-binary-ops sql-type-words
  sql-aggregates sql-file-functions)

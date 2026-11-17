; # x-sql -- SQL on x-lang
;
; ## sql/parse.x -- tokens to statements
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Recursive descent over sql/lex's tokens.  Every reader takes the tokens
; left and answers (tree . tokens-left).  Lowest to highest, the levels of
; an expression are OR, AND, NOT, comparison and IS, ||, + and -, * / // and
; %, and a sign.
;
; A statement, its head the name sql/exec's SqlStatement knows it by:
;   (select ITEMS FROM WHERE ORDER LIMIT OFFSET)
;       ITEMS   a list of (EXPR ALIAS), ALIAS nil or text; EXPR may be
;               (star QUALIFIER), every column, or every column of one table
;       FROM    nil, or (TABLE ALIAS)
;       WHERE   nil or an expression
;       ORDER   a list of (EXPR DESCENDING NULLS), NULLS nil, first or last
;       LIMIT, OFFSET   nil or an expression
;   (create TABLE COLUMNS REPLACE IF-NOT-EXISTS)   COLUMNS a list of (NAME TYPE)
;   (insert TABLE NAMES ROWS)   NAMES nil or the columns named; ROWS a list
;                               of lists of expressions
;   (drop TABLE IF-EXISTS)
;
; An expression, its head the name sql/eval's classes know it by:
;   (int N)  (str TEXT)  (bool B)  (null)  (col NAME QUALIFIER)
;   (neg E)  (not E)  (is-null E NEGATED)
;   (and A B)  (or A B)
;   (bin OP A B)            OP a name from sql/words' sql-binary-ops

(module sql/parse)
(import x/type/list)
(import x/type/str)
(import sql/words sql-binary-ops sql-type-words)
(import sql/lex sql-tokenize)

(def %sql-near
  (fn (_ ts)
    (error
      (if (null? ts) "Parser Error: syntax error at end of input"
        (Str8 str "Parser Error: syntax error at or near \""
                  (List second (first ts)) "\"")))))

; The first token of TS has TAG and TEXT
(def %sql-at?
  (fn (_ ts tag text)
    (if (null? ts) #f
      (if (eq? (first (first ts)) tag)
        (str=? (List second (first ts)) text)
        #f))))
(def %sql-op? (fn (_ ts text) (%sql-at? ts (lit op) text)))
(def %sql-kw? (fn (_ ts text) (%sql-at? ts (lit kw) text)))

; The first token of TS is WORD, reserved or not, in any case
(def %sql-word?
  (fn (_ ts word)
    (if (null? ts) #f
      (if (or (eq? (first (first ts)) (lit kw)) (eq? (first (first ts)) (lit id)))
        (str=? (Str8 upcase (List second (first ts))) word)
        #f))))

; TS after the words WORDS, or nil when it does not start with them
(def %sql-after
  (fn (self ts words)
    (match
      ((null? words) (pair ts ()))
      ((%sql-word? ts (first words)) (self (rest ts) (rest words)))
      (#t ()))))

; The first token of TS is an operator among OPS
(def %sql-op-in?
  (fn (_ ts ops)
    (if (null? ts) #f
      (if (eq? (first (first ts)) (lit op))
        (List includes? (List second (first ts)) ops)
        #f))))

(def %sql-name?
  (fn (_ ts)
    (if (null? ts) #f
      (or (eq? (first (first ts)) (lit id))
          (eq? (first (first ts)) (lit qid))))))

; The evaluator's name for a binary operator as written
(def %sql-op-name
  (fn (_ text)
    (List second (List find (fn (_ row) (str=? (first row) text)) sql-binary-ops))))

(def %sql-digits
  (fn (self text i n acc)
    (if (>= i n) acc
      (self text (+ i 1) n
            (+ (* acc 10) (- (Char ->int (Str8 ref i text)) 48))))))

(def %sql-primary
  (fn (_ ts)
    (if (null? ts) (%sql-near ts)
      (let ((tok (first ts)))
        (let ((tag (first tok)) (text (List second tok)))
          (match
            ((eq? tag (lit num))
              (if (= (List third tok) 1)
                (pair (list (lit int) (%sql-digits text 0 (Str8 length text) 0))
                      (rest ts))
                (error (Str8 str "Not implemented Error: the number " text
                                 ": only integers are read"))))
            ((eq? tag (lit str)) (pair (list (lit str) text) (rest ts)))
            ((%sql-kw? ts "NULL") (pair (list (lit null)) (rest ts)))
            ((%sql-kw? ts "TRUE") (pair (list (lit bool) #t) (rest ts)))
            ((%sql-kw? ts "FALSE") (pair (list (lit bool) #f) (rest ts)))
            ((%sql-op? ts "(")
              (let ((e (%sql-expr (rest ts))))
                (if (%sql-op? (rest e) ")")
                  (pair (first e) (rest (rest e)))
                  (%sql-near (rest e)))))
            ((%sql-name? ts)
              (if (and (%sql-op? (rest ts) ".") (%sql-name? (rest (rest ts))))
                (pair (list (lit col) (List second (List third ts)) text)
                      (rest (rest (rest ts))))
                (pair (list (lit col) text ()) (rest ts))))
            (#t (%sql-near ts))))))))

; A sign.  A minus on an integer constant is the constant, so the least
; INTEGER is one.
(def %sql-unary
  (fn (self ts)
    (match
      ((%sql-op? ts "-")
        (let ((r (self (rest ts))))
          (pair (if (eq? (first (first r)) (lit int))
                  (list (lit int) (- 0 (List second (first r))))
                  (list (lit neg) (first r)))
                (rest r))))
      ((%sql-op? ts "+") (self (rest ts)))
      (#t (%sql-primary ts)))))

; Operands NEXT reads, joined left to right by the operators OPS
(def %sql-binary
  (fn (_ next ops ts)
    (let ((l (next ts)))
      ((fn (self left ts)
         (if (%sql-op-in? ts ops)
           (let ((r (next (rest ts))))
             (self (list (lit bin) (%sql-op-name (List second (first ts)))
                         left (first r))
                   (rest r)))
           (pair left ts)))
       (first l) (rest l)))))

(def %sql-mul (fn (_ ts) (%sql-binary %sql-unary (list "*" "/" "//" "%") ts)))
(def %sql-add (fn (_ ts) (%sql-binary %sql-mul (list "+" "-") ts)))
(def %sql-concat (fn (_ ts) (%sql-binary %sql-add (list "||") ts)))

(def %sql-compare-ops (list "=" "==" "<>" "!=" "<" "<=" ">" ">="))

(def %sql-compare
  (fn (_ ts)
    (let ((l (%sql-concat ts)))
      ((fn (self left ts)
         (match
           ((%sql-op-in? ts %sql-compare-ops)
             (let ((r (%sql-concat (rest ts))))
               (self (list (lit bin) (%sql-op-name (List second (first ts)))
                           left (first r))
                     (rest r))))
           ((%sql-kw? ts "IS")
             (let ((negated (%sql-kw? (rest ts) "NOT")))
               (let ((after (if negated (rest (rest ts)) (rest ts))))
                 (if (%sql-kw? after "NULL")
                   (self (list (lit is-null) left negated) (rest after))
                   (%sql-near after)))))
           (#t (pair left ts))))
       (first l) (rest l)))))

(def %sql-not
  (fn (self ts)
    (if (%sql-kw? ts "NOT")
      (let ((r (self (rest ts))))
        (pair (list (lit not) (first r)) (rest r)))
      (%sql-compare ts))))

; Operands NEXT reads, joined left to right by the keyword WORD into HEAD
; nodes
(def %sql-logical
  (fn (_ next word head ts)
    (let ((l (next ts)))
      ((fn (self left ts)
         (if (%sql-kw? ts word)
           (let ((r (next (rest ts))))
             (self (list head left (first r)) (rest r)))
           (pair left ts)))
       (first l) (rest l)))))

(def %sql-and (fn (_ ts) (%sql-logical %sql-not "AND" (lit and) ts)))
(def %sql-expr (fn (_ ts) (%sql-logical %sql-and "OR" (lit or) ts)))

; An expression and its alias: after AS, or a bare name
(def %sql-item
  (fn (_ ts)
    (match
      ((%sql-op? ts "*") (pair (list (list (lit star) ()) ()) (rest ts)))
      ((and (%sql-name? ts) (%sql-op? (rest ts) ".")
            (%sql-op? (rest (rest ts)) "*"))
        (pair (list (list (lit star) (List second (first ts))) ())
              (rest (rest (rest ts)))))
      (#t (%sql-aliased ts)))))

(def %sql-aliased
  (fn (_ ts)
    (let ((e (%sql-expr ts)))
      (match
        ((%sql-kw? (rest e) "AS")
          (let ((after (rest (rest e))))
            (if (%sql-name? after)
              (pair (list (first e) (List second (first after))) (rest after))
              (%sql-near after))))
        ((%sql-name? (rest e))
          (pair (list (first e) (List second (first (rest e))))
                (rest (rest e))))
        (#t (pair (list (first e) ()) (rest e)))))))

; The clauses a SELECT takes that are not read yet
(def %sql-unread
  (list "GROUP" "HAVING" "UNION" "EXCEPT" "INTERSECT" "JOIN" "ON" "USING"
        "DISTINCT" "WITH"))

(def %sql-refuse-unread
  (fn (_ ts)
    (when (if (null? ts) #f
            (if (eq? (first (first ts)) (lit kw))
              (List includes? (List second (first ts)) %sql-unread)
              #f))
      (error (Str8 str "Not implemented Error: " (List second (first ts)))))))

(def %sql-name
  (fn (_ ts)
    (if (%sql-name? ts) (List second (first ts)) (%sql-near ts))))

; What follows FROM: a table and its alias, after AS or bare
(def %sql-from
  (fn (_ ts)
    (let ((table (%sql-name ts)) (after (rest ts)))
      (match
        ((%sql-kw? after "AS")
          (pair (list table (%sql-name (rest after))) (rest (rest after))))
        ((%sql-name? after)
          (pair (list table (List second (first after))) (rest after)))
        (#t (pair (list table ()) after))))))

; One ORDER BY term: an expression, ASC or DESC, NULLS FIRST or LAST
(def %sql-order-term
  (fn (_ ts)
    (let ((e (%sql-expr ts)))
      (let ((descending (%sql-word? (rest e) "DESC")))
        (let ((after (if (or descending (%sql-word? (rest e) "ASC"))
                       (rest (rest e)) (rest e))))
          (match
            ((not (null? (%sql-after after (list "NULLS" "FIRST"))))
              (pair (list (first e) descending (lit first)) (rest (rest after))))
            ((not (null? (%sql-after after (list "NULLS" "LAST"))))
              (pair (list (first e) descending (lit last)) (rest (rest after))))
            (#t (pair (list (first e) descending ()) after))))))))

; READ's results from TS, one after each comma
(def %sql-list
  (fn (self read ts)
    (let ((i (read ts)))
      (if (%sql-op? (rest i) ",")
        (let ((more (self read (rest (rest i)))))
          (pair (pair (first i) (first more)) (rest more)))
        (pair (list (first i)) (rest i))))))

; The clauses after the table: WHERE, ORDER BY, LIMIT and OFFSET, each nil
; when absent, as (WHERE ORDER LIMIT OFFSET)
(def %sql-tail
  (fn (_ ts)
    (let ((where (if (%sql-kw? ts "WHERE") (%sql-expr (rest ts)) (pair () ts))))
      (let ((by (%sql-after (rest where) (list "ORDER" "BY"))))
        (let ((order (if (null? by) (pair () (rest where))
                       (%sql-list %sql-order-term (first by)))))
          (let ((limit (if (%sql-kw? (rest order) "LIMIT")
                         (%sql-expr (rest (rest order)))
                         (pair () (rest order)))))
            (let ((offset (if (%sql-kw? (rest limit) "OFFSET")
                            (%sql-expr (rest (rest limit)))
                            (pair () (rest limit)))))
              (%sql-refuse-unread (rest offset))
              (pair (list (first where) (first order) (first limit) (first offset))
                    (rest offset)))))))))

(def %sql-select-node
  (fn (_ items from tail)
    (pair (lit select) (pair items (pair from tail)))))

; SELECT items [FROM table] and the clauses after
(def %sql-select
  (fn (_ ts)
    (when (or (null? ts) (%sql-op? ts ";"))
      (error "Parser Error: SELECT clause without selection list"))
    (%sql-refuse-unread ts)
    (let ((is (%sql-list %sql-item ts)))
      (let ((from (if (%sql-kw? (rest is) "FROM") (%sql-from (rest (rest is)))
                    (pair () (rest is)))))
        (let ((tail (%sql-tail (rest from))))
          (pair (%sql-select-node (first is) (first from) (first tail))
                (rest tail)))))))

; FROM table [SELECT items] and the clauses after: DuckDB's order
(def %sql-from-first
  (fn (_ ts)
    (let ((from (%sql-from ts)))
      (let ((is (if (%sql-kw? (rest from) "SELECT")
                  (%sql-list %sql-item (rest (rest from)))
                  (pair (list (list (list (lit star) ()) ())) (rest from)))))
        (let ((tail (%sql-tail (rest is))))
          (pair (%sql-select-node (first is) (first from) (first tail))
                (rest tail)))))))

; A column of CREATE TABLE: its name and its type
(def %sql-column
  (fn (_ ts)
    (let ((name (%sql-name ts)) (after (rest ts)))
      (when (null? after) (%sql-near after))
      (let ((row (List find
                   (fn (_ r) (str=? (first r) (Str8 upcase (List second (first after)))))
                   sql-type-words)))
        (when (null? row)
          (error (Str8 str "Not implemented Error: the type "
                           (List second (first after)))))
        (unless (or (%sql-op? (rest after) ",") (%sql-op? (rest after) ")"))
          (if (null? (rest after)) (%sql-near (rest after))
            (error (Str8 str "Not implemented Error: "
                             (List second (first (rest after)))
                             " in a column definition"))))
        (pair (list name (List second row)) (rest after))))))

; A list READ reads, in parentheses
(def %sql-parenthesized
  (fn (_ read ts)
    (if (%sql-op? ts "(")
      (let ((l (%sql-list read (rest ts))))
        (if (%sql-op? (rest l) ")") (pair (first l) (rest (rest l)))
          (%sql-near (rest l))))
      (%sql-near ts))))

; CREATE [OR REPLACE] TABLE [IF NOT EXISTS] name (columns)
(def %sql-create
  (fn (_ ts)
    (let ((replace (%sql-after ts (list "OR" "REPLACE"))))
      (let ((after (if (null? replace) ts (first replace))))
        (if (%sql-kw? after "TABLE")
          (let ((guarded (%sql-after (rest after) (list "IF" "NOT" "EXISTS"))))
            (let ((at (if (null? guarded) (rest after) (first guarded))))
              (let ((columns (%sql-parenthesized %sql-column (rest at))))
                (pair (list (lit create) (%sql-name at) (first columns)
                            (not (null? replace)) (not (null? guarded)))
                      (rest columns)))))
          (%sql-near after))))))

(def %sql-name-read
  (fn (_ ts) (pair (%sql-name ts) (rest ts))))

; INSERT INTO name [(columns)] VALUES (expressions), ...
(def %sql-insert
  (fn (_ ts)
    (if (%sql-kw? ts "INTO")
      (let ((table (%sql-name (rest ts))) (after (rest (rest ts))))
        (let ((names (if (%sql-op? after "(")
                       (%sql-parenthesized %sql-name-read after)
                       (pair () after))))
          (if (%sql-word? (rest names) "VALUES")
            (let ((rows (%sql-list
                          (fn (_ ts) (%sql-parenthesized %sql-expr ts))
                          (rest (rest names)))))
              (pair (list (lit insert) table (first names) (first rows))
                    (rest rows)))
            (if (%sql-kw? (rest names) "SELECT")
              (error "Not implemented Error: INSERT from a SELECT")
              (%sql-near (rest names))))))
      (%sql-near ts))))

; DROP TABLE [IF EXISTS] name
(def %sql-drop
  (fn (_ ts)
    (if (%sql-kw? ts "TABLE")
      (let ((guarded (%sql-after (rest ts) (list "IF" "EXISTS"))))
        (let ((at (if (null? guarded) (rest ts) (first guarded))))
          (pair (list (lit drop) (%sql-name at) (not (null? guarded)))
                (rest at))))
      (%sql-near ts))))

(def %sql-statement
  (fn (_ ts)
    (match
      ((%sql-kw? ts "SELECT") (%sql-select (rest ts)))
      ((%sql-kw? ts "FROM") (%sql-from-first (rest ts)))
      ((%sql-kw? ts "CREATE") (%sql-create (rest ts)))
      ((%sql-word? ts "INSERT") (%sql-insert (rest ts)))
      ((%sql-word? ts "DROP") (%sql-drop (rest ts)))
      (#t (%sql-near ts)))))

(def %sql-statements
  (fn (self ts)
    (match
      ((null? ts) ())
      ((%sql-op? ts ";") (self (rest ts)))
      (#t
        (let ((s (%sql-statement ts)))
          (if (or (null? (rest s)) (%sql-op? (rest s) ";"))
            (pair (first s) (self (rest s)))
            (%sql-near (rest s))))))))

(def sql-parse (fn (_ text) (%sql-statements (sql-tokenize text))))

(provide sql/parse sql-parse)

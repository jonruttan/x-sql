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
;   (select ITEMS FROM WHERE ORDER LIMIT OFFSET GROUP HAVING DISTINCT)
;       ITEMS   a list of (EXPR ALIAS), ALIAS nil or text; EXPR may be
;               (star QUALIFIER), every column, or every column of one table
;       FROM    nil, or a list: (TABLE ALIAS) first, then a
;               (KIND TABLE ALIAS ON USING) for each table joined to what
;               is before it, KIND inner, left, right, full or cross, ON
;               nil or an expression, and USING nil, the columns of a
;               USING, or the name natural
;       WHERE, HAVING   nil or an expression
;       ORDER   a list of (EXPR DESCENDING NULLS), NULLS nil, first or last
;       LIMIT, OFFSET   nil or an expression
;       GROUP   nil, the name all, or a list of expressions
;       DISTINCT   whether rows that repeat are dropped
;   (create TABLE COLUMNS REPLACE IF-NOT-EXISTS)   COLUMNS a list of
;       (NAME TYPE), or a select statement, whose result the table is
;   (insert TABLE NAMES ROWS)   NAMES nil or the columns named; ROWS a list
;                               of lists of expressions, or a select
;                               statement
;   (update TABLE SETS WHERE)   SETS a list of (COLUMN EXPR)
;   (delete TABLE WHERE)
;   (with TABLES SELECT)        TABLES a list of (NAME SELECT): each a table
;                               for the ones after it and for SELECT
;   (set OP ALL LEFT RIGHT)     OP union, intersect or except, of two select
;                               statements; ALL whether rows that repeat
;                               are kept.  An ORDER BY, LIMIT or OFFSET
;                               after the last statement is the whole's:
;                               the set is then the one table of a SELECT *
;                               that has them.
;   (drop TABLE IF-EXISTS)
;
; A table of a FROM is a name, a select statement in parentheses, or a
; file, (file PATH FORMAT): a string, or a call of a function that reads
; one, FORMAT then the format it reads, nil for a string.
;
;   (copy-to SOURCE PATH FORMAT HEADER)   SOURCE a table's name or a select
;                                         statement; FORMAT a name or nil
;   (copy-from TABLE PATH FORMAT)
;
; An expression, its head the name sql/eval's classes know it by:
;   (int N)  (str TEXT)  (bool B)  (null)
;   (col NAME QUALIFIER LOW-NAME LOW-QUALIFIER)   the names as written and
;                                   in lower case; QUALIFIER nil or a table
;   (dec SCALED WIDTH SCALE TEXT)   a number with a point: SCALED its digits
;                                   as an integer, TEXT as it was written
;   (dbl TEXT)                      a number with an exponent, as written
;   (cast E TYPE SHOWN)             SHOWN the type as a heading spells it;
;                                   a type before a string, DATE '2026-11-17',
;                                   is a cast of the string
;   (to-interval E UNIT)            INTERVAL E UNIT: E of the unit, an interval
;   (case WHENS ELSE)               WHENS a list of (CONDITION RESULT), ELSE
;                                   nil or an expression; CASE x WHEN v is
;                                   read as CASE WHEN x = v
;   (in E LIST)  (between E LOW HIGH)
;   (like E PATTERN NEGATED ANY-CASE)
;   NOT IN and NOT BETWEEN are a (not ...) around these
;   (subquery SELECT)               a select statement in parentheses, for
;                                   its one value
;   (in-query E SELECT)             E IN (select statement)
;   (exists SELECT)
;   (call NAME ARGS DISTINCT)   ARGS expressions, or one (star ()) in count(*)
;   (neg E)  (not E)  (is-null E NEGATED)
;   (and A B)  (or A B)
;   (bin OP A B)            OP a name from sql/words' sql-binary-ops

(module sql/parse)
(import x/type/list)
(import x/type/str)
(import sql/words
  sql-upper sql-lower sql-binary-ops sql-type-words sql-file-functions)
(import sql/lex sql-tokenize)
(import sql/number sql-decimal-read)

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
        (str=? (sql-upper (List second (first ts))) word)
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

; A col node: sql/eval's sql-column-node, made here so that this module
; reads nothing of the evaluator's
(def %sql-col
  (fn (_ name qualifier)
    (list (lit col) name qualifier (sql-lower name)
          (if (null? qualifier) () (sql-lower qualifier)))))

; The functions written with no parentheses
(def %sql-bare-calls (list "current_date" "current_timestamp"))

(def %sql-type-word?
  (fn (_ text)
    (List any? (fn (_ r) (str=? (first r) (sql-upper text))) sql-type-words)))

; The most digits a DECIMAL holds; a constant of more is a DOUBLE
(def %sql-decimal-width 38)

; A number as written, of the kind the lexer says: 1 an integer, 2 one
; with a point or an exponent, 3 hexadecimal
(def %sql-number
  (fn (_ text kind)
    (match
      ((= kind 1) (list (lit int) (%sql-digits text 0 (Str8 length text) 0)))
      ((= kind 2)
        (if (or (Str8 includes? "e" text) (Str8 includes? "E" text))
          (list (lit dbl) text)
          (let ((read (sql-decimal-read text)))
            (if (> (List second read) %sql-decimal-width) (list (lit dbl) text)
              (list (lit dec) (first read) (List second read) (List third read) text)))))
      (#t (error (Str8 str "Not implemented Error: the number " text))))))

; One WHEN of a CASE, TS after the word: (CONDITION RESULT), the condition
; a comparison with OPERAND when the CASE has one
(def %sql-when
  (fn (_ operand ts)
    (let ((condition (%sql-expr ts)))
      (if (%sql-kw? (rest condition) "THEN")
        (let ((result (%sql-expr (rest (rest condition)))))
          (pair (list (if (null? operand) (first condition)
                        (list (lit bin) (lit eq) operand (first condition)))
                      (first result))
                (rest result)))
        (%sql-near (rest condition))))))

; The WHENs of a CASE, then its ELSE and its END: ((WHENS ELSE) . tokens)
(def %sql-whens
  (fn (self operand ts)
    (match
      ((%sql-kw? ts "WHEN")
        (let ((one (%sql-when operand (rest ts))))
          (let ((more (self operand (rest one))))
            (pair (list (pair (first one) (first (first more))) (List second (first more)))
                  (rest more)))))
      ((%sql-kw? ts "ELSE")
        (let ((e (%sql-expr (rest ts))))
          (if (%sql-kw? (rest e) "END") (pair (list () (first e)) (rest (rest e)))
            (%sql-near (rest e)))))
      ((%sql-kw? ts "END") (pair (list () ()) (rest ts)))
      (#t (%sql-near ts)))))

; A CASE, TS after the word: an operand unless a WHEN comes first
(def %sql-case
  (fn (_ ts)
    (let ((operand (if (%sql-kw? ts "WHEN") (pair () ts) (%sql-expr ts))))
      (unless (%sql-kw? (rest operand) "WHEN") (%sql-near (rest operand)))
      (let ((whens (%sql-whens (first operand) (rest operand))))
        (pair (pair (lit case) (first whens)) (rest whens))))))

; A whole number in parentheses or two, as a list; nil and TS as it was
; when there is no parenthesis
(def %sql-type-arguments
  (fn (_ ts)
    (if (%sql-op? ts "(")
      (let ((l (%sql-list
                 (fn (_ ts)
                   (if (and (not (null? ts)) (eq? (first (first ts)) (lit num))
                            (= (List third (first ts)) 1))
                     (pair (%sql-digits (List second (first ts)) 0
                                        (Str8 length (List second (first ts))) 0)
                           (rest ts))
                     (%sql-near ts)))
                 (rest ts))))
        (if (%sql-op? (rest l) ")") (pair (first l) (rest (rest l)))
          (%sql-near (rest l))))
      (pair () ts))))

; DuckDB's DECIMAL with no width and scale
(def %sql-decimal-default (list 18 3))

; A type: ((TYPE SHOWN) . tokens-left).  A DECIMAL is (decimal WIDTH SCALE),
; the scale 0 when only a width is written.  A VARCHAR's length says
; nothing.  SHOWN is the name and what was in parentheses after it.
(def %sql-type
  (fn (_ ts)
    (when (null? ts) (%sql-near ts))
    (let ((row (List find
                 (fn (_ r) (str=? (first r) (sql-upper (List second (first ts)))))
                 sql-type-words))
          (args (%sql-type-arguments (rest ts))))
      (when (null? row)
        (error (Str8 str "Not implemented Error: the type " (List second (first ts)))))
      (let ((given (first args))
            (shown (Str8 append
                     (if (null? (List third row)) (List second (first ts)) (List third row))
                     (if (null? (first args)) ""
                       (Str8 append "("
                         (Str8 join ", " (List map (fn (_ n) (Str8 str n)) (first args)))
                         ")")))))
        (pair (list (if (eq? (List second row) (lit decimal))
                      (pair (lit decimal)
                        (match ((null? given) %sql-decimal-default)
                               ((null? (rest given)) (list (first given) 0))
                               (#t given)))
                      (List second row))
                    shown)
              (rest args))))))

; TS after an opening parenthesis: an expression and the parenthesis that
; closes it
(def %sql-closed-expr
  (fn (_ ts)
    (let ((e (%sql-expr ts)))
      (if (%sql-op? (rest e) ")") (pair (first e) (rest (rest e)))
        (%sql-near (rest e))))))

; A type before a string, DATE '2026-11-17': a cast of the string
(def %sql-typed-string
  (fn (_ ts)
    (let ((type (%sql-type (list (first ts)))))
      (pair (pair (lit cast) (pair (list (lit str) (List second (List second ts)))
                                   (first type)))
            (rest (rest ts))))))

; INTERVAL and a count, TS after the word: the unit follows
(def %sql-interval
  (fn (_ ts)
    (let ((e (%sql-postfix ts)))
      (if (%sql-name? (rest e))
        (pair (list (lit to-interval) (first e) (List second (first (rest e))))
              (rest (rest e)))
        (%sql-near (rest e))))))

; EXTRACT(part FROM value), TS at the part: date_part of the part's name
; in upper case, as DuckDB heads it
(def %sql-extract
  (fn (_ ts)
    (let ((e (%sql-closed-expr (rest (rest ts)))))
      (pair (list (lit call) "date_part"
                  (list (list (lit str) (sql-upper (List second (first ts)))) (first e))
                  #f)
            (rest e)))))

; CAST(value AS type), TS after the parenthesis
(def %sql-cast
  (fn (_ ts)
    (let ((e (%sql-expr ts)))
      (if (%sql-kw? (rest e) "AS")
        (let ((type (%sql-type (rest (rest e)))))
          (if (%sql-op? (rest type) ")")
            (pair (pair (lit cast) (pair (first e) (first type))) (rest (rest type)))
            (%sql-near (rest type))))
        (%sql-near (rest e))))))

; A select statement in parentheses, TS after the parenthesis, under HEAD:
; subquery or exists
(def %sql-subquery
  (fn (_ head ts)
    (let ((q (%sql-closed-query ts)))
      (pair (list head (first q)) (rest q)))))

; A name: a column, with its table before a point when it has one
(def %sql-column-name
  (fn (_ ts)
    (if (and (%sql-op? (rest ts) ".") (%sql-name? (rest (rest ts))))
      (pair (%sql-col (List second (List third ts)) (List second (first ts)))
            (rest (rest (rest ts))))
      (pair (%sql-col (List second (first ts)) ()) (rest ts)))))

; A form a word opens, when TS starts with one; nil when it does not
(def %sql-word-form
  (fn (_ ts)
    (let ((after (rest ts)) (text (List second (first ts))))
      (match
        ((%sql-kw? ts "CASE") (%sql-case after))
        ((not (eq? (first (first ts)) (lit id))) ())
        ((and (not (null? after)) (eq? (first (first after)) (lit str)) (%sql-type-word? text))
          (%sql-typed-string ts))
        ((and (%sql-word? ts "INTERVAL") (not (null? after))) (%sql-interval after))
        ((and (%sql-word? ts "EXTRACT") (%sql-op? after "(")
              (%sql-name? (rest after)) (%sql-kw? (List drop 3 ts) "FROM"))
          (%sql-extract (rest after)))
        ((and (%sql-word? ts "CAST") (%sql-op? after "(")) (%sql-cast (rest after)))
        ((and (%sql-word? ts "EXISTS") (%sql-op? after "(") (%sql-query? (rest after)))
          (%sql-subquery (lit exists) (rest after)))
        ((and (not (%sql-op? after "(")) (List includes? (sql-lower text) %sql-bare-calls))
          (pair (list (lit call) (sql-lower text) () #f) after))
        (#t ())))))

; A constant, when TS starts with one; nil when it does not
(def %sql-constant
  (fn (_ ts)
    (let ((tok (first ts)))
      (match
        ((eq? (first tok) (lit num))
          (pair (%sql-number (List second tok) (List third tok)) (rest ts)))
        ((eq? (first tok) (lit str)) (pair (list (lit str) (List second tok)) (rest ts)))
        ((%sql-kw? ts "NULL") (pair (list (lit null)) (rest ts)))
        ((%sql-kw? ts "TRUE") (pair (list (lit bool) #t) (rest ts)))
        ((%sql-kw? ts "FALSE") (pair (list (lit bool) #f) (rest ts)))
        (#t ())))))

; What an expression is made of: a constant, a form a word opens, what is
; in parentheses, a call, or a column
(def %sql-primary
  (fn (_ ts)
    (when (null? ts) (%sql-near ts))
    (let ((constant (%sql-constant ts)))
      (if (not (null? constant)) constant
        (let ((form (%sql-word-form ts)))
          (match
            ((not (null? form)) form)
            ((and (%sql-op? ts "(") (%sql-query? (rest ts)))
              (%sql-subquery (lit subquery) (rest ts)))
            ((%sql-op? ts "(") (%sql-closed-expr (rest ts)))
            ((and (or (eq? (first (first ts)) (lit id)) (%sql-kw? ts "LEFT") (%sql-kw? ts "RIGHT"))
                  (%sql-op? (rest ts) "("))
              (%sql-call (List second (first ts)) (rest (rest ts))))
            ((%sql-name? ts) (%sql-column-name ts))
            (#t (%sql-near ts))))))))

; A call's arguments, TS after its opening parenthesis: none, a star, or
; expressions, after DISTINCT or not
(def %sql-call
  (fn (_ name ts)
    (match
      ((%sql-op? ts ")") (pair (list (lit call) name () #f) (rest ts)))
      ((and (%sql-op? ts "*") (%sql-op? (rest ts) ")"))
        (pair (list (lit call) name (list (list (lit star) ())) #f)
              (rest (rest ts))))
      (#t
        (let ((distinct (%sql-kw? ts "DISTINCT")))
          (let ((args (%sql-list %sql-expr (if distinct (rest ts) ts))))
            (if (%sql-op? (rest args) ")")
              (pair (list (lit call) name (first args) distinct)
                    (rest (rest args)))
              (%sql-near (rest args)))))))))

; A primary and the casts written after it with ::
(def %sql-postfix
  (fn (_ ts)
    (let ((e (%sql-primary ts)))
      ((fn (self left ts)
         (if (%sql-op? ts "::")
           (let ((type (%sql-type (rest ts))))
             (self (pair (lit cast) (pair left (first type))) (rest type)))
           (pair left ts)))
       (first e) (rest e)))))

; A constant with a minus before it: the constant, so the least INTEGER is
; one and -1.5 is headed as written
(def %sql-negated
  (fn (_ e)
    (match
      ((eq? (first e) (lit int)) (list (lit int) (- 0 (List second e))))
      ((eq? (first e) (lit dec))
        (list (lit dec) (- 0 (List second e)) (List third e) (List ref 3 e)
              (Str8 append "-" (List ref 4 e))))
      ((eq? (first e) (lit dbl)) (list (lit dbl) (Str8 append "-" (List second e))))
      (#t (list (lit neg) e)))))

; A sign
(def %sql-unary
  (fn (self ts)
    (match
      ((%sql-op? ts "-")
        (let ((r (self (rest ts))))
          (pair (%sql-negated (first r)) (rest r))))
      ((%sql-op? ts "+") (self (rest ts)))
      (#t (%sql-postfix ts)))))

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

; The words that test a value against others, each of which NOT may come
; before
(def %sql-membership-words (list "IN" "BETWEEN" "LIKE" "ILIKE"))

(def %sql-membership?
  (fn (_ ts)
    (let ((at (if (%sql-kw? ts "NOT") (rest ts) ts)))
      (List any? (fn (_ word) (%sql-kw? at word)) %sql-membership-words))))

; LEFT [NOT] IN (list), [NOT] BETWEEN low AND high, or [NOT] LIKE pattern,
; TS at the NOT or the word
(def %sql-membership
  (fn (_ left ts)
    (let ((negated (%sql-kw? ts "NOT")))
      (let ((at (if negated (rest ts) ts)))
        (let ((wrap (fn (_ node) (if negated (list (lit not) node) node))))
          (match
            ((and (%sql-kw? at "IN") (%sql-op? (rest at) "(")
                  (%sql-query? (rest (rest at))))
              (let ((q (%sql-closed-query (rest (rest at)))))
                (pair (wrap (list (lit in-query) left (first q))) (rest q))))
            ((%sql-kw? at "IN")
              (let ((l (%sql-parenthesized %sql-expr (rest at))))
                (pair (wrap (list (lit in) left (first l))) (rest l))))
            ((%sql-kw? at "BETWEEN")
              (let ((low (%sql-concat (rest at))))
                (if (%sql-kw? (rest low) "AND")
                  (let ((high (%sql-concat (rest (rest low)))))
                    (pair (wrap (list (lit between) left (first low) (first high)))
                          (rest high)))
                  (%sql-near (rest low)))))
            (#t
              (let ((pattern (%sql-concat (rest at))))
                (pair (list (lit like) left (first pattern) negated (%sql-kw? at "ILIKE"))
                      (rest pattern))))))))))

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
           ((%sql-membership? ts)
             (let ((r (%sql-membership left ts)))
               (self (first r) (rest r))))
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
(def %sql-unread ())

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

; TS starts a select statement
(def %sql-query?
  (fn (_ ts) (or (%sql-kw? ts "SELECT") (%sql-kw? ts "FROM") (%sql-kw? ts "WITH"))))

; A select statement and the parenthesis that closes it, TS after the one
; that opened it
(def %sql-closed-query
  (fn (_ ts)
    (let ((q (%sql-query ts)))
      (if (%sql-op? (rest q) ")") (pair (first q) (rest (rest q)))
        (%sql-near (rest q))))))

; What a FROM names: a table, or a select statement in parentheses, as
; (TABLE . tokens-left)
(def %sql-table
  (fn (_ ts)
    (match
      ((and (%sql-op? ts "(") (%sql-query? (rest ts))) (%sql-closed-query (rest ts)))
      ((and (not (null? ts)) (eq? (first (first ts)) (lit str)))
        (pair (list (lit file) (List second (first ts)) ()) (rest ts)))
      ((%sql-file-call? ts)
        (pair (list (lit file) (List second (List third ts))
                    (List second (%sql-file-function (List second (first ts)))))
              (List drop 4 ts)))
      (#t (pair (%sql-name ts) (rest ts))))))

(def %sql-file-function
  (fn (_ name)
    (List find (fn (_ row) (str=? (first row) (sql-lower name))) sql-file-functions)))

; TS starts with a function that reads a file, a string in its parentheses
(def %sql-file-call?
  (fn (_ ts)
    (and (>= (List length ts) 4) (eq? (first (first ts)) (lit id))
         (not (null? (%sql-file-function (List second (first ts)))))
         (%sql-op? (rest ts) "(") (eq? (first (List third ts)) (lit str))
         (%sql-op? (List drop 3 ts) ")"))))

; A table and its alias, after AS or bare
(def %sql-source
  (fn (_ ts)
    (let ((named (%sql-table ts)))
      (%sql-aliased-source (first named) (rest named)))))

(def %sql-aliased-source
  (fn (_ table after)
    (match
      ((%sql-kw? after "AS")
        (pair (list table (%sql-name (rest after))) (rest (rest after))))
      ((%sql-name? after)
        (pair (list table (List second (first after))) (rest after)))
      (#t (pair (list table ()) after)))))

; The kind of join TS starts with and the tokens after its JOIN, or nil:
; JOIN alone is an inner one, and OUTER after LEFT, RIGHT or FULL says
; nothing more
(def %sql-join-kind
  (fn (_ ts)
    (let ((row (List find (fn (_ r) (%sql-kw? ts (first r)))
                 (list (list "INNER" (lit inner)) (list "LEFT" (lit left))
                       (list "RIGHT" (lit right)) (list "FULL" (lit full))
                       (list "CROSS" (lit cross))))))
      (let ((after (if (null? row) ts
                     (if (%sql-kw? (rest ts) "OUTER") (rest (rest ts)) (rest ts)))))
        (match
          ((%sql-kw? after "JOIN")
            (pair (if (null? row) (lit inner) (List second row)) (rest after)))
          ((null? row) ())
          (#t (%sql-near after)))))))

; What says which rows of a join are kept, TS after the table joined: ON
; and a condition, or USING and columns in parentheses, as
; ((ON USING) . tokens-left); both nil when TS starts with neither
(def %sql-join-test
  (fn (_ ts)
    (match
      ((%sql-kw? ts "ON")
        (let ((on (%sql-expr (rest ts))))
          (pair (list (first on) ()) (rest on))))
      ((%sql-kw? ts "USING")
        (let ((names (%sql-parenthesized %sql-name-read (rest ts))))
          (pair (list () (first names)) (rest names))))
      (#t (pair (list () ()) ts)))))

; The tables joined to the first, TS after it: each after a comma or a
; JOIN.  NATURAL before a JOIN joins on the columns the two sides share,
; and takes no ON or USING; a CROSS JOIN takes none either; any other
; takes one.
(def %sql-joins
  (fn (self ts)
    (if (%sql-op? ts ",")
      (let ((source (%sql-source (rest ts))))
        (let ((more (self (rest source))))
          (pair (pair (pair (lit cross) (List append (first source) (list () ())))
                      (first more))
                (rest more))))
      (let ((natural (%sql-kw? ts "NATURAL")))
        (let ((kind (%sql-join-kind (if natural (rest ts) ts))))
          (match
            ((and (null? kind) natural) (%sql-near (rest ts)))
            ((null? kind) (pair () ts))
            (#t
              (let ((source (%sql-source (rest kind))))
                (let ((test (if natural (pair (list () (lit natural)) (rest source))
                              (%sql-join-test (rest source)))))
                  (when (and (null? (first (first test))) (null? (List second (first test)))
                             (not (eq? (first kind) (lit cross))))
                    (%sql-near (rest test)))
                  (let ((more (self (rest test))))
                    (pair (pair (pair (first kind) (List append (first source) (first test)))
                                (first more))
                          (rest more))))))))))))

; What follows FROM: the first table, then the tables joined to it
(def %sql-from
  (fn (_ ts)
    (let ((source (%sql-source ts)))
      (let ((joins (%sql-joins (rest source))))
        (pair (pair (first source) (first joins)) (rest joins))))))

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

; One optional clause: (VALUE . tokens-left), VALUE nil when TS does not
; start with WORDS, else what READ reads after them
(def %sql-clause
  (fn (_ words read ts)
    (let ((after (%sql-after ts words)))
      (if (null? after) (pair () ts) (read (first after))))))

(def %sql-group
  (fn (_ ts)
    (if (%sql-kw? ts "ALL") (pair (lit all) (rest ts))
      (%sql-list %sql-expr ts))))

(def %sql-order (fn (_ ts) (%sql-list %sql-order-term ts)))

; The clauses after the tables, each nil when absent, as
; (WHERE ORDER LIMIT OFFSET GROUP HAVING)
(def %sql-tail
  (fn (_ ts)
    (let ((where (%sql-clause (list "WHERE") %sql-expr ts)))
      (let ((group (%sql-clause (list "GROUP" "BY") %sql-group (rest where))))
        (let ((having (%sql-clause (list "HAVING") %sql-expr (rest group))))
          (let ((order (%sql-clause (list "ORDER" "BY") %sql-order (rest having))))
            (let ((limit (%sql-clause (list "LIMIT") %sql-expr (rest order))))
              (let ((offset (%sql-clause (list "OFFSET") %sql-expr (rest limit))))
                (%sql-refuse-unread (rest offset))
                (pair (list (first where) (first order) (first limit)
                            (first offset) (first group) (first having))
                      (rest offset))))))))))

; The items after SELECT and whether DISTINCT came first:
; ((ITEMS . DISTINCT) . tokens-left)
(def %sql-items
  (fn (_ ts)
    (let ((distinct (%sql-kw? ts "DISTINCT")))
      (let ((is (%sql-list %sql-item (if distinct (rest ts) ts))))
        (pair (pair (first is) distinct) (rest is))))))

; ITEMS is %sql-items' (ITEMS . DISTINCT), TAIL %sql-tail's list
(def %sql-select-node
  (fn (_ items from tail)
    (pair (lit select)
      (pair (first items)
        (pair from (List append tail (list (rest items))))))))

; SELECT items [FROM tables] and the clauses after
(def %sql-select
  (fn (_ ts)
    (when (or (null? ts) (%sql-op? ts ";"))
      (error "Parser Error: SELECT clause without selection list"))
    (%sql-refuse-unread ts)
    (let ((is (%sql-items ts)))
      (let ((from (if (%sql-kw? (rest is) "FROM") (%sql-from (rest (rest is)))
                    (pair () (rest is)))))
        (let ((tail (%sql-tail (rest from))))
          (pair (%sql-select-node (first is) (first from) (first tail))
                (rest tail)))))))

; FROM tables [SELECT items] and the clauses after: DuckDB's order
(def %sql-from-first
  (fn (_ ts)
    (let ((from (%sql-from ts)))
      (let ((is (if (%sql-kw? (rest from) "SELECT")
                  (%sql-items (rest (rest from)))
                  (pair (pair (list (list (list (lit star) ()) ())) #f)
                        (rest from)))))
        (let ((tail (%sql-tail (rest is))))
          (pair (%sql-select-node (first is) (first from) (first tail))
                (rest tail)))))))

; A column of CREATE TABLE: its name and its type
(def %sql-column
  (fn (_ ts)
    (let ((name (%sql-name ts)) (type (%sql-type (rest ts))))
      (unless (or (%sql-op? (rest type) ",") (%sql-op? (rest type) ")"))
        (if (null? (rest type)) (%sql-near (rest type))
          (error (Str8 str "Not implemented Error: "
                           (List second (first (rest type)))
                           " in a column definition"))))
      (pair (list name (first (first type))) (rest type)))))

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
              (let ((columns (if (and (%sql-kw? (rest at) "AS") (%sql-query? (rest (rest at))))
                               (%sql-query (rest (rest at)))
                               (%sql-parenthesized %sql-column (rest at)))))
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
            (if (%sql-query? (rest names))
              (let ((q (%sql-query (rest names))))
                (pair (list (lit insert) table (first names) (first q)) (rest q)))
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

; One select statement in either order, or a WITH before one
(def %sql-simple-query
  (fn (_ ts)
    (match
      ((%sql-kw? ts "SELECT") (%sql-select (rest ts)))
      ((%sql-kw? ts "FROM") (%sql-from-first (rest ts)))
      ((%sql-kw? ts "WITH") (%sql-with (rest ts)))
      (#t (%sql-near ts)))))

; A select statement without its ORDER BY, LIMIT and OFFSET, and those:
; (STATEMENT ORDER LIMIT OFFSET).  Only a SELECT has them to give.
(def %sql-without-tail
  (fn (_ stmt)
    (if (eq? (first stmt) (lit select))
      (list (list (lit select) (List second stmt) (List third stmt) (List ref 3 stmt)
                  () () () (List ref 7 stmt) (List ref 8 stmt) (List ref 9 stmt))
            (List ref 4 stmt) (List ref 5 stmt) (List ref 6 stmt))
      (list stmt () () ()))))

; LEFT and RIGHT under a set operation.  What ORDER BY, LIMIT and OFFSET
; RIGHT ends with are the whole's: the set is then the one table of a
; SELECT * that has them.
(def %sql-set-node
  (fn (_ op all left right)
    (let ((tail (%sql-without-tail right)))
      (let ((node (list (lit set) op all left (first tail))))
        (if (and (null? (List second tail)) (null? (List third tail)) (null? (List ref 3 tail)))
          node
          (list (lit select) (list (list (list (lit star) ()) ()))
                (list (list node ()))
                () (List second tail) (List third tail) (List ref 3 tail) () () #f))))))

; Whether ALL follows a set operation's word, and the tokens after it or
; after DISTINCT: (ALL . tokens-left)
(def %sql-set-all
  (fn (_ ts)
    (match
      ((%sql-kw? ts "ALL") (pair #t (rest ts)))
      ((%sql-kw? ts "DISTINCT") (pair #f (rest ts)))
      (#t (pair #f ts)))))

; Statements NEXT reads, joined left to right by the set operations WORDS
; name, each (WORD NAME)
(def %sql-set-chain
  (fn (_ next words ts)
    (let ((l (next ts)))
      ((fn (self left ts)
         (let ((word (List find (fn (_ w) (%sql-kw? ts (first w))) words)))
           (if (null? word) (pair left ts)
             (let ((all (%sql-set-all (rest ts))))
               (let ((r (next (rest all))))
                 (self (%sql-set-node (List second word) (first all) left (first r))
                       (rest r)))))))
       (first l) (rest l)))))

; INTERSECT joins tighter than UNION and EXCEPT
(def %sql-intersections
  (fn (_ ts)
    (%sql-set-chain %sql-simple-query (list (list "INTERSECT" (lit intersect))) ts)))

; A select statement, or several under set operations
(def %sql-query
  (fn (_ ts)
    (%sql-set-chain %sql-intersections
      (list (list "UNION" (lit union)) (list "EXCEPT" (lit except)))
      ts)))

; One table of a WITH: name AS (select statement)
(def %sql-with-table
  (fn (_ ts)
    (let ((name (%sql-name ts)))
      (if (and (%sql-kw? (rest ts) "AS") (%sql-op? (rest (rest ts)) "("))
        (let ((q (%sql-closed-query (rest (rest (rest ts))))))
          (pair (list name (first q)) (rest q)))
        (%sql-near (rest ts))))))

(def %sql-with
  (fn (_ ts)
    (let ((tables (%sql-list %sql-with-table ts)))
      (let ((q (%sql-query (rest tables))))
        (pair (list (lit with) (first tables) (first q)) (rest q))))))

; One SET of an UPDATE: column = expression
(def %sql-set
  (fn (_ ts)
    (let ((name (%sql-name ts)))
      (if (%sql-op? (rest ts) "=")
        (let ((e (%sql-expr (rest (rest ts)))))
          (pair (list name (first e)) (rest e)))
        (%sql-near (rest ts))))))

; UPDATE table SET column = expression, ... [WHERE condition]
(def %sql-update
  (fn (_ ts)
    (let ((table (%sql-name ts)))
      (if (%sql-word? (rest ts) "SET")
        (let ((sets (%sql-list %sql-set (rest (rest ts)))))
          (let ((where (%sql-clause (list "WHERE") %sql-expr (rest sets))))
            (pair (list (lit update) table (first sets) (first where)) (rest where))))
        (%sql-near (rest ts))))))

; DELETE FROM table [WHERE condition]
(def %sql-delete
  (fn (_ ts)
    (if (%sql-kw? ts "FROM")
      (let ((table (%sql-name (rest ts))))
        (let ((where (%sql-clause (list "WHERE") %sql-expr (rest (rest ts)))))
          (pair (list (lit delete) table (first where)) (rest where))))
      (%sql-near ts))))

; One option of a COPY, TS at its name: FORMAT and a name, or HEADER and
; maybe true or false, as ((NAME VALUE) . tokens-left)
(def %sql-copy-option
  (fn (_ ts)
    (match
      ((and (%sql-word? ts "FORMAT") (%sql-name? (rest ts)))
        (pair (list (lit format) (List second (List second ts))) (rest (rest ts))))
      ((%sql-word? ts "HEADER")
        (match
          ((%sql-kw? (rest ts) "TRUE") (pair (list (lit header) #t) (rest (rest ts))))
          ((%sql-kw? (rest ts) "FALSE") (pair (list (lit header) #f) (rest (rest ts))))
          (#t (pair (list (lit header) #t) (rest ts)))))
      ((null? ts) (%sql-near ts))
      (#t (error (Str8 str "Not implemented Error: the COPY option " (List second (first ts))))))))

; The options after a COPY's file, in parentheses or not there, as an
; alist of (NAME VALUE)
(def %sql-copy-options
  (fn (_ ts)
    (if (%sql-op? ts "(") (%sql-parenthesized %sql-copy-option ts) (pair () ts))))

(def %sql-option
  (fn (_ options name otherwise)
    (let ((found (List find (fn (_ o) (eq? (first o) name)) options)))
      (if (null? found) otherwise (List second found)))))

; COPY table or (select statement) TO 'file', and COPY table FROM 'file',
; each with options after
(def %sql-copy
  (fn (_ ts)
    (let ((source (if (and (%sql-op? ts "(") (%sql-query? (rest ts)))
                    (%sql-closed-query (rest ts))
                    (pair (%sql-name ts) (rest ts)))))
      (let ((after (rest source)))
        (unless (and (or (%sql-word? after "TO") (%sql-kw? after "FROM"))
                     (not (null? (rest after))) (eq? (first (List second after)) (lit str)))
          (%sql-near (if (null? after) after (rest after))))
        (let ((path (List second (List second after)))
              (options (%sql-copy-options (rest (rest after)))))
          (pair (if (%sql-word? after "TO")
                  (list (lit copy-to) (first source) path
                        (%sql-option (first options) (lit format) ())
                        (%sql-option (first options) (lit header) #t))
                  (list (lit copy-from) (first source) path
                        (%sql-option (first options) (lit format) ())))
                (rest options)))))))

(def %sql-statement
  (fn (_ ts)
    (match
      ((%sql-word? ts "COPY") (%sql-copy (rest ts)))
      ((%sql-query? ts) (%sql-query ts))
      ((%sql-kw? ts "CREATE") (%sql-create (rest ts)))
      ((%sql-word? ts "INSERT") (%sql-insert (rest ts)))
      ((%sql-word? ts "UPDATE") (%sql-update (rest ts)))
      ((%sql-word? ts "DELETE") (%sql-delete (rest ts)))
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

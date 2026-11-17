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
; A statement:
;   (select ITEMS)          ITEMS a list of (EXPR ALIAS), ALIAS nil or text
;
; An expression, its head the name sql/eval's classes know it by:
;   (int N)  (str TEXT)  (bool B)  (null)  (col NAME)
;   (neg E)  (not E)  (is-null E NEGATED)
;   (and A B)  (or A B)
;   (bin OP A B)            OP a name from sql/words' sql-binary-ops

(module sql/parse)
(import x/type/list)
(import x/type/str)
(import sql/words sql-binary-ops)
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
            ((%sql-name? ts) (pair (list (lit col) text) (rest ts)))
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

(def %sql-items
  (fn (self ts)
    (let ((i (%sql-item ts)))
      (if (%sql-op? (rest i) ",")
        (let ((more (self (rest (rest i)))))
          (pair (pair (first i) (first more)) (rest more)))
        (pair (list (first i)) (rest i))))))

; The clauses a SELECT takes that are not read yet
(def %sql-unread
  (list "FROM" "WHERE" "GROUP" "HAVING" "ORDER" "LIMIT" "OFFSET" "UNION"
        "EXCEPT" "INTERSECT"))

(def %sql-select
  (fn (_ ts)
    (when (or (null? ts) (%sql-op? ts ";"))
      (error "Parser Error: SELECT clause without selection list"))
    (let ((is (%sql-items ts)))
      (let ((after (rest is)))
        (if (if (null? after) #f
              (if (eq? (first (first after)) (lit kw))
                (List includes? (List second (first after)) %sql-unread)
                #f))
          (error (Str8 str "Not implemented Error: " (List second (first after))))
          (pair (list (lit select) (first is)) after))))))

(def %sql-statement
  (fn (_ ts)
    (if (%sql-kw? ts "SELECT") (%sql-select (rest ts)) (%sql-near ts))))

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

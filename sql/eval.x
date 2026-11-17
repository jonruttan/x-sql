; # x-sql -- SQL on x-lang
;
; ## sql/eval.x -- what a statement answers
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A value is (TYPE . X): TYPE one of integer, bigint, hugeint, varchar,
; boolean and null, and X the x value, nil for NULL.  A NULL keeps the type
; of the expression it came from; the constant NULL has the type null.
;
; A result is (NAMES TYPES ROWS), each row a list of values.
;
; Three classes hold what is chosen by a name: SqlNode evaluates an
; expression by its head, SqlName spells one for a column heading, and
; SqlOp applies a binary operator.  SqlStatement runs a statement.  The
; name is a symbol the parser made, so the lookup is class-static-ref.

(module sql/eval)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/num/tower)
(import sql/words sql-binary-ops)

; --- types -------------------------------------------------------------------

(def %sql-2^31 2147483648)
(def %sql-2^63 (* %sql-2^31 %sql-2^31 2))
(def %sql-2^127 (* %sql-2^63 %sql-2^63 2))

; An integer type, one past its greatest value, and its name in an error;
; narrowest first.
(def %sql-int-rows
  (list (list (lit integer) %sql-2^31 "INT32")
        (list (lit bigint) %sql-2^63 "INT64")
        (list (lit hugeint) %sql-2^127 "INT128")))

; A type, its SQL name, and the name a result's heading shows
(def %sql-type-rows
  (list (list (lit integer) "INTEGER" "int32")
        (list (lit bigint) "BIGINT" "int64")
        (list (lit hugeint) "HUGEINT" "int128")
        (list (lit varchar) "VARCHAR" "varchar")
        (list (lit boolean) "BOOLEAN" "boolean")
        (list (lit null) "NULL" "\"null\"")))

(def %sql-row
  (fn (_ key rows) (List find (fn (_ r) (eq? (first r) key)) rows)))

(def %sql-int? (fn (_ t) (not (null? (%sql-row t %sql-int-rows)))))
(def %sql-limit (fn (_ t) (List second (%sql-row t %sql-int-rows))))
(def %sql-type-name (fn (_ t) (List second (%sql-row t %sql-type-rows))))

(def sql-integer-type? %sql-int?)
(def sql-type-heading (fn (_ t) (List third (%sql-row t %sql-type-rows))))

(def %sql-fits?
  (fn (_ t n)
    (let ((limit (%sql-limit t)))
      (and (< n limit) (>= n (- 0 limit))))))

; The narrowest integer type holding N
(def %sql-int-type
  (fn (_ n)
    (let ((row (List find (fn (_ r) (%sql-fits? (first r) n)) %sql-int-rows)))
      (if (null? row)
        (error (Str8 str "Not implemented Error: the integer " n
                         " is wider than HUGEINT"))
        (first row)))))

(def %sql-wider
  (fn (_ a b) (if (>= (%sql-limit a) (%sql-limit b)) a b)))

; A value as a result shows it
(def sql-value-text
  (fn (_ v)
    (let ((x (rest v)))
      (match
        ((null? x) "NULL")
        ((eq? (first v) (lit boolean)) (if x "true" "false"))
        ((eq? (first v) (lit varchar)) x)
        (#t (Str8 str x))))))

(def %sql-null? (fn (_ v) (null? (rest v))))

; --- arithmetic --------------------------------------------------------------

; The type of an arithmetic result: the wider operand's.  A NULL constant
; takes the other operand's type, and two of them are a BIGINT, as DuckDB
; has it.
(def %sql-arith-type
  (fn (_ sign a b)
    (let ((ta (first a)) (tb (first b)))
      (match
        ((and (%sql-int? ta) (%sql-int? tb)) (%sql-wider ta tb))
        ((and (%sql-int? ta) (eq? tb (lit null))) ta)
        ((and (eq? ta (lit null)) (%sql-int? tb)) tb)
        ((and (eq? ta (lit null)) (eq? tb (lit null))) (lit bigint))
        (#t
          (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                           sign "(" (%sql-type-name ta) ", " (%sql-type-name tb) ")'.")))))))

; An integer result of type T, or the overflow WORD names
(def %sql-checked
  (fn (_ t r word sign a b)
    (if (%sql-fits? t r) (pair t r)
      (error (Str8 str "Out of Range Error: Overflow in " word " of "
                       (List third (%sql-row t %sql-int-rows))
                       " (" (rest a) " " sign " " (rest b) ")!")))))

(def %sql-arith
  (fn (_ sign word f a b)
    (let ((t (%sql-arith-type sign a b)))
      (if (or (%sql-null? a) (%sql-null? b)) (pair t ())
        (%sql-checked t (f (rest a) (rest b)) word sign a b)))))

(def %sql-divide
  (fn (_ sign f a b name)
    (let ((t (%sql-arith-type sign a b)))
      (match
        ((or (%sql-null? a) (%sql-null? b)) (pair t ()))
        ((= (rest b) 0)
          (error (Str8 str "Invalid Input Error: Division by zero in expression "
                           name ".")))
        (#t (%sql-checked t (f (rest a) (rest b)) "division" sign a b))))))

; --- comparison --------------------------------------------------------------

; -1, 0 or 1: how two values of one family stand
(def %sql-order
  (fn (_ a b)
    (let ((ta (first a)) (tb (first b)) (x (rest a)) (y (rest b)))
      (match
        ((and (%sql-int? ta) (%sql-int? tb))
          (if (< x y) -1 (if (= x y) 0 1)))
        ((and (eq? ta (lit varchar)) (eq? tb (lit varchar)))
          (if (Str8 <? x y) -1 (if (Str8 =? x y) 0 1)))
        ((and (eq? ta (lit boolean)) (eq? tb (lit boolean)))
          (if (eq? x y) 0 (if y -1 1)))
        (#t
          (error (Str8 str "Not implemented Error: comparing "
                           (%sql-type-name ta) " with " (%sql-type-name tb))))))))

(def %sql-compare
  (fn (_ a b test)
    (pair (lit boolean)
      (if (or (%sql-null? a) (%sql-null? b)) ()
        (test (%sql-order a b))))))

; --- truth -------------------------------------------------------------------

; #t, #f, or nil for NULL
(def %sql-truth
  (fn (_ v)
    (let ((t (first v)) (x (rest v)))
      (match
        ((null? x) ())
        ((eq? t (lit boolean)) x)
        ((%sql-int? t) (not (= x 0)))
        (#t (error (Str8 str "Conversion Error: Could not convert string '"
                             x "' to BOOL")))))))

; --- the operators -----------------------------------------------------------

(def-class SqlOp ()
  (static
    (method add (self a b name) (%sql-arith "+" "addition" + a b))
    (method sub (self a b name) (%sql-arith "-" "subtraction" - a b))
    (method mul (self a b name) (%sql-arith "*" "multiplication" * a b))
    (method idiv (self a b name)
      (%sql-divide "//" (fn (_ x y) (Num quotient x y)) a b name))
    (method mod (self a b name)
      (%sql-divide "%" (fn (_ x y) (Num remainder x y)) a b name))
    (method div (self a b name)
      (error "Not implemented Error: / answers a DOUBLE, which is not built; // divides integers"))
    ; A NULL constant for an operand makes the result one, as DuckDB has it
    (method concat (self a b name)
      (if (or (eq? (first a) (lit null)) (eq? (first b) (lit null)))
        (pair (lit null) ())
        (pair (lit varchar)
          (if (or (%sql-null? a) (%sql-null? b)) ()
            (Str8 append (sql-value-text a) (sql-value-text b))))))
    (method eq (self a b name) (%sql-compare a b (fn (_ c) (= c 0))))
    (method ne (self a b name) (%sql-compare a b (fn (_ c) (not (= c 0)))))
    (method lt (self a b name) (%sql-compare a b (fn (_ c) (< c 0))))
    (method le (self a b name) (%sql-compare a b (fn (_ c) (<= c 0))))
    (method gt (self a b name) (%sql-compare a b (fn (_ c) (> c 0))))
    (method ge (self a b name) (%sql-compare a b (fn (_ c) (>= c 0))))))

; --- expressions -------------------------------------------------------------

(def sql-eval
  (fn (_ node) ((class-static-ref SqlNode (first node)) SqlNode node)))
(def sql-expr-name
  (fn (_ node) ((class-static-ref SqlName (first node)) SqlName node)))

(def-class SqlNode ()
  (static
    (method int (self node)
      (pair (%sql-int-type (List second node)) (List second node)))
    (method str (self node) (pair (lit varchar) (List second node)))
    (method bool (self node) (pair (lit boolean) (List second node)))
    (method null (self node) (pair (lit null) ()))
    (method col (self node)
      (error (Str8 str "Binder Error: Referenced column \"" (List second node)
                       "\" was not found because the FROM clause is missing")))
    (method neg (self node)
      (let ((v (sql-eval (List second node))))
        (let ((t (%sql-arith-type "-" v v)))
          (if (%sql-null? v) (pair t ())
            (%sql-checked t (- 0 (rest v)) "negation" "-" (pair t 0) v)))))
    (method not (self node)
      (let ((v (%sql-truth (sql-eval (List second node)))))
        (pair (lit boolean) (if (null? v) () (not v)))))
    (method is-null (self node)
      (let ((null (%sql-null? (sql-eval (List second node)))))
        (pair (lit boolean) (if (List third node) (not null) null))))
    (method and (self node)
      (let ((a (%sql-truth (sql-eval (List second node))))
            (b (%sql-truth (sql-eval (List third node)))))
        (pair (lit boolean)
          (match
            ((or (eq? a #f) (eq? b #f)) #f)
            ((or (null? a) (null? b)) ())
            (#t #t)))))
    (method or (self node)
      (let ((a (%sql-truth (sql-eval (List second node))))
            (b (%sql-truth (sql-eval (List third node)))))
        (pair (lit boolean)
          (match
            ((or (eq? a #t) (eq? b #t)) #t)
            ((or (null? a) (null? b)) ())
            (#t #f)))))
    (method bin (self node)
      ((class-static-ref SqlOp (List second node)) SqlOp
       (sql-eval (List third node))
       (sql-eval (List ref 3 node))
       (sql-expr-name node)))))

; How a binary operator is spelled in a heading
(def %sql-op-text
  (fn (_ name)
    (List third (List find (fn (_ r) (eq? (List second r) name)) sql-binary-ops))))

(def-class SqlName ()
  (static
    (method int (self node) (Str8 str (List second node)))
    (method str (self node)
      (Str8 append "'" (Str8 replace "'" "''" (List second node)) "'"))
    (method bool (self node) (if (List second node) "true" "false"))
    (method null (self node) "NULL")
    (method col (self node) (List second node))
    (method neg (self node)
      (Str8 append "(-(" (sql-expr-name (List second node)) "))"))
    (method not (self node)
      (Str8 append "(NOT " (sql-expr-name (List second node)) ")"))
    (method is-null (self node)
      (Str8 append "(" (sql-expr-name (List second node))
                   (if (List third node) " IS NOT NULL)" " IS NULL)")))
    (method and (self node)
      (Str8 append "(" (sql-expr-name (List second node)) " AND "
                   (sql-expr-name (List third node)) ")"))
    (method or (self node)
      (Str8 append "(" (sql-expr-name (List second node)) " OR "
                   (sql-expr-name (List third node)) ")"))
    (method bin (self node)
      (Str8 append "(" (sql-expr-name (List third node)) " "
                   (%sql-op-text (List second node)) " "
                   (sql-expr-name (List ref 3 node)) ")"))))

; --- statements --------------------------------------------------------------

(def-class SqlStatement ()
  (static
    (method select (self stmt)
      (let ((items (List second stmt)))
        (let ((values (List map (fn (_ i) (sql-eval (first i))) items)))
          (list (List map
                  (fn (_ i)
                    (if (null? (List second i)) (sql-expr-name (first i))
                      (List second i)))
                  items)
                (List map first values)
                (list values)))))))

(def sql-execute
  (fn (_ stmt) ((class-static-ref SqlStatement (first stmt)) SqlStatement stmt)))

(provide sql/eval
  sql-eval sql-expr-name sql-execute sql-value-text sql-type-heading
  sql-integer-type?)

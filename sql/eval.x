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
; Four classes hold what is chosen by a name: SqlNode evaluates an
; expression by its head, SqlName spells one for a column heading, SqlOp
; applies a binary operator, and SqlAggregate answers for a group of rows.  The name is a symbol the parser made,
; so the lookup is class-static-ref.

(module sql/eval)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/num/tower)
(import sql/words sql-binary-ops sql-aggregates)

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

; NODE's value in SCOPE: nil where there is no FROM, else
; (COLUMNS ROW GROUP).  COLUMNS is a list of (QUALIFIER NAME TYPE) and ROW
; their x values.  GROUP is nil for a row of the tables, and for a group of
; rows a one-element list holding the group's scopes, ROW then being the
; first of them, or NULLs when the group is empty.
(def sql-eval
  (fn (_ node scope)
    ((class-static-ref SqlNode (first node)) SqlNode node scope)))

(def sql-expr-name
  (fn (_ node) ((class-static-ref SqlName (first node)) SqlName node)))

; The places in COLUMNS of the columns NAME names under QUALIFIER, nil or
; a table's name; names match in any case
(def %sql-column-places
  (fn (_ name qualifier columns)
    (List filter
      (fn (_ i)
        (let ((c (List ref i columns)))
          (and (Str8 ci=? (List second c) name)
               (or (null? qualifier) (Str8 ci=? (first c) qualifier)))))
      (List range 0 (List length columns)))))

; The place in COLUMNS of the one column NAME names.  None, a table that is
; not there, and more than one are errors.
(def sql-column-index
  (fn (_ name qualifier columns)
    (when (and (not (null? qualifier))
               (null? (List find (fn (_ c) (Str8 ci=? (first c) qualifier)) columns)))
      (error (Str8 str "Binder Error: Referenced table \"" qualifier "\" not found!")))
    (let ((places (%sql-column-places name qualifier columns)))
      (match
        ((null? places)
          (error (Str8 str "Binder Error: Referenced column \"" name
                           "\" not found in FROM clause!")))
        ((null? (rest places)) (first places))
        (#t
          (error (Str8 str "Binder Error: Ambiguous reference to column name \""
                           name "\" (use: "
                           (Str8 join " or "
                             (List map
                               (fn (_ i)
                                 (Str8 append "'" (first (List ref i columns)) "."
                                              (List second (List ref i columns)) "'"))
                               places))
                           ")")))))))

; --- aggregates --------------------------------------------------------------

(def %sql-aggregate?
  (fn (_ name) (List includes? (Str8 downcase name) sql-aggregates)))

; NODE holds a call to an aggregate, at any depth
(def sql-aggregated?
  (fn (self node)
    (if (pair? node)
      (if (and (eq? (first node) (lit call)) (%sql-aggregate? (List second node)))
        #t
        (List any? self node))
      #f)))

; A scope of a group as a scope of its first row, for what is not
; aggregated
(def %sql-plain (fn (_ scope) (list (first scope) (List second scope) ())))

; The values ARG has over a group's rows, the NULLs left out, and each
; value once when DISTINCT
(def %sql-values
  (fn (_ node scope)
    (let ((arg (first (List third node))))
      (let ((values (List filter (fn (_ v) (not (%sql-null? v)))
                      (List map (fn (_ member) (sql-eval arg member))
                                (first (List third scope))))))
        (if (List ref 3 node) (%sql-once values ()) values)))))

; VALUES, each once, in the order they first come.  SEEN holds the ones
; kept, newest first.
(def %sql-once
  (fn (self values seen)
    (match
      ((null? values) (List reverse seen))
      ((List any? (fn (_ v) (equal? v (first values))) seen)
        (self (rest values) seen))
      (#t (self (rest values) (pair (first values) seen))))))

; The type ARG has in a group, read off the group's first row
(def %sql-arg-type
  (fn (_ node scope)
    (first (sql-eval (first (List third node)) (%sql-plain scope)))))

; The least or the greatest of a group: PICK says whether a value takes the
; place of the one held
(def %sql-extreme
  (fn (_ node scope pick)
    (let ((values (%sql-values node scope)))
      (if (null? values) (pair (%sql-arg-type node scope) ())
        (List fold (fn (_ best v) (if (pick (%sql-order v best)) v best))
                   (first values) (rest values))))))

(def %sql-one-argument
  (fn (_ node)
    (let ((args (List third node)))
      (when (or (null? args) (not (null? (rest args)))
                (eq? (first (first args)) (lit star)))
        (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                         (sql-expr-name node) "'."))))))

(def-class SqlAggregate ()
  (static
    (method count (self node scope)
      (let ((args (List third node)))
        (pair (lit bigint)
          (if (or (null? args) (eq? (first (first args)) (lit star)))
            (List length (first (List third scope)))
            (do (%sql-one-argument node)
                (List length (%sql-values node scope)))))))
    (method sum (self node scope)
      (%sql-one-argument node)
      (unless (%sql-int? (%sql-arg-type node scope))
        (error (Str8 str "Binder Error: No function matches the given name and argument types 'sum("
                         (%sql-type-name (%sql-arg-type node scope)) ")'.")))
      (let ((values (%sql-values node scope)))
        (if (null? values) (pair (lit hugeint) ())
          (let ((total (List fold (fn (_ acc v) (+ acc (rest v))) 0 values)))
            (if (%sql-fits? (lit hugeint) total) (pair (lit hugeint) total)
              (error "Out of Range Error: Overflow in HUGEINT addition"))))))
    (method min (self node scope)
      (%sql-one-argument node)
      (%sql-extreme node scope (fn (_ c) (< c 0))))
    (method max (self node scope)
      (%sql-one-argument node)
      (%sql-extreme node scope (fn (_ c) (> c 0))))))

(def-class SqlNode ()
  (static
    (method int (self node scope)
      (pair (%sql-int-type (List second node)) (List second node)))
    (method str (self node scope) (pair (lit varchar) (List second node)))
    (method bool (self node scope) (pair (lit boolean) (List second node)))
    (method null (self node scope) (pair (lit null) ()))
    (method col (self node scope)
      (if (null? scope)
        (error (Str8 str "Binder Error: Referenced column \"" (List second node)
                         "\" was not found because the FROM clause is missing"))
        (let ((i (sql-column-index (List second node) (List third node) (first scope))))
          (pair (List third (List ref i (first scope)))
                (List ref i (List second scope))))))
    (method call (self node scope)
      (let ((aggregate (class-static-ref SqlAggregate
                         (Str8 ->sym (Str8 downcase (List second node))))))
        (match
          ((null? aggregate)
            (error (Str8 str "Catalog Error: Scalar Function with name "
                             (List second node) " does not exist!")))
          ((sql-aggregated? (List third node))
            (error "Binder Error: aggregate function calls cannot be nested"))
          ((or (null? scope) (null? (List third scope)))
            (error "Binder Error: an aggregate has no group of rows here"))
          (#t (aggregate SqlAggregate node scope)))))
    (method neg (self node scope)
      (let ((v (sql-eval (List second node) scope)))
        (let ((t (%sql-arith-type "-" v v)))
          (if (%sql-null? v) (pair t ())
            (%sql-checked t (- 0 (rest v)) "negation" "-" (pair t 0) v)))))
    (method not (self node scope)
      (let ((v (%sql-truth (sql-eval (List second node) scope))))
        (pair (lit boolean) (if (null? v) () (not v)))))
    (method is-null (self node scope)
      (let ((null (%sql-null? (sql-eval (List second node) scope))))
        (pair (lit boolean) (if (List third node) (not null) null))))
    (method and (self node scope)
      (let ((a (%sql-truth (sql-eval (List second node) scope)))
            (b (%sql-truth (sql-eval (List third node) scope))))
        (pair (lit boolean)
          (match
            ((or (eq? a #f) (eq? b #f)) #f)
            ((or (null? a) (null? b)) ())
            (#t #t)))))
    (method or (self node scope)
      (let ((a (%sql-truth (sql-eval (List second node) scope)))
            (b (%sql-truth (sql-eval (List third node) scope))))
        (pair (lit boolean)
          (match
            ((or (eq? a #t) (eq? b #t)) #t)
            ((or (null? a) (null? b)) ())
            (#t #f)))))
    (method bin (self node scope)
      ((class-static-ref SqlOp (List second node)) SqlOp
       (sql-eval (List third node) scope)
       (sql-eval (List ref 3 node) scope)
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
    (method col (self node)
      (if (null? (List third node)) (List second node)
        (Str8 append (List third node) "." (List second node))))
    (method star (self node) "*")
    (method call (self node)
      (let ((args (List third node)))
        (if (and (%sql-aggregate? (List second node))
                 (Str8 ci=? (List second node) "count")
                 (or (null? args) (eq? (first (first args)) (lit star))))
          "count_star()"
          (Str8 append (Str8 downcase (List second node)) "("
                       (if (List ref 3 node) "DISTINCT " "")
                       (Str8 join ", " (List map sql-expr-name args))
                       ")"))))
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

; --- casts -------------------------------------------------------------------

; The integer TEXT spells, or nil: an optional sign, then digits
(def %sql-text-integer
  (fn (_ text)
    (let ((n (Str8 length text)))
      (let ((signed (and (> n 0) (or (Str8 starts? "-" text) (Str8 starts? "+" text)))))
        (let ((start (if signed 1 0)))
          (if (>= start n) ()
            ((fn (self i acc)
               (if (>= i n) (if (Str8 starts? "-" text) (- 0 acc) acc)
                 (let ((d (- (Char ->int (Str8 ref i text)) 48)))
                   (if (and (>= d 0) (<= d 9)) (self (+ i 1) (+ (* acc 10) d)) ()))))
             start 0)))))))

(def %sql-int-name (fn (_ t) (List third (%sql-row t %sql-int-rows))))

; The x value of V as the type T holds it, for storing in a column
(def sql-cast
  (fn (_ v t)
    (let ((from (first v)) (x (rest v)))
      (match
        ((null? x) ())
        ((eq? t (lit varchar)) (sql-value-text v))
        ((and (%sql-int? from) (%sql-int? t))
          (if (%sql-fits? t x) x
            (error (Str8 str "Conversion Error: Type " (%sql-int-name from)
                             " with value " x
                             " can't be cast because the value is out of range for the destination type "
                             (%sql-int-name t)))))
        ((and (eq? from (lit varchar)) (%sql-int? t))
          (let ((n (%sql-text-integer (Str8 trim x))))
            (if (and (not (null? n)) (%sql-fits? t n)) n
              (error (Str8 str "Conversion Error: Could not convert string '" x
                               "' to " (%sql-int-name t))))))
        ((eq? from t) x)
        (#t (error (Str8 str "Not implemented Error: casting " (%sql-type-name from)
                             " to " (%sql-type-name t))))))))

(def sql-truth %sql-truth)
(def sql-order %sql-order)
(def sql-null? %sql-null?)

(provide sql/eval
  sql-eval sql-expr-name sql-column-index sql-aggregated? sql-cast
  sql-truth sql-order sql-null? sql-value-text sql-type-heading
  sql-integer-type?)

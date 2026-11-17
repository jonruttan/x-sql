; # x-sql -- SQL on x-lang
;
; ## sql/eval.x -- what a statement answers
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A value is (TYPE . X): TYPE one of integer, bigint, hugeint, double,
; varchar, boolean and null, or (decimal WIDTH SCALE), and X the x value,
; nil for NULL.  A decimal's X is its digits as an integer: 1.50 is 150 at
; scale 2.  A NULL keeps the type
; of the expression it came from; the constant NULL has the type null.
;
; Five classes hold what is chosen by a name: SqlNode evaluates an
; expression by its head, SqlName spells one for a column heading, SqlOp
; applies a binary operator, SqlAggregate answers for a group of rows, and
; SqlCast makes a value one of a type.  The name is a symbol the parser made,
; so the lookup is class-static-ref.

(module sql/eval)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/num/tower)
(import x/num/float)
(import sql/words sql-binary-ops sql-aggregates)
(import sql/lex sql-lex)
(import sql/number
  sql-pow10 sql-double-text sql-double-of sql-double-scaled
  sql-double-integer sql-double-finite? sql-decimal-read sql-rescale
  sql-decimal-text)

; --- types -------------------------------------------------------------------

(def %sql-2^31 2147483648)
(def %sql-2^63 (* %sql-2^31 %sql-2^31 2))
(def %sql-2^127 (* %sql-2^63 %sql-2^63 2))

; An integer type, one past its greatest value, its name in an error, and
; the width of the DECIMAL that holds it; narrowest first.
(def %sql-int-rows
  (list (list (lit integer) %sql-2^31 "INT32" 10)
        (list (lit bigint) %sql-2^63 "INT64" 19)
        (list (lit hugeint) %sql-2^127 "INT128" 38)))

; A type, its SQL name, and the name a result's heading shows
(def %sql-type-rows
  (list (list (lit integer) "INTEGER" "int32")
        (list (lit bigint) "BIGINT" "int64")
        (list (lit hugeint) "HUGEINT" "int128")
        (list (lit double) "DOUBLE" "double")
        (list (lit varchar) "VARCHAR" "varchar")
        (list (lit boolean) "BOOLEAN" "boolean")
        (list (lit null) "NULL" "\"null\"")))

(def %sql-row
  (fn (_ key rows) (List find (fn (_ r) (eq? (first r) key)) rows)))

(def %sql-int? (fn (_ t) (not (null? (%sql-row t %sql-int-rows)))))
(def %sql-limit (fn (_ t) (List second (%sql-row t %sql-int-rows))))
(def %sql-int-name (fn (_ t) (List third (%sql-row t %sql-int-rows))))

(def %sql-decimal? (fn (_ t) (pair? t)))
(def %sql-double? (fn (_ t) (eq? t (lit double))))
(def %sql-null-type? (fn (_ t) (eq? t (lit null))))
(def %sql-numeric?
  (fn (_ t) (or (%sql-int? t) (%sql-decimal? t) (%sql-double? t))))

; The most digits a DECIMAL holds
(def %sql-decimal-width 38)

(def %sql-decimal-name
  (fn (_ t) (Str8 str "(" (List second t) "," (List third t) ")")))

(def %sql-type-name
  (fn (_ t)
    (if (%sql-decimal? t) (Str8 append "DECIMAL" (%sql-decimal-name t))
      (List second (%sql-row t %sql-type-rows)))))

(def sql-type-heading
  (fn (_ t)
    (if (%sql-decimal? t) (Str8 append "decimal" (%sql-decimal-name t))
      (List third (%sql-row t %sql-type-rows)))))

(def sql-numeric-type? %sql-numeric?)

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
    (let ((t (first v)) (x (rest v)))
      (match
        ((null? x) "NULL")
        ((eq? t (lit boolean)) (if x "true" "false"))
        ((eq? t (lit varchar)) x)
        ((%sql-double? t) (sql-double-text x))
        ((%sql-decimal? t) (sql-decimal-text x (List second t) (List third t)))
        (#t (Str8 str x))))))

(def %sql-null? (fn (_ v) (null? (rest v))))

; --- numbers of unlike types -------------------------------------------------

; The (WIDTH SCALE) of an exact number's type: a decimal's own, and for an
; integer the decimal that holds its type
(def %sql-shape
  (fn (_ t)
    (if (%sql-decimal? t) (rest t)
      (list (List ref 3 (%sql-row t %sql-int-rows)) 0))))

; Integers below this are doubles exactly
(def %sql-2^53 9007199254740992)

; A number as a double.  A wide integer and a decimal go through their
; text, which the platform's reader rounds once.
(def %sql-as-double
  (fn (_ v)
    (let ((t (first v)) (x (rest v)))
      (match
        ((%sql-double? t) x)
        ((%sql-decimal? t)
          (sql-double-of (sql-decimal-text x (+ (List second t) 1) (List third t))))
        ((and (< x %sql-2^53) (> x (- 0 %sql-2^53))) (Float from x))
        (#t (sql-double-of (Str8 str x)))))))

; --- arithmetic --------------------------------------------------------------

; The type of integer arithmetic: the wider operand's.  A NULL constant
; takes the other operand's type, and two of them are a BIGINT, as DuckDB
; has it.
(def %sql-arith-type
  (fn (_ sign a b)
    (let ((ta (first a)) (tb (first b)))
      (match
        ((and (%sql-int? ta) (%sql-int? tb)) (%sql-wider ta tb))
        ((and (%sql-int? ta) (%sql-null-type? tb)) ta)
        ((and (%sql-null-type? ta) (%sql-int? tb)) tb)
        ((and (%sql-null-type? ta) (%sql-null-type? tb)) (lit bigint))
        (#t
          (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                           sign "(" (%sql-type-name ta) ", " (%sql-type-name tb) ")'.")))))))

; An integer result of type T, or the overflow WORD names
(def %sql-checked
  (fn (_ t r word sign a b)
    (if (%sql-fits? t r) (pair t r)
      (error (Str8 str "Out of Range Error: Overflow in " word " of "
                       (%sql-int-name t)
                       " (" (rest a) " " sign " " (rest b) ")!")))))

(def %sql-integer-arith
  (fn (_ sign word f a b)
    (let ((t (%sql-arith-type sign a b)))
      (if (or (%sql-null? a) (%sql-null? b)) (pair t ())
        (%sql-checked t (f (rest a) (rest b)) word sign a b)))))

; A double: both operands as doubles.  An overflow is an infinity.
(def %sql-double-arith
  (fn (_ f a b)
    (pair (lit double)
      (if (or (%sql-null? a) (%sql-null? b)) ()
        (f (%sql-as-double a) (%sql-as-double b))))))

(def %sql-max (fn (_ a b) (if (> a b) a b)))
(def %sql-min (fn (_ a b) (if (< a b) a b)))

; The (WIDTH SCALE) DuckDB gives decimal arithmetic.  A product has the
; widths and the scales added.  A sum has the wider scale and room for the
; wider whole part and a carry.  Neither is wider than a DECIMAL can be.
(def %sql-decimal-shape
  (fn (_ sign a b)
    (if (str=? sign "*")
      (list (%sql-min %sql-decimal-width (+ (first a) (first b)))
            (+ (List second a) (List second b)))
      (let ((scale (%sql-max (List second a) (List second b))))
        (list (%sql-min %sql-decimal-width
                (+ (%sql-max (- (first a) (List second a))
                             (- (first b) (List second b)))
                   scale 1))
              scale)))))

; Exact arithmetic with a decimal in it.  A NULL constant for an operand
; makes the result one, as DuckDB has it.
(def %sql-decimal-arith
  (fn (_ sign word f a b)
    (if (or (%sql-null-type? (first a)) (%sql-null-type? (first b)))
      (pair (lit null) ())
      (let ((sa (%sql-shape (first a))) (sb (%sql-shape (first b))))
        (let ((shape (%sql-decimal-shape sign sa sb)))
          (when (> (List second shape) %sql-decimal-width)
            (error (Str8 str "Not implemented Error: a scale of " (List second shape))))
          (pair (pair (lit decimal) shape)
            (if (or (%sql-null? a) (%sql-null? b)) ()
              (let ((r (if (str=? sign "*") (* (rest a) (rest b))
                         (f (sql-rescale (rest a) (List second sa) (List second shape))
                            (sql-rescale (rest b) (List second sb) (List second shape))))))
                (if (and (< r (sql-pow10 (first shape)))
                         (> r (- 0 (sql-pow10 (first shape)))))
                  r
                  (error (Str8 str "Out of Range Error: Overflow in " word " of DECIMAL("
                                   (first shape) "," (List second shape) ")")))))))))))

(def %sql-numeric-or-null?
  (fn (_ t) (or (%sql-numeric? t) (%sql-null-type? t))))

; + - or *: integers in the wider type, a double when either is one, and
; exactly as a decimal otherwise
(def %sql-arith
  (fn (_ sign word f a b)
    (let ((ta (first a)) (tb (first b)))
      (match
        ((not (and (%sql-numeric-or-null? ta) (%sql-numeric-or-null? tb)))
          (%sql-arith-type sign a b))
        ((or (%sql-double? ta) (%sql-double? tb)) (%sql-double-arith f a b))
        ((or (%sql-decimal? ta) (%sql-decimal? tb))
          (%sql-decimal-arith sign word f a b))
        (#t (%sql-integer-arith sign word f a b))))))

; // or %: integers only
(def %sql-divide
  (fn (_ sign f a b name)
    (when (or (%sql-double? (first a)) (%sql-double? (first b))
              (%sql-decimal? (first a)) (%sql-decimal? (first b)))
      (error (Str8 str "Not implemented Error: " sign " on a number that is not an integer")))
    (let ((t (%sql-arith-type sign a b)))
      (match
        ((or (%sql-null? a) (%sql-null? b)) (pair t ()))
        ((= (rest b) 0)
          (error (Str8 str "Invalid Input Error: Division by zero in expression "
                           name ".")))
        (#t (%sql-checked t (f (rest a) (rest b)) "division" sign a b))))))

; /: always a double
(def %sql-quotient
  (fn (_ a b)
    (if (and (%sql-numeric-or-null? (first a)) (%sql-numeric-or-null? (first b)))
      (%sql-double-arith / a b)
      (%sql-arith-type "/" a b))))

; --- comparison --------------------------------------------------------------

; -1, 0 or 1: how two values of one family stand
(def %sql-order
  (fn (_ a b)
    (let ((ta (first a)) (tb (first b)) (x (rest a)) (y (rest b)))
      (match
        ((and (%sql-int? ta) (%sql-int? tb))
          (if (< x y) -1 (if (= x y) 0 1)))
        ((and (%sql-numeric? ta) (%sql-numeric? tb))
          (if (or (%sql-double? ta) (%sql-double? tb))
            (let ((fx (%sql-as-double a)) (fy (%sql-as-double b)))
              (if (< fx fy) -1 (if (= fx fy) 0 1)))
            (let ((scale (%sql-max (List second (%sql-shape ta))
                                   (List second (%sql-shape tb)))))
              (let ((sx (sql-rescale x (List second (%sql-shape ta)) scale))
                    (sy (sql-rescale y (List second (%sql-shape tb)) scale)))
                (if (< sx sy) -1 (if (= sx sy) 0 1))))))
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
        ((%sql-numeric? t)
          (error (Str8 str "Not implemented Error: a " (%sql-type-name t)
                           " as a truth value")))
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
    (method div (self a b name) (%sql-quotient a b))
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

(def %sql-no-function
  (fn (_ node t)
    (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                     (Str8 downcase (List second node)) "(" (%sql-type-name t) ")'."))))

; The exact sum of VALUES as a T, which holds less than LIMIT either way;
; NULL when there are none
(def %sql-total
  (fn (_ t values limit)
    (if (null? values) (pair t ())
      (let ((total (List fold (fn (_ acc v) (+ acc (rest v))) 0 values)))
        (if (and (< total limit) (> total (- 0 limit))) (pair t total)
          (error (Str8 str "Out of Range Error: Overflow in sum of "
                           (%sql-type-name t))))))))

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
      (let ((t (%sql-arg-type node scope)) (values (%sql-values node scope)))
        (match
          ((%sql-int? t)
            (%sql-total (lit hugeint) values (%sql-limit (lit hugeint))))
          ((%sql-decimal? t)
            (%sql-total (list (lit decimal) %sql-decimal-width (List third t))
                        values (sql-pow10 %sql-decimal-width)))
          ((%sql-double? t)
            (pair t (if (null? values) ()
                      (List fold (fn (_ acc v) (+ acc (rest v)))
                                 (rest (first values)) (rest values)))))
          (#t (%sql-no-function node t)))))
    (method avg (self node scope)
      (%sql-one-argument node)
      (let ((t (%sql-arg-type node scope)) (values (%sql-values node scope)))
        (unless (%sql-numeric? t) (%sql-no-function node t))
        (pair (lit double)
          (if (null? values) ()
            (/ (if (%sql-double? t)
                 (List fold (fn (_ acc v) (+ acc (rest v)))
                            (rest (first values)) (rest values))
                 (%sql-as-double
                   (pair t (List fold (fn (_ acc v) (+ acc (rest v))) 0 values))))
               (Float from (List length values)))))))
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
    (method dec (self node scope)
      (pair (list (lit decimal) (List third node) (List ref 3 node))
            (List second node)))
    (method dbl (self node scope)
      (pair (lit double) (sql-double-of (List second node))))
    (method cast (self node scope)
      (pair (List third node)
            (sql-cast (sql-eval (List second node) scope) (List third node))))
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
        (match
          ((or (%sql-double? (first v)) (%sql-decimal? (first v)))
            (pair (first v)
              (if (%sql-null? v) ()
                (if (%sql-double? (first v)) (- (Float from 0) (rest v))
                  (- 0 (rest v))))))
          (#t
            (let ((t (%sql-arith-type "-" v v)))
              (if (%sql-null? v) (pair t ())
                (%sql-checked t (- 0 (rest v)) "negation" "-" (pair t 0) v)))))))
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
    (method dec (self node) (List ref 4 node))
    (method dbl (self node) (List second node))
    (method cast (self node)
      (Str8 append "CAST(" (sql-expr-name (List second node)) " AS "
                   (List ref 3 node) ")"))
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

; The number TEXT spells, as (NEGATIVE BODY KIND), or nil: blanks around
; it, a sign, and one number as the lexer reads one, KIND 1 an integer and
; 2 one with a point or an exponent
(def %sql-number-text
  (fn (_ text)
    (let ((trimmed (Str8 trim text)))
      (let ((negative (Str8 starts? "-" trimmed)))
        (let ((body (if (or negative (Str8 starts? "+" trimmed))
                      (Str8 sub 1 (Str8 length trimmed) trimmed)
                      trimmed)))
          (let ((tokens (sql-lex body)))
            (if (and (not (null? tokens)) (null? (rest tokens))
                     (eq? (first (first tokens)) (lit num))
                     (< (List third (first tokens)) 3))
              (list negative body (List third (first tokens)))
              ())))))))

(def %sql-exponent?
  (fn (_ body) (or (Str8 includes? "e" body) (Str8 includes? "E" body))))

(def %sql-no-conversion
  (fn (_ text name)
    (error (Str8 str "Conversion Error: Could not convert string '" text
                     "' to " name))))

(def %sql-out-of-range
  (fn (_ v name)
    (error (Str8 str "Conversion Error: Type "
                     (if (%sql-int? (first v)) (%sql-int-name (first v))
                       (%sql-type-name (first v)))
                     " with value " (sql-value-text v)
                     " can't be cast because the value is out of range for the destination type "
                     name))))

; V as an integer, before its range is looked at.  Text spells an integer
; or it is no number; a double's half goes to the even integer and a
; decimal's away from zero, as DuckDB rounds them.
(def %sql-integer-of
  (fn (_ v name)
    (let ((from (first v)) (x (rest v)))
      (match
        ((%sql-int? from) x)
        ((eq? from (lit boolean)) (if x 1 0))
        ((%sql-double? from)
          (if (sql-double-finite? x) (sql-double-integer x)
            (%sql-out-of-range v name)))
        ((%sql-decimal? from) (sql-rescale x (List third from) 0))
        ((eq? from (lit varchar))
          (let ((number (%sql-number-text x)))
            (if (and (not (null? number)) (= (List third number) 1))
              (let ((n (first (sql-decimal-read (List second number)))))
                (if (first number) (- 0 n) n))
              (%sql-no-conversion x name))))
        (#t (error (Str8 str "Not implemented Error: casting "
                             (%sql-type-name from) " to an integer")))))))

(def %sql-cast-integer
  (fn (_ v t)
    (let ((n (%sql-integer-of v (%sql-int-name t))))
      (match
        ((%sql-fits? t n) n)
        ((eq? (first v) (lit varchar)) (%sql-no-conversion (rest v) (%sql-int-name t)))
        (#t (%sql-out-of-range v (%sql-int-name t)))))))

; V as an integer of digits at SCALE, before its width is looked at
(def %sql-scaled-of
  (fn (_ v scale name)
    (let ((from (first v)) (x (rest v)))
      (match
        ((%sql-int? from) (* x (sql-pow10 scale)))
        ((%sql-decimal? from) (sql-rescale x (List third from) scale))
        ((%sql-double? from)
          (if (sql-double-finite? x) (sql-double-scaled x scale)
            (%sql-out-of-range v name)))
        ((eq? from (lit varchar))
          (let ((number (%sql-number-text x)))
            (if (or (null? number) (%sql-exponent? (List second number)))
              (%sql-no-conversion x name)
              (let ((read (sql-decimal-read (List second number))))
                (let ((n (sql-rescale (first read) (List third read) scale)))
                  (if (first number) (- 0 n) n))))))
        (#t (error (Str8 str "Not implemented Error: casting "
                             (%sql-type-name from) " to a decimal")))))))

(def-class SqlCast ()
  (static
    (method varchar (self v t) (sql-value-text v))
    (method integer (self v t) (%sql-cast-integer v t))
    (method bigint (self v t) (%sql-cast-integer v t))
    (method hugeint (self v t) (%sql-cast-integer v t))
    (method double (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((%sql-numeric? from) (%sql-as-double v))
          ((eq? from (lit varchar))
            (let ((number (%sql-number-text x)))
              (if (null? number) (%sql-no-conversion x "DOUBLE")
                (sql-double-of (Str8 append (if (first number) "-" "")
                                            (List second number))))))
          (#t (error (Str8 str "Not implemented Error: casting "
                               (%sql-type-name from) " to DOUBLE"))))))
    (method decimal (self v t)
      (let ((n (%sql-scaled-of v (List third t) (%sql-type-name t)))
            (limit (sql-pow10 (List second t))))
        (if (and (< n limit) (> n (- 0 limit))) n
          (error (Str8 str "Conversion Error: Casting value \"" (sql-value-text v)
                           "\" to type " (%sql-type-name t)
                           " failed: value is out of range!")))))
    (method boolean (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit boolean)) x)
          ((%sql-int? from) (not (= x 0)))
          ((eq? from (lit varchar))
            (match
              ((or (Str8 ci=? x "true") (Str8 ci=? x "t")) #t)
              ((or (Str8 ci=? x "false") (Str8 ci=? x "f")) #f)
              (#t (%sql-no-conversion x "BOOL"))))
          (#t (error (Str8 str "Not implemented Error: casting "
                               (%sql-type-name from) " to BOOLEAN"))))))))

; The x value of V as the type T holds it
(def sql-cast
  (fn (_ v t)
    (if (%sql-null? v) ()
      ((class-static-ref SqlCast (if (%sql-decimal? t) (lit decimal) t))
       SqlCast v t))))

(def sql-truth %sql-truth)
(def sql-order %sql-order)
(def sql-null? %sql-null?)

(provide sql/eval
  sql-eval sql-expr-name sql-column-index sql-aggregated? sql-cast
  sql-truth sql-order sql-null? sql-value-text sql-type-heading
  sql-numeric-type?)

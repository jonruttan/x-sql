; # x-sql -- SQL on x-lang
;
; ## sql/eval.x -- what a statement answers
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A value is (TYPE . X): TYPE one of tinyint, smallint, integer, bigint,
; hugeint, the same five with a u before them, real, double,
; varchar, boolean, date, time, timestamp, interval and null, or
; (decimal WIDTH SCALE), and X the x value, nil for NULL.  A decimal's X is
; its digits as an integer: 1.50 is 150 at scale 2.  A date, a time and a
; timestamp are integers and an interval a list of three, as sql/time has
; them.  A NULL keeps the type
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
(import x/type/dict)
(import x/num/tower)
(import x/num/float)
(import sql/words sql-lower sql-same-name? sql-binary-ops sql-aggregates
  sql-window-functions)
(import sql/lex sql-lex)
(import sql/time
  sql-micros-second sql-micros-minute sql-micros-hour sql-micros-day
  sql-floor-div sql-floor-mod sql-civil sql-days sql-month-days
  sql-date-text sql-clock-text sql-timestamp-text sql-interval-text
  sql-date-read sql-clock-read sql-timestamp-read sql-interval-read
  sql-interval-of sql-interval-add sql-interval-times sql-interval-negated
  sql-timestamp-plus sql-micros-interval sql-interval-micros sql-day-names
  sql-month-names sql-day-of-year sql-moment-diff sql-moment-trunc)
(import sql/number
  sql-pow10 sql-double-text sql-double-of sql-double-scaled sql-real-text
  sql-real-of
  sql-double-integer sql-double-finite? sql-decimal-read sql-rescale
  sql-decimal-text)

; --- types -------------------------------------------------------------------

(def %sql-2^7 128)
(def %sql-2^15 32768)
(def %sql-2^31 2147483648)
(def %sql-2^63 (* %sql-2^31 %sql-2^31 2))
(def %sql-2^127 (* %sql-2^63 %sql-2^63 2))

(def %sql-2^8 256)
(def %sql-2^16 65536)
(def %sql-2^32 (* %sql-2^31 2))
(def %sql-2^64 (* %sql-2^63 2))
(def %sql-2^128 (* %sql-2^127 2))

; An integer type, one past its greatest value, its name in an error, the
; width of the DECIMAL that holds it, and its least value.  The signed
; types come first, narrowest first, then the unsigned.
(def %sql-int-rows
  (list (list (lit tinyint) %sql-2^7 "INT8" 3 (- 0 %sql-2^7))
        (list (lit smallint) %sql-2^15 "INT16" 5 (- 0 %sql-2^15))
        (list (lit integer) %sql-2^31 "INT32" 10 (- 0 %sql-2^31))
        (list (lit bigint) %sql-2^63 "INT64" 19 (- 0 %sql-2^63))
        (list (lit hugeint) %sql-2^127 "INT128" 38 (- 0 %sql-2^127))
        (list (lit utinyint) %sql-2^8 "UINT8" 3 0)
        (list (lit usmallint) %sql-2^16 "UINT16" 5 0)
        (list (lit uinteger) %sql-2^32 "UINT32" 10 0)
        (list (lit ubigint) %sql-2^64 "UINT64" 20 0)
        (list (lit uhugeint) %sql-2^128 "UINT128" 39 0)))

; A type, its SQL name, and the name a result's heading shows
(def %sql-type-rows
  (list (list (lit tinyint) "TINYINT" "int8")
        (list (lit smallint) "SMALLINT" "int16")
        (list (lit real) "FLOAT" "float")
        (list (lit integer) "INTEGER" "int32")
        (list (lit bigint) "BIGINT" "int64")
        (list (lit hugeint) "HUGEINT" "int128")
        (list (lit utinyint) "UTINYINT" "uint8")
        (list (lit usmallint) "USMALLINT" "uint16")
        (list (lit uinteger) "UINTEGER" "uint32")
        (list (lit ubigint) "UBIGINT" "uint64")
        (list (lit uhugeint) "UHUGEINT" "uint128")
        (list (lit double) "DOUBLE" "double")
        (list (lit varchar) "VARCHAR" "varchar")
        (list (lit boolean) "BOOLEAN" "boolean")
        (list (lit date) "DATE" "date")
        (list (lit time) "TIME" "time")
        (list (lit timestamp) "TIMESTAMP" "timestamp")
        (list (lit interval) "INTERVAL" "interval")
        (list (lit null) "NULL" "\"null\"")))

(def %sql-row
  (fn (_ key rows) (List find (fn (_ r) (eq? (first r) key)) rows)))

(def %sql-int? (fn (_ t) (not (null? (%sql-row t %sql-int-rows)))))
(def %sql-limit (fn (_ t) (List second (%sql-row t %sql-int-rows))))
(def %sql-int-name (fn (_ t) (List third (%sql-row t %sql-int-rows))))
(def %sql-least (fn (_ t) (List ref 4 (%sql-row t %sql-int-rows))))
(def %sql-unsigned? (fn (_ t) (= (%sql-least t) 0)))

(def %sql-decimal? (fn (_ t) (pair? t)))
(def %sql-double? (fn (_ t) (eq? t (lit double))))
(def %sql-real? (fn (_ t) (eq? t (lit real))))

; A binary float: a DOUBLE, or a REAL, which is held as the double equal
; to it
(def %sql-float? (fn (_ t) (or (eq? t (lit double)) (eq? t (lit real)))))
(def %sql-null-type? (fn (_ t) (eq? t (lit null))))
(def %sql-numeric?
  (fn (_ t) (or (%sql-int? t) (%sql-decimal? t) (%sql-float? t))))

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
(def sql-type-name %sql-type-name)

(def %sql-fits?
  (fn (_ t n) (and (< n (%sql-limit t)) (>= n (%sql-least t)))))

; The types an integer constant may have, narrowest first: INTEGER and the
; wider signed ones, and UHUGEINT past them
(def %sql-constant-types
  (list (lit integer) (lit bigint) (lit hugeint) (lit uhugeint)))

; The narrowest type an integer constant N has
(def %sql-int-type
  (fn (_ n)
    (let ((t (List find (fn (_ t) (%sql-fits? t n)) %sql-constant-types)))
      (if (null? t)
        (error (Str8 str "Not implemented Error: the integer " n
                         " is wider than UHUGEINT"))
        t))))

; Every value of the integer type B is one of A
(def %sql-holds?
  (fn (_ a b)
    (and (>= (%sql-limit a) (%sql-limit b)) (<= (%sql-least a) (%sql-least b)))))

; The first of TYPES that holds both A and B, or nil
(def %sql-holding
  (fn (_ a b types)
    (List find (fn (_ t) (and (%sql-holds? t a) (%sql-holds? t b))) types)))

; The type arithmetic on the integer types A and B answers: the one that
; holds the other; when neither does, a signed with an unsigned, a BIGINT,
; or a HUGEINT, whichever holds both, and a DOUBLE when none does.  It is
; what DuckDB picks.
(def %sql-arith-wider
  (fn (_ a b)
    (match
      ((%sql-holds? a b) a)
      ((%sql-holds? b a) b)
      (#t (let ((t (%sql-holding a b (list (lit bigint) (lit hugeint)))))
            (if (null? t) (lit double) t))))))

(def %sql-signed-types
  (list (lit tinyint) (lit smallint) (lit integer) (lit bigint) (lit hugeint)))

; The type several values of the integer types A and B take: the one that
; holds the other, else the narrowest signed type that holds both, and a
; HUGEINT when none does
(def %sql-wider
  (fn (_ a b)
    (match
      ((%sql-holds? a b) a)
      ((%sql-holds? b a) b)
      (#t (let ((t (%sql-holding a b %sql-signed-types)))
            (if (null? t) (lit hugeint) t))))))

; A value as a result shows it
(def sql-value-text
  (fn (_ v)
    (let ((t (first v)) (x (rest v)))
      (match
        ((null? x) "NULL")
        ((eq? t (lit boolean)) (if x "true" "false"))
        ((eq? t (lit varchar)) x)
        ((%sql-double? t) (sql-double-text x))
        ((%sql-real? t) (sql-real-text x))
        ((eq? t (lit date)) (sql-date-text x))
        ((eq? t (lit timestamp)) (sql-timestamp-text x))
        ((eq? t (lit time)) (sql-clock-text x))
        ((eq? t (lit interval)) (sql-interval-text x))
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
        ((%sql-float? t) x)
        ((%sql-decimal? t)
          (sql-double-of (sql-decimal-text x (+ (List second t) 1) (List third t))))
        ((and (< x %sql-2^53) (> x (- 0 %sql-2^53))) (Float from x))
        (#t (sql-double-of (Str8 str x)))))))

; --- one type for several ---------------------------------------------------

; The type values of TYPES all go into: the one they share; for numbers a
; double when any is one, else a decimal wide enough for every whole part
; and scale, else the widest integer.  A NULL constant's type does not
; count, and is the answer when there is no other.
(def sql-common-type
  (fn (_ types)
    (let ((known (List reject %sql-null-type? types)))
      (match
        ((null? known) (lit null))
        ((List all? (fn (_ t) (equal? t (first known))) known) (first known))
        ((not (List all? %sql-numeric? known))
          (let ((other (List find (fn (_ t) (not (equal? t (first known)))) known)))
            (error (Str8 str "Binder Error: Cannot mix values of type "
                             (%sql-type-name (first known)) " and "
                             (%sql-type-name other)
                             " - an explicit cast is required"))))
        ((List any? %sql-double? known) (lit double))
        ((List any? %sql-real? known) (lit real))
        ((List any? %sql-decimal? known)
          (let ((shapes (List map %sql-shape known)))
            (let ((scale (List fold (fn (_ acc s) (%sql-max acc (List second s))) 0 shapes))
                  (whole (List fold (fn (_ acc s) (%sql-max acc (- (first s) (List second s)))) 0 shapes)))
              (list (lit decimal) (%sql-min %sql-decimal-width (+ whole scale)) scale))))
        (#t (List fold %sql-wider (first known) (rest known)))))))

; V as a value of the type T
(def %sql-as (fn (_ v t) (pair t (sql-cast v t))))

; --- arithmetic --------------------------------------------------------------

; The type of integer arithmetic: the wider operand's.  A NULL constant
; takes the other operand's type, and two of them are a BIGINT, as DuckDB
; has it.
(def %sql-arith-type
  (fn (_ sign a b)
    (let ((ta (first a)) (tb (first b)))
      (match
        ((and (%sql-int? ta) (%sql-int? tb)) (%sql-arith-wider ta tb))
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
      (match
        ((%sql-double? t) (%sql-double-arith f a b))
        ((or (%sql-null? a) (%sql-null? b)) (pair t ()))
        (#t (%sql-checked t (f (rest a) (rest b)) word sign a b))))))

; A double: both operands as doubles.  An overflow is an infinity.
(def %sql-double-arith
  (fn (_ f a b)
    (pair (lit double)
      (if (or (%sql-null? a) (%sql-null? b)) ()
        (f (%sql-as-double a) (%sql-as-double b))))))

; A number as the REAL nearest it
(def %sql-as-real (fn (_ v) (sql-real-of (%sql-as-double v))))

; A REAL: both operands as REALs, and the answer the REAL nearest
(def %sql-real-arith
  (fn (_ f a b)
    (pair (lit real)
      (if (or (%sql-null? a) (%sql-null? b)) ()
        (sql-real-of (f (%sql-as-real a) (%sql-as-real b)))))))

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

; --- dates and times in arithmetic --------------------------------------------

(def %sql-temporal-types (list (lit date) (lit time) (lit timestamp) (lit interval)))
(def %sql-temporal? (fn (_ t) (List includes? t %sql-temporal-types)))

; A date or a timestamp as a moment, in microseconds
(def %sql-moment
  (fn (_ v) (if (eq? (first v) (lit date)) (* (rest v) sql-micros-day) (rest v))))

(def %sql-moment-type?
  (fn (_ t) (or (eq? t (lit date)) (eq? t (lit timestamp)))))

; T, or NULL of it when either operand is NULL, else what COMPUTE answers
(def %sql-unless-null
  (fn (_ t a b compute)
    (pair t (if (or (%sql-null? a) (%sql-null? b)) () (compute)))))

; + and - where a date, a time, a timestamp or an interval is an operand,
; and * of an interval by an integer.  A date and a count of days is a
; date; two dates apart are days; a date or a timestamp and an interval is
; a timestamp; two moments apart are an interval; a time and an interval
; is a time, on the clock of one day.
(def %sql-temporal-arith
  (fn (_ sign a b)
    (let ((ta (first a)) (tb (first b)) (plus (str=? sign "+")) (minus (str=? sign "-")))
      (match
        ((and (eq? ta (lit date)) (%sql-int? tb) (or plus minus))
          (%sql-unless-null (lit date) a b
            (fn (_) (if plus (+ (rest a) (rest b)) (- (rest a) (rest b))))))
        ((and (%sql-int? ta) (eq? tb (lit date)) plus)
          (%sql-unless-null (lit date) a b (fn (_) (+ (rest a) (rest b)))))
        ((and (eq? ta (lit date)) (eq? tb (lit date)) minus)
          (%sql-unless-null (lit bigint) a b (fn (_) (- (rest a) (rest b)))))
        ((and (%sql-moment-type? ta) (eq? tb (lit interval)) (or plus minus))
          (%sql-unless-null (lit timestamp) a b
            (fn (_) (sql-timestamp-plus (%sql-moment a)
                      (if plus (rest b) (sql-interval-negated (rest b)))))))
        ((and (eq? ta (lit interval)) (%sql-moment-type? tb) plus)
          (%sql-unless-null (lit timestamp) a b
            (fn (_) (sql-timestamp-plus (%sql-moment b) (rest a)))))
        ((and (%sql-moment-type? ta) (%sql-moment-type? tb) minus)
          (%sql-unless-null (lit interval) a b
            (fn (_) (sql-micros-interval (- (%sql-moment a) (%sql-moment b))))))
        ((and (eq? ta (lit time)) (eq? tb (lit interval)) (or plus minus))
          (%sql-unless-null (lit time) a b
            (fn (_) (sql-floor-mod
                      (if plus (+ (rest a) (List third (rest b))) (- (rest a) (List third (rest b))))
                      sql-micros-day))))
        ((and (eq? ta (lit interval)) (eq? tb (lit interval)) (or plus minus))
          (%sql-unless-null (lit interval) a b
            (fn (_) (sql-interval-add (rest a)
                      (if plus (rest b) (sql-interval-negated (rest b)))))))
        ((and (eq? ta (lit interval)) (%sql-int? tb) (str=? sign "*"))
          (%sql-unless-null (lit interval) a b (fn (_) (sql-interval-times (rest a) (rest b)))))
        ((and (%sql-int? ta) (eq? tb (lit interval)) (str=? sign "*"))
          (%sql-unless-null (lit interval) a b (fn (_) (sql-interval-times (rest b) (rest a)))))
        (#t
          (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                           sign "(" (%sql-type-name ta) ", " (%sql-type-name tb) ")'.")))))))

; + - or *: integers in the wider type, a double when either is one, a
; REAL when either is one and neither a double, and exactly as a decimal
; otherwise
(def %sql-arith
  (fn (_ sign word f a b)
    (let ((ta (first a)) (tb (first b)))
      (match
        ((or (%sql-temporal? ta) (%sql-temporal? tb)) (%sql-temporal-arith sign a b))
        ((not (and (%sql-numeric-or-null? ta) (%sql-numeric-or-null? tb)))
          (%sql-arith-type sign a b))
        ((or (%sql-double? ta) (%sql-double? tb)) (%sql-double-arith f a b))
        ((or (%sql-real? ta) (%sql-real? tb)) (%sql-real-arith f a b))
        ((or (%sql-decimal? ta) (%sql-decimal? tb))
          (%sql-decimal-arith sign word f a b))
        (#t (%sql-integer-arith sign word f a b))))))

; // or %: integers only
(def %sql-divide
  (fn (_ sign f a b name)
    (when (or (%sql-float? (first a)) (%sql-float? (first b))
              (%sql-decimal? (first a)) (%sql-decimal? (first b)))
      (error (Str8 str "Not implemented Error: " sign " on a number that is not an integer")))
    (let ((t (%sql-arith-type sign a b)))
      (match
        ((%sql-double? t)
          (error (Str8 str "Not implemented Error: " sign " on a UHUGEINT and a signed integer")))
        ((or (%sql-null? a) (%sql-null? b)) (pair t ()))
        ((= (rest b) 0)
          (error (Str8 str "Invalid Input Error: Division by zero in expression "
                           name ".")))
        (#t (%sql-checked t (f (rest a) (rest b)) "division" sign a b))))))

; /: a double, or a REAL when either is one and neither a double
(def %sql-quotient
  (fn (_ a b)
    (match
      ((not (and (%sql-numeric-or-null? (first a)) (%sql-numeric-or-null? (first b))))
        (%sql-arith-type "/" a b))
      ((or (%sql-double? (first a)) (%sql-double? (first b))) (%sql-double-arith / a b))
      ((or (%sql-real? (first a)) (%sql-real? (first b))) (%sql-real-arith / a b))
      (#t (%sql-double-arith / a b)))))

; --- comparison --------------------------------------------------------------

; -1, 0 or 1: how two values of one family stand
(def %sql-order
  (fn (_ a b)
    (let ((ta (first a)) (tb (first b)) (x (rest a)) (y (rest b)))
      (match
        ((and (%sql-int? ta) (%sql-int? tb))
          (if (< x y) -1 (if (= x y) 0 1)))
        ((and (%sql-numeric? ta) (%sql-numeric? tb))
          (if (or (%sql-float? ta) (%sql-float? tb))
            (let ((as (if (or (%sql-double? ta) (%sql-double? tb)) %sql-as-double %sql-as-real)))
              (let ((fx (as a)) (fy (as b)))
                (if (< fx fy) -1 (if (= fx fy) 0 1))))
            (let ((scale (%sql-max (List second (%sql-shape ta))
                                   (List second (%sql-shape tb)))))
              (let ((sx (sql-rescale x (List second (%sql-shape ta)) scale))
                    (sy (sql-rescale y (List second (%sql-shape tb)) scale)))
                (if (< sx sy) -1 (if (= sx sy) 0 1))))))
        ((and (eq? ta (lit varchar)) (eq? tb (lit varchar)))
          (if (Str8 <? x y) -1 (if (Str8 =? x y) 0 1)))
        ((and (%sql-temporal? ta) (eq? tb (lit varchar))) (%sql-order a (%sql-as b ta)))
        ((and (eq? ta (lit varchar)) (%sql-temporal? tb)) (%sql-order (%sql-as a tb) b))
        ((and (%sql-moment-type? ta) (%sql-moment-type? tb))
          (let ((mx (%sql-moment a)) (my (%sql-moment b)))
            (if (< mx my) -1 (if (= mx my) 0 1))))
        ((and (eq? ta (lit time)) (eq? tb (lit time)))
          (if (< x y) -1 (if (= x y) 0 1)))
        ((and (eq? ta (lit interval)) (eq? tb (lit interval)))
          (let ((mx (sql-interval-micros x)) (my (sql-interval-micros y)))
            (if (< mx my) -1 (if (= mx my) 0 1))))
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

; --- pieces the expressions share --------------------------------------------

; Two truths, each #t, #f or nil for NULL, as AND joins them
(def %sql-both
  (fn (_ a b)
    (match
      ((or (eq? a #f) (eq? b #f)) #f)
      ((or (null? a) (null? b)) ())
      (#t #t))))

; The type E has in SCOPE, found over a row of NULLs so that nothing a row
; holds is computed; nil when even that cannot be computed
(def %sql-type-in
  (fn (_ e scope)
    (guard (_ (lit null))
      (first (sql-eval e
               (if (null? scope) ()
                 (list (first scope)
                       (List repeat (List length (first scope)) ())
                       (List third scope)
                       (%sql-fourth scope))))))))

; --- LIKE --------------------------------------------------------------------

(def %sql-byte (fn (_ s i) (Char ->int (Str8 ref i s))))

; How many bytes the character starting with byte B takes in UTF-8
(def %sql-char-bytes
  (fn (_ b)
    (match ((< b 192) 1) ((< b 224) 2) ((< b 240) 3) (#t 4))))

; The bytes % and _ of a pattern
(def %sql-like-any 37)
(def %sql-like-one 95)

; S from I matches the pattern P from J: % is any run of characters, _ any
; one character
(def %sql-like?
  (fn (self s i p j)
    (let ((n (Str8 length s)) (m (Str8 length p)))
      (match
        ((>= j m) (>= i n))
        ((= (%sql-byte p j) %sql-like-any)
          (if (self s i p (+ j 1)) #t
            (if (>= i n) #f (self s (+ i 1) p j))))
        ((>= i n) #f)
        ((= (%sql-byte p j) %sql-like-one)
          (self s (+ i (%sql-char-bytes (%sql-byte s i))) p (+ j 1)))
        ((= (%sql-byte p j) (%sql-byte s i)) (self s (+ i 1) p (+ j 1)))
        (#t #f)))))

; --- functions ---------------------------------------------------------------

(def %sql-no-match
  (fn (_ name args)
    (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                     name "(" (Str8 join ", " (List map (fn (_ a) (%sql-type-name (first a))) args))
                     ")'."))))

; ARGS are COUNT values, or the function has no such form
(def %sql-arity
  (fn (_ name args counts)
    (unless (List includes? (List length args) counts) (%sql-no-match name args))))

; ARGS are all text or NULL constants, or the function has no such form
(def %sql-texts
  (fn (_ name args)
    (unless (List all? (fn (_ a) (or (eq? (first a) (lit varchar)) (%sql-null-type? (first a)))) args)
      (%sql-no-match name args))))

(def %sql-any-null? (fn (_ args) (List any? %sql-null? args)))

; A function of text answering text: NAME's ARGS checked, NULL for a NULL
; argument, else F of the argument texts
(def %sql-text-function
  (fn (_ name args counts f)
    (%sql-arity name args counts)
    (%sql-texts name args)
    (pair (lit varchar)
      (if (%sql-any-null? args) () (f (List map rest args))))))

; The integer an argument is, for a count or a place
(def %sql-count-arg
  (fn (_ name args v)
    (unless (or (%sql-int? (first v)) (%sql-null-type? (first v))) (%sql-no-match name args))
    (rest v)))

; LEN characters of TEXT from the START-th, counted from 1 as SQL counts; a
; start before the text takes from its length, and one below zero counts
; from the end
(def %sql-substring
  (fn (_ text start len)
    (let ((n (Str length text)))
      (let ((from (if (< start 0) (%sql-max 0 (+ n start)) (- start 1))))
        (let ((begin (%sql-max 0 from))
              (end (if (null? len) n (%sql-min n (+ from len)))))
          (if (> end begin) (Str sub begin (- end begin) text) ""))))))

; A number's value as its own type under F, which takes an exact integer
; or a float; NULL for NULL
(def %sql-numeric-function
  (fn (_ name args exact inexact)
    (%sql-arity name args (list 1))
    (let ((v (first args)))
      (match
        ((%sql-null-type? (first v)) (pair (lit bigint) ()))
        ((not (%sql-numeric? (first v))) (%sql-no-match name args))
        ((%sql-null? v) v)
        ((%sql-double? (first v)) (pair (lit double) (inexact (rest v))))
        ((%sql-real? (first v)) (pair (lit real) (sql-real-of (inexact (rest v)))))
        (#t (exact v))))))

; A decimal with its digits after the point dropped: FLOOR rounds toward
; the least, CEIL toward the greatest, ROUND a half away from zero.  The
; result has room for a carry.
(def %sql-whole
  (fn (_ v round)
    (let ((t (first v)))
      (if (%sql-int? t) v
        (let ((unit (sql-pow10 (List third t))))
          (pair (list (lit decimal) (+ (- (List second t) (List third t)) 1) 0)
                (round (rest v) unit)))))))

(def %sql-floor-div
  (fn (_ n unit)
    (let ((q (Num quotient n unit)))
      (if (and (< n 0) (not (= (* q unit) n))) (- q 1) q))))

; %sql-numeric-function, but that an integer's NULL is a DOUBLE's: the
; type FLOOR and CEIL answer for an integer
(def %sql-double-for-integer
  (fn (_ name args exact inexact)
    (let ((r (%sql-numeric-function name args exact inexact)))
      (if (and (%sql-int? (first r)) (%sql-null? r)) (pair (lit double) ()) r))))

; FLOOR and CEIL of an integer are a DOUBLE, as DuckDB has them; of a
; decimal, the decimal %sql-whole answers
(def %sql-whole-or-double
  (fn (_ v round)
    (if (%sql-int? (first v)) (pair (lit double) (%sql-as-double v))
      (%sql-whole v round))))

; --- the parts of a date and a time ------------------------------------------

; A date or a timestamp as (YEAR MONTH DAY WEEKDAY)
(def %sql-civil-of
  (fn (_ v) (sql-civil (sql-floor-div (%sql-moment v) sql-micros-day))))

; The time of day of V, or of an interval its time, in microseconds; a
; date has none
(def %sql-clock-of
  (fn (_ v)
    (match
      ((eq? (first v) (lit date)) 0)
      ((eq? (first v) (lit interval)) (List third (rest v)))
      (#t (sql-floor-mod (rest v) sql-micros-day)))))

; ARGS are dates or timestamps, or NULL constants, or NAME has no such form
(def %sql-moments
  (fn (_ name all args)
    (unless (List all? (fn (_ a) (or (%sql-moment-type? (first a)) (%sql-null-type? (first a)))) args)
      (%sql-no-match name all))))

; A part of a date, a time, a timestamp or an interval: a static method a
; part's name, of a value that is not NULL
(def-class SqlPart ()
  (static
    (method year (self v)
      (if (eq? (first v) (lit interval)) (Num quotient (first (rest v)) 12)
        (first (%sql-civil-of v))))
    (method month (self v)
      (if (eq? (first v) (lit interval)) (Num remainder (first (rest v)) 12)
        (List second (%sql-civil-of v))))
    (method day (self v)
      (if (eq? (first v) (lit interval)) (List second (rest v))
        (List third (%sql-civil-of v))))
    (method hour (self v) (Num quotient (%sql-clock-of v) sql-micros-hour))
    (method minute (self v)
      (Num remainder (Num quotient (%sql-clock-of v) sql-micros-minute) 60))
    (method second (self v)
      (Num remainder (Num quotient (%sql-clock-of v) sql-micros-second) 60))
    (method dayofweek (self v) (List ref 3 (%sql-civil-of v)))
    (method dow (self v) (SqlPart dayofweek v))
    (method dayofyear (self v)
      (sql-day-of-year (sql-floor-div (%sql-moment v) sql-micros-day)))
    (method doy (self v) (SqlPart dayofyear v))
    (method quarter (self v) (+ (Num quotient (- (List second (%sql-civil-of v)) 1) 3) 1))))

; The part NAME names of the one value of ARGS, a BIGINT
(def %sql-part
  (fn (_ name args)
    (%sql-arity name args (list 1))
    (let ((v (first args)) (part (class-static-ref SqlPart (Str8 ->sym (sql-lower name)))))
      (when (null? part)
        (error (Str8 append "Conversion Error: extract specifier \"" name "\" not recognized")))
      (unless (or (%sql-temporal? (first v)) (%sql-null-type? (first v)))
        (%sql-no-match (sql-lower name) args))
      (when (and (eq? (first v) (lit time))
                 (not (List includes? (sql-lower name) (list "hour" "minute" "second"))))
        (%sql-no-match (sql-lower name) args))
      (pair (lit bigint) (if (%sql-null? v) () (part SqlPart v))))))

(def %sql-two (fn (_ n) (Str8 pad-left 2 #\0 (Str8 str n))))

; What a letter after % stands for in a format, for the moment MICROS;
; nil for a letter that stands for nothing here
(def %sql-directive
  (fn (_ letter micros)
    (let ((civil (sql-civil (sql-floor-div micros sql-micros-day)))
          (clock (sql-floor-mod micros sql-micros-day)))
      (match
        ((= letter 89) (Str8 str (first civil)))                                   ; Y
        ((= letter 121) (%sql-two (Num remainder (first civil) 100)))              ; y
        ((= letter 109) (%sql-two (List second civil)))                            ; m
        ((= letter 100) (%sql-two (List third civil)))                             ; d
        ((= letter 72) (%sql-two (Num quotient clock sql-micros-hour)))            ; H
        ((= letter 77) (%sql-two (Num remainder (Num quotient clock sql-micros-minute) 60)))  ; M
        ((= letter 83) (%sql-two (Num remainder (Num quotient clock sql-micros-second) 60)))  ; S
        ((= letter 66) (List ref (- (List second civil) 1) sql-month-names))       ; B
        ((= letter 98) (Str8 sub 0 3 (List ref (- (List second civil) 1) sql-month-names)))   ; b
        ((= letter 65) (List ref (List ref 3 civil) sql-day-names))                ; A
        ((= letter 97) (Str8 sub 0 3 (List ref (List ref 3 civil) sql-day-names))) ; a
        ((= letter 106)                                                            ; j
          (Str8 pad-left 3 #\0 (Str8 str (sql-day-of-year (sql-floor-div micros sql-micros-day)))))
        ((= letter 37) "%")
        (#t ())))))

; FORMAT from I with each % and its letter replaced for the moment MICROS
(def %sql-strftime
  (fn (self format i micros)
    (let ((at (Str8 index-of "%" (Str8 sub i (Str8 length format) format))))
      (if (or (null? at) (>= (+ i at 1) (Str8 length format)))
        (Str8 sub i (Str8 length format) format)
        (let ((text (%sql-directive (%sql-byte format (+ i at 1)) micros)))
          (when (null? text)
            (error (Str8 append "Invalid Input Error: Failed to parse format specifier "
                                format ": Unrecognized format for strftime/strptime: %"
                                (Str8 sub (+ i at 1) 1 format))))
          (Str8 append (Str8 sub i at format) text
                       (self format (+ i at 2) micros)))))))

; The functions of one row's values.  A function is a static method named
; in lower case, taking its arguments' values and its node.
(def-class SqlFunction ()
  (static
    (method lower (self args node)
      (%sql-text-function "lower" args (list 1) (fn (_ t) (Str8 downcase (first t)))))
    (method upper (self args node)
      (%sql-text-function "upper" args (list 1) (fn (_ t) (Str8 upcase (first t)))))
    (method trim (self args node)
      (%sql-text-function "trim" args (list 1) (fn (_ t) (Str8 trim (first t)))))
    (method ltrim (self args node)
      (%sql-text-function "ltrim" args (list 1) (fn (_ t) (Str8 trim-left (first t)))))
    (method rtrim (self args node)
      (%sql-text-function "rtrim" args (list 1) (fn (_ t) (Str8 trim-right (first t)))))
    (method reverse (self args node)
      (%sql-text-function "reverse" args (list 1) (fn (_ t) (Str reverse (first t)))))
    (method replace (self args node)
      (%sql-text-function "replace" args (list 3)
        (fn (_ t)
          (if (= (Str8 length (List second t)) 0) (first t)
            (Str8 replace (List second t) (List third t) (first t))))))
    (method length (self args node)
      (%sql-arity "length" args (list 1))
      (%sql-texts "length" args)
      (pair (lit bigint) (if (%sql-any-null? args) () (Str length (rest (first args))))))
    (method starts_with (self args node)
      (%sql-arity "starts_with" args (list 2))
      (%sql-texts "starts_with" args)
      (pair (lit boolean)
        (if (%sql-any-null? args) ()
          (Str8 starts? (rest (List second args)) (rest (first args))))))
    (method contains (self args node)
      (%sql-arity "contains" args (list 2))
      (%sql-texts "contains" args)
      (pair (lit boolean)
        (if (%sql-any-null? args) ()
          (Str8 includes? (rest (List second args)) (rest (first args))))))
    ; Every argument as a result shows it, the NULLs left out
    (method concat (self args node)
      (when (null? args) (%sql-no-match "concat" args))
      (pair (lit varchar)
        (Str8 join "" (List map sql-value-text (List reject %sql-null? args)))))
    (method substring (self args node)
      (%sql-arity "substring" args (list 2 3))
      (%sql-texts "substring" (list (first args)))
      (let ((start (%sql-count-arg "substring" args (List second args)))
            (len (if (null? (rest (rest args))) 0
                   (%sql-count-arg "substring" args (List third args)))))
        (pair (lit varchar)
          (if (%sql-any-null? args) ()
            (%sql-substring (rest (first args)) start
                            (if (null? (rest (rest args))) () len))))))
    (method substr (self args node) (SqlFunction substring args node))
    (method left (self args node)
      (%sql-arity "left" args (list 2))
      (%sql-texts "left" (list (first args)))
      (let ((n (%sql-count-arg "left" args (List second args))))
        (pair (lit varchar)
          (if (%sql-any-null? args) ()
            (let ((text (rest (first args))))
              (Str sub 0 (if (< n 0) (%sql-max 0 (+ (Str length text) n)) n) text))))))
    (method right (self args node)
      (%sql-arity "right" args (list 2))
      (%sql-texts "right" (list (first args)))
      (let ((n (%sql-count-arg "right" args (List second args))))
        (pair (lit varchar)
          (if (%sql-any-null? args) ()
            (let ((text (rest (first args))))
              (let ((size (Str length text)))
                (let ((take (%sql-min size (if (< n 0) (%sql-max 0 (+ size n)) n))))
                  (Str sub (- size take) take text))))))))
    (method repeat (self args node)
      (%sql-arity "repeat" args (list 2))
      (%sql-texts "repeat" (list (first args)))
      (let ((n (%sql-count-arg "repeat" args (List second args))))
        (pair (lit varchar)
          (if (%sql-any-null? args) () (Str8 repeat n (rest (first args)))))))
    (method abs (self args node)
      (%sql-numeric-function "abs" args
        (fn (_ v)
          (if (>= (rest v) 0) v
            (match
              ((not (%sql-int? (first v))) (pair (first v) (- 0 (rest v))))
              ((%sql-fits? (first v) (- 0 (rest v))) (pair (first v) (- 0 (rest v))))
              (#t (error (Str8 str "Out of Range Error: Overflow on abs(" (rest v) ")"))))))
        (fn (_ x) (Float abs x))))
    (method floor (self args node)
      (%sql-double-for-integer "floor" args
        (fn (_ v) (%sql-whole-or-double v %sql-floor-div))
        (fn (_ x) (Float floor x))))
    (method ceil (self args node)
      (%sql-double-for-integer "ceil" args
        (fn (_ v)
          (%sql-whole-or-double v (fn (_ n unit) (- 0 (%sql-floor-div (- 0 n) unit)))))
        (fn (_ x) (Float ceil x))))
    (method ceiling (self args node) (SqlFunction ceil args node))
    (method round (self args node)
      (%sql-numeric-function "round" args
        (fn (_ v)
          (%sql-whole v
            (fn (_ n unit)
              (let ((r (Num quotient (+ (* 2 (if (< n 0) (- 0 n) n)) unit) (* 2 unit))))
                (if (< n 0) (- 0 r) r)))))
        (fn (_ x) (Float round x))))
    (method sqrt (self args node)
      (%sql-arity "sqrt" args (list 1))
      (unless (%sql-numeric-or-null? (first (first args))) (%sql-no-match "sqrt" args))
      (pair (lit double)
        (if (%sql-any-null? args) ()
          (Float sqrt (%sql-as-double (first args))))))
    (method power (self args node)
      (%sql-arity "power" args (list 2))
      (unless (List all? (fn (_ a) (%sql-numeric-or-null? (first a))) args)
        (%sql-no-match "power" args))
      (pair (lit double)
        (if (%sql-any-null? args) ()
          (Float pow (%sql-as-double (first args)) (%sql-as-double (List second args))))))
    (method pow (self args node) (SqlFunction power args node))
    ; The first argument that is not NULL, in the type they all go into
    (method coalesce (self args node)
      (when (null? args) (%sql-no-match "coalesce" args))
      (let ((t (sql-common-type (List map first args)))
            (found (List find (fn (_ a) (not (%sql-null? a))) args)))
        (if (null? found) (pair t ()) (%sql-as found t))))
    (method ifnull (self args node)
      (%sql-arity "ifnull" args (list 2))
      (SqlFunction coalesce args node))
    (method nullif (self args node)
      (%sql-arity "nullif" args (list 2))
      (let ((a (first args)) (b (List second args)))
        (if (and (not (%sql-null? a)) (not (%sql-null? b)) (= (%sql-order a b) 0))
          (pair (first a) ())
          a)))
    (method greatest (self args node) (%sql-extreme-of "greatest" args (fn (_ c) (> c 0))))
    (method least (self args node) (%sql-extreme-of "least" args (fn (_ c) (< c 0))))
    (method year (self args node) (%sql-part "year" args))
    (method month (self args node) (%sql-part "month" args))
    (method day (self args node) (%sql-part "day" args))
    (method hour (self args node) (%sql-part "hour" args))
    (method minute (self args node) (%sql-part "minute" args))
    (method second (self args node) (%sql-part "second" args))
    (method dayofweek (self args node) (%sql-part "dayofweek" args))
    (method dayofyear (self args node) (%sql-part "dayofyear" args))
    (method quarter (self args node) (%sql-part "quarter" args))
    (method date_part (self args node)
      (%sql-arity "date_part" args (list 2))
      (%sql-texts "date_part" (list (first args)))
      (if (%sql-null? (first args)) (pair (lit bigint) ())
        (%sql-part (rest (first args)) (rest args))))
    ; The start of the unit a moment is in: a timestamp, whatever was given
    (method date_trunc (self args node)
      (%sql-arity "date_trunc" args (list 2))
      (%sql-texts "date_trunc" (list (first args)))
      (%sql-moments "date_trunc" args (rest args))
      (pair (lit timestamp)
        (if (%sql-any-null? args) ()
          (sql-moment-trunc (rest (first args)) (%sql-moment (List second args))))))
    ; How many of a unit begin between two moments
    (method date_diff (self args node)
      (%sql-arity "date_diff" args (list 3))
      (%sql-texts "date_diff" (list (first args)))
      (%sql-moments "date_diff" args (rest args))
      (pair (lit bigint)
        (if (%sql-any-null? args) ()
          (sql-moment-diff (rest (first args)) (%sql-moment (List second args))
                           (%sql-moment (List third args))))))
    (method datediff (self args node) (SqlFunction date_diff args node))
    (method dayname (self args node)
      (%sql-arity "dayname" args (list 1))
      (%sql-moments "dayname" args args)
      (pair (lit varchar)
        (if (%sql-any-null? args) ()
          (List ref (List ref 3 (%sql-civil-of (first args))) sql-day-names))))
    (method monthname (self args node)
      (%sql-arity "monthname" args (list 1))
      (%sql-moments "monthname" args args)
      (pair (lit varchar)
        (if (%sql-any-null? args) ()
          (List ref (- (List second (%sql-civil-of (first args))) 1) sql-month-names))))
    (method last_day (self args node)
      (%sql-arity "last_day" args (list 1))
      (%sql-moments "last_day" args args)
      (pair (lit date)
        (if (%sql-any-null? args) ()
          (let ((civil (%sql-civil-of (first args))))
            (sql-days (first civil) (List second civil)
                      (sql-month-days (first civil) (List second civil)))))))
    (method make_date (self args node)
      (%sql-arity "make_date" args (list 3))
      (unless (List all? (fn (_ a) (or (%sql-int? (first a)) (%sql-null-type? (first a)))) args)
        (%sql-no-match "make_date" args))
      (pair (lit date)
        (if (%sql-any-null? args) ()
          (let ((days (sql-days (rest (first args)) (rest (List second args))
                                (rest (List third args)))))
            (if (null? days)
              (error (Str8 str "Conversion Error: Date out of range: " (rest (first args)) "-"
                               (rest (List second args)) "-" (rest (List third args))))
              days)))))
    (method strftime (self args node)
      (%sql-arity "strftime" args (list 2))
      (%sql-moments "strftime" args (list (first args)))
      (%sql-texts "strftime" (rest args))
      (pair (lit varchar)
        (if (%sql-any-null? args) ()
          (%sql-strftime (rest (List second args)) 0 (%sql-moment (first args))))))
    ; The clock's time, in UTC: there is no time zone here
    (method now (self args node)
      (%sql-arity "now" args (list 0))
      (pair (lit timestamp) (* (Sys now) sql-micros-second)))
    (method current_timestamp (self args node) (SqlFunction now args node))
    (method current_date (self args node)
      (%sql-arity "current_date" args (list 0))
      (pair (lit date) (sql-floor-div (* (Sys now) sql-micros-second) sql-micros-day)))
    (method today (self args node) (SqlFunction current_date args node))
    (method typeof (self args node)
      (%sql-arity "typeof" args (list 1))
      (pair (lit varchar)
        (if (%sql-null-type? (first (first args))) "\"NULL\""
          (%sql-type-name (first (first args))))))))

; The least or greatest of ARGS, the NULLs left out, in the type they all
; go into
(def %sql-extreme-of
  (fn (_ name args pick)
    (when (null? args) (%sql-no-match name args))
    (let ((t (sql-common-type (List map first args)))
          (present (List reject %sql-null? args)))
      (if (null? present) (pair t ())
        (%sql-as (List fold (fn (_ best v) (if (pick (%sql-order v best)) v best))
                            (first present) (rest present))
                 t)))))

; --- expressions -------------------------------------------------------------

; NODE's value in SCOPE: nil where there is no FROM and no statement
; around this one, else (COLUMNS ROW GROUP OUTER).  COLUMNS is a list of
; columns and ROW their x values.  GROUP is nil for a row of the tables,
; and for a group of rows a one-element list holding the group's scopes,
; ROW then being the first of them, or NULLs when the group is empty.
; OUTER is the scope of the row a subquery is being answered for, nil at
; the top: a name no column here has is looked for there.
(def sql-scope (fn (_ columns row group outer) (list columns row group outer)))

; A scope has a fifth part once its statement's windows are answered: a
; list of (NODE . VALUE), an over node and what it is for this row
(def %sql-scope-windows
  (fn (_ scope)
    (let ((after (rest (rest (rest (rest scope))))))
      (if (null? after) () (first after)))))

; SCOPE with one more window answered, HELD its (NODE . VALUE)
(def sql-scope-windowed
  (fn (_ scope held)
    (list (first scope) (List second scope) (List third scope)
          (first (rest (rest (rest scope))))
          (pair held (%sql-scope-windows scope)))))

; A subquery is run by the executor, which reads this module and so cannot
; be read by it: the executor leaves its function here
(def %sql-hooks (Dict make))

(def sql-select-runner!
  (fn (_ run) (%sql-hooks set! (lit select) run)))

; A select statement's result, (NAMES TYPES ROWS), for the row of SCOPE
(def %sql-subresult
  (fn (_ stmt scope) ((%sql-hooks get (lit select)) stmt scope)))

; The one column of a subquery's result, as a list of values; its type
; comes first: (TYPE . VALUES)
(def %sql-subcolumn
  (fn (_ stmt scope)
    (let ((result (%sql-subresult stmt scope)))
      (unless (= (List length (first result)) 1)
        (error (Str8 str "Binder Error: Subquery returns " (List length (first result))
                         " columns - expected 1")))
      (pair (first (List second result)) (List map first (List third result))))))

; V IN the values AMONG, in three values
(def %sql-among
  (fn (_ v among)
    (pair (lit boolean)
      (match
        ((%sql-null? v) ())
        ((List any? (fn (_ a) (and (not (%sql-null? a)) (= (%sql-order v a) 0))) among) #t)
        ((List any? %sql-null? among) ())
        (#t #f)))))

(def sql-eval
  (fn (_ node scope)
    ((class-static-ref SqlNode (first node)) SqlNode node scope)))

(def sql-expr-name
  (fn (_ node) ((class-static-ref SqlName (first node)) SqlName node)))

; A column of a scope is (QUALIFIER NAME TYPE LOW-QUALIFIER LOW-NAME HIDDEN), and
; a col node (col NAME QUALIFIER LOW-NAME LOW-QUALIFIER): the names as
; written, for a heading or an error, and in lower case, folded once where
; the column and the node are made, so finding a column for a row
; compares strings as they are.
(def %sql-fourth (fn (_ l) (first (rest (rest (rest l))))))
(def %sql-fifth (fn (_ l) (first (rest (rest (rest (rest l)))))))

(def %sql-nth
  (fn (self l i) (if (= i 0) (first l) (self (rest l) (- i 1)))))

; A scope's column of a table under its qualifier
(def sql-column
  (fn (_ qualifier name type)
    (list qualifier name type (sql-lower qualifier) (sql-lower name) #f)))

; A column is hidden when a USING joined on it and the other side's column
; of that name stands for both: a name with no qualifier does not find it,
; and a star leaves it out.  Its qualified name still finds it.
(def sql-column-hidden?
  (fn (_ column) (first (rest (rest (rest (rest (rest column))))))))

(def sql-column-hide
  (fn (_ column)
    (list (first column) (List second column) (List third column)
          (%sql-fourth column) (%sql-fifth column) #t)))

; A col node for a name, QUALIFIER nil or a table's name
(def sql-column-node
  (fn (_ name qualifier)
    (list (lit col) name qualifier (sql-lower name)
          (if (null? qualifier) () (sql-lower qualifier)))))

; The places in COLUMNS, from I, of the columns a lower-case name names
; under a lower-case qualifier or nil
(def %sql-column-places
  (fn (self name qualifier columns i)
    (if (null? columns) ()
      (if (and (str=? (%sql-fifth (first columns)) name)
               (if (null? qualifier) (not (sql-column-hidden? (first columns)))
                 (str=? (%sql-fourth (first columns)) qualifier)))
        (pair i (self name qualifier (rest columns) (+ i 1)))
        (self name qualifier (rest columns) (+ i 1))))))

; The place in COLUMNS of the one column a col NODE names.  None, a table
; that is not there, and more than one are errors.
(def sql-column-index
  (fn (_ node columns)
    (let ((places (%sql-column-places (%sql-fourth node) (%sql-fifth node) columns 0)))
      (match
        ((and (not (null? places)) (null? (rest places))) (first places))
        ((and (null? places) (not (null? (%sql-fifth node)))
              (null? (List find (fn (_ c) (str=? (%sql-fourth c) (%sql-fifth node))) columns)))
          (error (Str8 str "Binder Error: Referenced table \"" (List third node)
                           "\" not found!")))
        ((null? places)
          (error (Str8 str "Binder Error: Referenced column \"" (List second node)
                           "\" not found in FROM clause!")))
        (#t
          (error (Str8 str "Binder Error: Ambiguous reference to column name \""
                           (List second node) "\" (use: "
                           (Str8 join " or "
                             (List map
                               (fn (_ i)
                                 (Str8 append "'" (first (List ref i columns)) "."
                                              (List second (List ref i columns)) "'"))
                               places))
                           ")")))))))

; --- aggregates --------------------------------------------------------------

(def %sql-aggregate?
  (fn (_ name) (List includes? (sql-lower name) sql-aggregates)))

; NODE is a call to an aggregate
(def sql-aggregate-call?
  (fn (_ node)
    (and (eq? (first node) (lit call)) (%sql-aggregate? (List second node)))))

; NODE holds a call to an aggregate, at any depth of its own statement: a
; subquery's aggregates are the subquery's.  A call OVER a window is no
; aggregate, though its arguments and its window may hold one.
(def sql-aggregated?
  (fn (self node)
    (match
      ((not (pair? node)) #f)
      ((sql-aggregate-call? node) #t)
      ((eq? (first node) (lit over))
        (or (self (List third (List second node))) (self (rest (rest node)))))
      ((or (eq? (first node) (lit subquery)) (eq? (first node) (lit exists))) #f)
      ((eq? (first node) (lit in-query)) (self (List second node)))
      (#t (List any? self node)))))

; NODE holds a call OVER a window, at any depth of its own statement
(def sql-windowed?
  (fn (self node)
    (match
      ((not (pair? node)) #f)
      ((eq? (first node) (lit over)) #t)
      ((or (eq? (first node) (lit subquery)) (eq? (first node) (lit exists))) #f)
      ((eq? (first node) (lit in-query)) (self (List second node)))
      (#t (List any? self node)))))

; A scope of a group as a scope of its first row, for what is not
; aggregated
(def %sql-plain
  (fn (_ scope) (list (first scope) (List second scope) () (%sql-fourth scope))))

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

; The type ARG has in a group, read off the group's first row, or off a
; row of NULLs when the group is empty
(def %sql-arg-type
  (fn (_ node scope)
    (let ((members (first (List third scope))))
      (first (sql-eval (first (List third node))
                       (if (null? members) (%sql-plain scope) (first members)))))))

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
                     (sql-lower (List second node)) "(" (%sql-type-name t) ")'."))))

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
          ((eq? t (lit uhugeint))
            (pair (lit double)
              (if (null? values) ()
                (List fold (fn (_ acc v) (+ acc (%sql-as-double v))) (Float from 0) values))))
          ((%sql-int? t)
            (%sql-total (lit hugeint) values (%sql-limit (lit hugeint))))
          ((%sql-decimal? t)
            (%sql-total (list (lit decimal) %sql-decimal-width (List third t))
                        values (sql-pow10 %sql-decimal-width)))
          ((%sql-float? t)
            (pair (lit double) (if (null? values) ()
                      (List fold (fn (_ acc v) (+ acc (rest v)))
                                 (rest (first values)) (rest values)))))
          (#t (%sql-no-function node t)))))
    (method avg (self node scope)
      (%sql-one-argument node)
      (let ((t (%sql-arg-type node scope)) (values (%sql-values node scope)))
        (unless (%sql-numeric? t) (%sql-no-function node t))
        (pair (lit double)
          (if (null? values) ()
            (/ (if (%sql-float? t)
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

; An aggregate CALL answered for the group of SCOPE, as a window's frame
; is one.  A scalar function is refused, and a name nothing has.
(def sql-window-aggregate
  (fn (_ call scope)
    (let ((name (Str8 ->sym (sql-lower (List second call)))))
      (let ((aggregate (class-static-ref SqlAggregate name)))
        (match
          ((not (null? aggregate)) (aggregate SqlAggregate call scope))
          ((null? (class-static-ref SqlFunction name))
            (error (Str8 str "Catalog Error: Aggregate Function with name "
                             (List second call) " does not exist!")))
          (#t (error (Str8 str "Catalog Error: " (List second call)
                               " is not an aggregate function"))))))))

; V, the value of NODE, as it stands beside OTHER: an integer constant
; takes OTHER's integer type when that holds it
(def %sql-constant-beside
  (fn (_ node v other)
    (if (and (eq? (first node) (lit int)) (%sql-int? (first other))
             (%sql-fits? (first other) (rest v)))
      (pair (first other) (rest v))
      v)))

(def-class SqlNode ()
  (static
    (method int (self node scope)
      (pair (%sql-int-type (List second node)) (List second node)))
    (method dec (self node scope)
      (pair (list (lit decimal) (List third node) (List ref 3 node))
            (List second node)))
    (method dbl (self node scope)
      (pair (lit double) (sql-double-of (List second node))))
    (method to-interval (self node scope)
      (let ((v (sql-eval (List second node) scope)))
        (unless (%sql-numeric-or-null? (first v))
          (error (Str8 str "Binder Error: No function matches the given name and argument types 'to_"
                           (sql-lower (List third node)) "(" (%sql-type-name (first v)) ")'.")))
        (pair (lit interval)
          (if (%sql-null? v) ()
            (sql-interval-of (%sql-cast-integer v (lit bigint)) (List third node))))))
    (method cast (self node scope)
      (pair (List third node)
            (sql-cast (sql-eval (List second node) scope) (List third node))))
    (method str (self node scope) (pair (lit varchar) (List second node)))
    (method bool (self node scope) (pair (lit boolean) (List second node)))
    (method null (self node scope) (pair (lit null) ()))
    ; A window's value was worked out for the row before the row's items
    ; are: it is held in the scope under its node
    (method over (self node scope)
      (let ((held (if (null? scope) ()
                    (List find (fn (_ h) (same? (first h) node))
                               (%sql-scope-windows scope)))))
        (if (null? held) (error "Binder Error: Window functions are not supported here")
          (rest held))))
    (method col (self node scope)
      (if (or (null? scope) (and (null? (first scope)) (null? (%sql-fourth scope))))
        (error (Str8 str "Binder Error: Referenced column \"" (List second node)
                         "\" was not found because the FROM clause is missing"))
        (let ((places (%sql-column-places (%sql-fourth node) (%sql-fifth node) (first scope) 0)))
          (if (and (null? places) (not (null? (%sql-fourth scope))))
            (sql-eval node (%sql-fourth scope))
            (let ((i (if (and (not (null? places)) (null? (rest places))) (first places)
                       (sql-column-index node (first scope)))))
              (pair (first (rest (rest (%sql-nth (first scope) i))))
                    (%sql-nth (first (rest scope)) i)))))))
    (method call (self node scope)
      (let ((aggregate (class-static-ref SqlAggregate
                         (Str8 ->sym (sql-lower (List second node))))))
        (match
          ((null? aggregate)
            (let ((function (class-static-ref SqlFunction
                              (Str8 ->sym (sql-lower (List second node))))))
              (when (List includes? (sql-lower (List second node)) sql-window-functions)
                (error "Binder Error: Window functions are not supported here"))
              (when (or (null? function) (List ref 3 node)
                        (List any? (fn (_ a) (eq? (first a) (lit star))) (List third node)))
                (error (Str8 str "Catalog Error: Scalar Function with name "
                                 (List second node) " does not exist!")))
              (function SqlFunction
                (List map (fn (_ a) (sql-eval a scope)) (List third node))
                node)))
          ((sql-aggregated? (List third node))
            (error "Binder Error: aggregate function calls cannot be nested"))
          ((sql-windowed? (List third node))
            (error "Binder Error: aggregate function calls cannot contain window function calls"))
          ((or (null? scope) (null? (List third scope)))
            (error "Binder Error: an aggregate has no group of rows here"))
          (#t (aggregate SqlAggregate node scope)))))
    (method case (self node scope)
      (let ((whens (List second node)) (otherwise (List third node)))
        (let ((t (sql-common-type
                   (List map (fn (_ e) (%sql-type-in e scope))
                     (List append (List map (fn (_ w) (List second w)) whens)
                                  (if (null? otherwise) () (list otherwise))))))
              (taken (List find
                       (fn (_ w) (eq? (%sql-truth (sql-eval (first w) scope)) #t))
                       whens)))
          (match
            ((not (null? taken)) (%sql-as (sql-eval (List second taken) scope) t))
            ((null? otherwise) (pair (if (%sql-null-type? t) (lit integer) t) ()))
            (#t (%sql-as (sql-eval otherwise scope) t))))))
    (method in (self node scope)
      (%sql-among (sql-eval (List second node) scope)
                  (List map (fn (_ e) (sql-eval e scope)) (List third node))))
    (method in-query (self node scope)
      (%sql-among (sql-eval (List second node) scope)
                  (rest (%sql-subcolumn (List third node) scope))))
    (method exists (self node scope)
      (pair (lit boolean)
            (not (null? (List third (%sql-subresult (List second node) scope))))))
    (method subquery (self node scope)
      (let ((column (%sql-subcolumn (List second node) scope)))
        (match
          ((null? (rest column)) (pair (first column) ()))
          ((null? (rest (rest column))) (first (rest column)))
          (#t (error "Invalid Input Error: More than one row returned by a subquery used as an expression - scalar subqueries can only return a single row.")))))
    (method between (self node scope)
      (let ((v (sql-eval (List second node) scope)))
        (let ((low (rest (%sql-compare v (sql-eval (List third node) scope) (fn (_ c) (>= c 0)))))
              (high (rest (%sql-compare v (sql-eval (List ref 3 node) scope) (fn (_ c) (<= c 0))))))
          (pair (lit boolean) (%sql-both low high)))))
    (method like (self node scope)
      (let ((v (sql-eval (List second node) scope))
            (pattern (sql-eval (List third node) scope)))
        (%sql-texts "~~" (list v pattern))
        (pair (lit boolean)
          (if (or (%sql-null? v) (%sql-null? pattern)) ()
            (let ((matched (if (List ref 4 node)
                             (%sql-like? (Str8 downcase (rest v)) 0 (Str8 downcase (rest pattern)) 0)
                             (%sql-like? (rest v) 0 (rest pattern) 0))))
              (if (List ref 3 node) (not matched) matched))))))
    (method neg (self node scope)
      (let ((v (sql-eval (List second node) scope)))
        (match
          ((or (%sql-float? (first v)) (%sql-decimal? (first v)))
            (pair (first v)
              (if (%sql-null? v) ()
                (if (%sql-float? (first v)) (- (Float from 0) (rest v))
                  (- 0 (rest v))))))
          (#t
            (let ((t (%sql-arith-type "-" v v)))
              (match
                ((%sql-null? v) (pair t ()))
                ((and (%sql-int? t) (%sql-unsigned? t) (> (rest v) 0))
                  (error "Out of Range Error: Overflow in negation of numeric value!"))
                (#t (%sql-checked t (- 0 (rest v)) "negation" "-" (pair t 0) v))))))))
    (method not (self node scope)
      (let ((v (%sql-truth (sql-eval (List second node) scope))))
        (pair (lit boolean) (if (null? v) () (not v)))))
    (method is-null (self node scope)
      (let ((null (%sql-null? (sql-eval (List second node) scope))))
        (pair (lit boolean) (if (List third node) (not null) null))))
    (method and (self node scope)
      (pair (lit boolean)
        (%sql-both (%sql-truth (sql-eval (List second node) scope))
                   (%sql-truth (sql-eval (List third node) scope)))))
    (method or (self node scope)
      (let ((a (%sql-truth (sql-eval (List second node) scope)))
            (b (%sql-truth (sql-eval (List third node) scope))))
        (pair (lit boolean)
          (match
            ((or (eq? a #t) (eq? b #t)) #t)
            ((or (null? a) (null? b)) ())
            (#t #f)))))
    ; An integer constant beside a TINYINT or a SMALLINT is one too when it
    ; fits, as DuckDB has it
    (method bin (self node scope)
      (let ((a (sql-eval (List third node) scope))
            (b (sql-eval (List ref 3 node) scope)))
        ((class-static-ref SqlOp (List second node)) SqlOp
         (%sql-constant-beside (List third node) a b)
         (%sql-constant-beside (List ref 3 node) b a)
         (sql-expr-name node))))))

; How a binary operator is spelled in a heading
(def %sql-op-text
  (fn (_ name)
    (List third (List find (fn (_ r) (eq? (List second r) name)) sql-binary-ops))))

; A function's name in a heading: lower case, but for the ones DuckDB
; spells its own way
(def %sql-call-names
  (list (pair "substring" "\"substring\"") (pair "trim" "\"trim\"")
        (pair "replace" "\"replace\"") (pair "left" "\"left\"")
        (pair "right" "\"right\"") (pair "nullif" "\"nullif\"")
        (pair "coalesce" "COALESCE") (pair "ifnull" "COALESCE")
        (pair "year" "\"year\"") (pair "month" "\"month\"") (pair "day" "\"day\"")
        (pair "hour" "\"hour\"") (pair "minute" "\"minute\"")
        (pair "second" "\"second\"") (pair "quarter" "\"quarter\"")))

(def %sql-call-name
  (fn (_ name)
    (let ((own (List find (fn (_ row) (str=? (first row) (sql-lower name))) %sql-call-names)))
      (if (null? own) (sql-lower name) (rest own)))))

; A select statement spelled out for a heading, as DuckDB spells one back:
; its items, its tables, and the clauses after
(def %sql-select-text
  (fn (_ stmt)
    (match
      ((eq? (first stmt) (lit with))
        (Str8 append "WITH ... " (%sql-select-text (List third stmt))))
      ((eq? (first stmt) (lit set))
        (Str8 append "(" (%sql-select-text (List ref 3 stmt)) ") "
                     (Str8 upcase (Str8 str (List second stmt)))
                     (if (List third stmt) " ALL (" " (")
                     (%sql-select-text (List ref 4 stmt)) ")"))
      (#t
      (let ((clause (fn (_ word e) (if (null? e) "" (Str8 append " " word " " (sql-expr-name e))))))
        (Str8 append "SELECT "
          (if (List ref 9 stmt) "DISTINCT " "")
          (Str8 join ", "
            (List map
              (fn (_ i)
                (Str8 append (sql-expr-name (first i))
                  (if (null? (List second i)) "" (Str8 append " AS " (List second i)))))
              (List second stmt)))
          (if (null? (List third stmt)) ""
            (Str8 append " FROM "
              (Str8 join ", "
                (List map
                  (fn (_ source)
                    (let ((named (if (symbol? (first source)) (rest source) source)))
                      (Str8 append
                        (if (pair? (first named))
                          (Str8 append "(" (%sql-select-text (first named)) ")")
                          (first named))
                        (if (null? (List second named)) ""
                          (Str8 append " AS " (List second named))))))
                  (List third stmt)))))
          (clause "WHERE" (List ref 3 stmt))
          (if (or (null? (List ref 7 stmt)) (eq? (List ref 7 stmt) (lit all))) ""
            (Str8 append " GROUP BY "
              (Str8 join ", " (List map sql-expr-name (List ref 7 stmt)))))
          (clause "HAVING" (List ref 8 stmt))
          (clause "QUALIFY" (List ref 10 stmt))
          (if (null? (List ref 4 stmt)) ""
            (Str8 append " ORDER BY "
              (Str8 join ", "
                (List map (fn (_ term) (sql-expr-name (first term))) (List ref 4 stmt)))))
          (clause "LIMIT" (List ref 5 stmt))
          (clause "OFFSET" (List ref 6 stmt))))))))

; One end of a frame as a heading spells it, FAR the word for its side
(def %sql-frame-end-text
  (fn (_ end far)
    (match
      ((eq? end (lit unbounded)) (Str8 append "UNBOUNDED " far))
      ((eq? end (lit current)) "CURRENT ROW")
      (#t (Str8 append (sql-expr-name (List second end))
                       (if (< (first end) 0) " PRECEDING" " FOLLOWING"))))))

; A frame as a heading spells it
(def %sql-frame-text
  (fn (_ frame)
    (Str8 append (Str8 upcase (Str8 str (first frame))) " BETWEEN "
      (%sql-frame-end-text (List second frame) "PRECEDING") " AND "
      (%sql-frame-end-text (List third frame) "FOLLOWING")
      (if (null? (List ref 3 frame)) ""
        (Str8 append " EXCLUDE " (List third (List ref 3 frame)))))))

; A term of an ORDER BY as a heading spells it
(def %sql-term-text
  (fn (_ term)
    (Str8 append (sql-expr-name (first term))
      (if (List second term) " DESC" "")
      (if (null? (List third term)) ""
        (if (eq? (List third term) (lit first)) " NULLS FIRST" " NULLS LAST")))))

; The clauses of a window that are there, as a heading spells them
(def %sql-window-texts
  (fn (_ node)
    (let ((partition (List third node)) (order (List ref 3 node)) (frame (List ref 4 node)))
      (List append
        (if (null? partition) ()
          (list (Str8 append "PARTITION BY "
                  (Str8 join ", " (List map sql-expr-name partition)))))
        (if (null? order) ()
          (list (Str8 append "ORDER BY " (Str8 join ", " (List map %sql-term-text order)))))
        (if (null? frame) ()
          (list (%sql-frame-text frame)))))))

(def-class SqlName ()
  (static
    ; A count of rows is count() before an OVER, count_star() elsewhere
    (method over (self node)
      (let ((call (sql-expr-name (List second node))))
        (Str8 append (if (str=? call "count_star()") "count()" call)
                     " OVER (" (Str8 join " " (%sql-window-texts node)) ")")))
    (method int (self node) (Str8 str (List second node)))
    (method dec (self node) (List ref 4 node))
    (method dbl (self node) (List second node))
    ; DuckDB's spelling of INTERVAL 2 HOUR: the count as a whole number, a
    ; BIGINT for a unit of time and an INTEGER for one of the calendar
    (method to-interval (self node)
      (let ((unit (sql-lower (List third node))))
        (Str8 append "to_" unit (if (Str8 ends? "s" unit) "" "s")
                     "(CAST(trunc(CAST(" (sql-expr-name (List second node))
                     " AS DOUBLE)) AS "
                     (if (= (List third (sql-interval-of 1 unit)) 0) "INTEGER" "BIGINT")
                     "))")))
    (method cast (self node)
      (Str8 append "CAST(" (sql-expr-name (List second node)) " AS "
                   (List ref 3 node) ")"))
    ; DuckDB's spelling: two blanks after CASE, a condition and a result in
    ; parentheses, and an ELSE always
    (method case (self node)
      (Str8 append "CASE "
        (Str8 join ""
          (List map
            (fn (_ w)
              (Str8 append " WHEN (" (sql-expr-name (first w)) ") THEN ("
                           (sql-expr-name (List second w)) ")"))
            (List second node)))
        " ELSE "
        (if (null? (List third node)) "NULL" (sql-expr-name (List third node)))
        " END"))
    (method in (self node)
      (Str8 append "(" (sql-expr-name (List second node)) " IN ("
                   (Str8 join ", " (List map sql-expr-name (List third node))) "))"))
    (method between (self node)
      (Str8 append "(" (sql-expr-name (List second node)) " BETWEEN "
                   (sql-expr-name (List third node)) " AND "
                   (sql-expr-name (List ref 3 node)) ")"))
    ; LIKE is ~~ in a heading, ILIKE ~~*, and a ! before either says NOT
    (method like (self node)
      (Str8 append "(" (sql-expr-name (List second node)) " "
                   (if (List ref 3 node) "!" "") "~~" (if (List ref 4 node) "*" "") " "
                   (sql-expr-name (List third node)) ")"))
    (method str (self node)
      (Str8 append "'" (Str8 replace "'" "''" (List second node)) "'"))
    (method bool (self node) (if (List second node) "true" "false"))
    (method null (self node) "NULL")
    (method col (self node)
      (if (null? (List third node)) (List second node)
        (Str8 append (List third node) "." (List second node))))
    (method star (self node)
      (if (null? (List second node)) "*" (Str8 append (List second node) ".*")))
    (method subquery (self node)
      (Str8 append "(" (%sql-select-text (List second node)) ")"))
    (method in-query (self node)
      (Str8 append "(" (sql-expr-name (List second node)) " = ANY("
                   (%sql-select-text (List third node)) "))"))
    (method exists (self node)
      (Str8 append "EXISTS(" (%sql-select-text (List second node)) ")"))
    (method call (self node)
      (let ((args (List third node)))
        (if (and (%sql-aggregate? (List second node))
                 (sql-same-name? (List second node) "count")
                 (or (null? args) (eq? (first (first args)) (lit star))))
          "count_star()"
          (Str8 append (%sql-call-name (List second node)) "("
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
        ((%sql-float? from)
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
        ((%sql-float? from)
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

(def %sql-no-cast
  (fn (_ from t)
    (error (Str8 str "Not implemented Error: casting " (%sql-type-name from)
                     " to " (%sql-type-name t)))))

; What READ makes of TEXT, or the error of a KIND that is not one: FORMAT
; when the text has not its form, and out of range when it has
(def %sql-read-or
  (fn (_ read text kind format)
    (let ((x (read text)))
      (match
        ((null? x) (error (Str8 append "Conversion Error: " format)))
        ((eq? x (lit out-of-range))
          (error (Str8 append "Conversion Error: " kind " field value out of range: \"" text "\"")))
        (#t x)))))

; The words that spell a float no digits do, in lower case, and a function
; that answers each
(def %sql-float-words
  (let ((zero (Float from 0)) (one (Float from 1)))
    (let ((inf (fn (_) (/ one zero))))
      (list (pair "inf" inf) (pair "+inf" inf) (pair "infinity" inf)
            (pair "-inf" (fn (_) (- zero (/ one zero))))
            (pair "-infinity" (fn (_) (- zero (/ one zero))))
            (pair "nan" (fn (_) (/ zero zero)))))))

; V as a double, for a cast to the float type NAME
(def %sql-cast-float
  (fn (_ v name)
    (let ((from (first v)) (x (rest v)))
      (match
        ((%sql-numeric? from) (%sql-as-double v))
        ((eq? from (lit boolean)) (Float from (if x 1 0)))
        ((eq? from (lit varchar))
          (let ((number (%sql-number-text x))
                (word (List find (fn (_ w) (str=? (first w) (sql-lower (Str8 trim x))))
                                 %sql-float-words)))
            (match
              ((not (null? word)) ((rest word)))
              ((null? number) (%sql-no-conversion x name))
              (#t (sql-double-of (Str8 append (if (first number) "-" "")
                                              (List second number)))))))
        (#t (error (Str8 str "Not implemented Error: casting "
                             (%sql-type-name from) " to " name)))))))

(def-class SqlCast ()
  (static
    (method varchar (self v t) (sql-value-text v))
    ; A column with no type, as a table made from a NULL constant has,
    ; holds only NULLs
    (method null (self v t)
      (error "Not implemented Error: a value for a column of no type"))
    (method integer (self v t) (%sql-cast-integer v t))
    (method bigint (self v t) (%sql-cast-integer v t))
    (method hugeint (self v t) (%sql-cast-integer v t))
    (method tinyint (self v t) (%sql-cast-integer v t))
    (method smallint (self v t) (%sql-cast-integer v t))
    (method utinyint (self v t) (%sql-cast-integer v t))
    (method usmallint (self v t) (%sql-cast-integer v t))
    (method uinteger (self v t) (%sql-cast-integer v t))
    (method ubigint (self v t) (%sql-cast-integer v t))
    (method uhugeint (self v t) (%sql-cast-integer v t))
    (method double (self v t) (%sql-cast-float v "DOUBLE"))
    ; A number too great for a REAL is refused; text that spells one is an
    ; infinity
    (method real (self v t)
      (let ((x (%sql-cast-float v "FLOAT")))
        (let ((r (sql-real-of x)))
          (if (and (%sql-numeric? (first v)) (sql-double-finite? x)
                   (not (sql-double-finite? r)))
            (%sql-out-of-range v "FLOAT")
            r))))
    (method decimal (self v t)
      (let ((n (%sql-scaled-of v (List third t) (%sql-type-name t)))
            (limit (sql-pow10 (List second t))))
        (if (and (< n limit) (> n (- 0 limit))) n
          (error (Str8 str "Conversion Error: Casting value \"" (sql-value-text v)
                           "\" to type " (%sql-type-name t)
                           " failed: value is out of range!")))))
    (method date (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit date)) x)
          ((eq? from (lit timestamp)) (sql-floor-div x sql-micros-day))
          ((eq? from (lit varchar))
            (%sql-read-or sql-date-read x "date"
              (Str8 append "invalid date field format: \"" x "\", expected format is (YYYY-MM-DD)")))
          (#t (%sql-no-cast from t)))))
    (method timestamp (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit timestamp)) x)
          ((eq? from (lit date)) (* x sql-micros-day))
          ((eq? from (lit varchar))
            (%sql-read-or sql-timestamp-read x "timestamp"
              (Str8 append "invalid timestamp field format: \"" x
                           "\", expected format is (YYYY-MM-DD HH:MM:SS[.US][±HH[:MM[:SS]]| ZONE])")))
          (#t (%sql-no-cast from t)))))
    (method time (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit time)) x)
          ((eq? from (lit timestamp)) (sql-floor-mod x sql-micros-day))
          ((eq? from (lit varchar))
            (%sql-read-or sql-clock-read x "time"
              (Str8 append "invalid time field format: \"" x
                           "\", expected format is ([YYYY-MM-DD ]HH:MM:SS[.MS])")))
          (#t (%sql-no-cast from t)))))
    (method interval (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit interval)) x)
          ((eq? from (lit varchar))
            (let ((read (sql-interval-read x)))
              (if (null? read)
                (error (Str8 append "Conversion Error: Could not convert string '" x "' to INTERVAL"))
                read)))
          (#t (%sql-no-cast from t)))))
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
  sql-eval sql-expr-name sql-scope sql-select-runner! sql-column
  sql-column-hidden? sql-column-hide sql-column-node sql-column-index
  sql-aggregated? sql-aggregate-call? sql-common-type sql-cast
  sql-windowed? sql-scope-windowed sql-window-aggregate
  sql-truth sql-order sql-null? sql-value-text sql-type-heading
  sql-type-name sql-numeric-type?)

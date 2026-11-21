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
; them.  A list's type is (list TYPE) and its X a list of one, the x values
; of its elements, so that an empty list is not a NULL.  A struct's type is
; (struct (NAME TYPE) ...) and its X the x values of its fields in that
; order.  A NULL keeps the type
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
  sql-window-functions sql-keywords)
(import sql/lex sql-lex)
(import sql/time
  sql-micros-second sql-micros-minute sql-micros-hour sql-micros-day
  sql-floor-div sql-floor-mod sql-civil sql-days sql-month-days
  sql-date-text sql-clock-text sql-timestamp-text sql-interval-text
  sql-date-read sql-clock-read sql-timestamp-read sql-interval-read
  sql-interval-of sql-interval-add sql-interval-times sql-interval-negated
  sql-timestamp-plus sql-micros-interval sql-interval-micros sql-day-names
  sql-month-names sql-day-of-year sql-moment-diff sql-moment-trunc)
(import sql/zone
  sql-zone-find sql-zone-offset sql-zone-utc sql-zone-name sql-zone-session)
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
        (list (lit timestamptz) "TIMESTAMP WITH TIME ZONE" "timestamp with time zone")
        (list (lit interval) "INTERVAL" "interval")
        (list (lit blob) "BLOB" "blob")
        (list (lit null) "NULL" "\"null\"")))

; The row of ROWS whose first is KEY.  It is walked here, a row at a time:
; a type is asked of several times for every value answered, and a
; function handed to a finder is made anew at each asking.
(def %sql-row
  (fn (self key rows)
    (match
      ((null? rows) ())
      ((eq? (first (first rows)) key) (first rows))
      (#t (self key (rest rows))))))

(def %sql-int? (fn (_ t) (not (null? (%sql-row t %sql-int-rows)))))
(def %sql-limit (fn (_ t) (List second (%sql-row t %sql-int-rows))))
(def %sql-int-name (fn (_ t) (List third (%sql-row t %sql-int-rows))))
(def %sql-least (fn (_ t) (List ref 4 (%sql-row t %sql-int-rows))))
(def %sql-unsigned? (fn (_ t) (= (%sql-least t) 0)))

(def %sql-decimal? (fn (_ t) (and (pair? t) (eq? (first t) (lit decimal)))))
(def %sql-list? (fn (_ t) (and (pair? t) (eq? (first t) (lit list)))))
(def %sql-struct? (fn (_ t) (and (pair? t) (eq? (first t) (lit struct)))))
(def %sql-nested? (fn (_ t) (or (%sql-list? t) (%sql-struct? t))))

; A struct whose fields have no names, which DuckDB calls a tuple: every
; field's name is the empty text
(def %sql-tuple?
  (fn (_ t)
    (and (%sql-struct? t)
         (List all? (fn (_ f) (= (Str8 length (first f)) 0)) (rest t)))))
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

; A name is written bare when it is letters, digits and underscores, does
; not start with a digit, and is no keyword; any other goes in double
; quotes
(def %sql-bare-name?
  (fn (_ name)
    (let ((n (Str8 length name)))
      (and (> n 0)
           (not (and (>= (%sql-byte name 0) 48) (<= (%sql-byte name 0) 57)))
           (List all?
             (fn (_ i)
               (let ((b (%sql-byte name i)))
                 (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90))
                     (and (>= b 48) (<= b 57)) (= b 95))))
             (List range 0 n))))))

; Each name's spelling is worked out once: a heading is spelled for every
; row of some statements, and the keywords are many.
(def %sql-key-names (Dict make))

(def %sql-key-name
  (fn (_ name)
    (unless (%sql-key-names has? name)
      (%sql-key-names set! name
        (if (and (%sql-bare-name? name)
                 (not (List includes? (Str8 downcase name) sql-keywords)))
          name
          (Str8 append "\"" name "\""))))
    (%sql-key-names get name)))

(def %sql-type-name
  (fn (self t)
    (match
      ((%sql-decimal? t) (Str8 append "DECIMAL" (%sql-decimal-name t)))
      ((%sql-list? t)
        (Str8 append (if (%sql-null-type? (List second t)) "\"NULL\"" (self (List second t)))
                     "[]"))
      ((and (%sql-tuple? t) (null? (rest t))) "TUPLE")
      ((%sql-tuple? t)
        (Str8 append "TUPLE("
          (Str8 join ", "
            (List map
              (fn (_ f) (if (%sql-null-type? (List second f)) "\"NULL\"" (self (List second f))))
              (rest t)))
          ")"))
      ((%sql-struct? t)
        (Str8 append "STRUCT("
          (Str8 join ", "
            (List map
              (fn (_ f)
                (Str8 append (%sql-key-name (first f)) " "
                  (if (%sql-null-type? (List second f)) "\"NULL\"" (self (List second f)))))
              (rest t)))
          ")"))
      (#t (List second (%sql-row t %sql-type-rows))))))

; A struct is headed by its SQL name in lower case, and a list by its
; element's heading
(def sql-type-heading
  (fn (self t)
    (match
      ((%sql-decimal? t) (Str8 append "decimal" (%sql-decimal-name t)))
      ((%sql-list? t) (Str8 append (self (List second t)) "[]"))
      ((%sql-struct? t) (Str8 downcase (%sql-type-name t)))
      (#t (List third (%sql-row t %sql-type-rows))))))

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

; --- moments in a zone -------------------------------------------------------

; A TIMESTAMP WITH TIME ZONE is a moment, in microseconds of UTC; the
; session's zone says what clock shows it.

; ZONE's offset at the moment MICROS, in seconds east
(def %sql-zone-seconds
  (fn (_ micros zone) (sql-zone-offset zone (sql-floor-div micros sql-micros-second))))

; What ZONE's clock shows at the moment MICROS, as a moment of a clock
; with no zone
(def %sql-zone-local
  (fn (_ micros zone) (+ micros (* (%sql-zone-seconds micros zone) sql-micros-second))))

; The moment ZONE's clock shows LOCAL
(def %sql-zone-global
  (fn (_ local zone)
    (+ (* (sql-zone-utc zone (sql-floor-div local sql-micros-second)) sql-micros-second)
       (sql-floor-mod local sql-micros-second))))

(def %sql-two-digits
  (fn (_ n) (if (< n 10) (Str8 str "0" n) (Str8 str n))))

; An offset as a moment shows it: a sign, the hours, and the minutes when
; there are any
(def %sql-offset-text
  (fn (_ seconds)
    (let ((minutes (Num quotient (if (< seconds 0) (- 0 seconds) seconds) 60)))
      (Str8 append (if (< seconds 0) "-" "+")
                   (%sql-two-digits (Num quotient minutes 60))
                   (if (= (Num remainder minutes 60) 0) ""
                     (Str8 append ":" (%sql-two-digits (Num remainder minutes 60))))))))

(def %sql-zoned-text
  (fn (_ micros zone)
    (Str8 append (sql-timestamp-text (%sql-zone-local micros zone))
                 (%sql-offset-text (%sql-zone-seconds micros zone)))))

; The bytes that put a text inside a list or a struct in quotes: a comma,
; a colon, an equals sign, both quotes, the three pairs of brackets and a
; backslash
(def %sql-quoting-bytes (list 44 58 61 34 39 40 41 123 125 91 93 92))

; TEXT as a list or a struct shows it: in single quotes when it is empty,
; starts or ends with a blank, spells null, or holds one of the bytes
; above, a quote and a backslash each after a backslash
(def %sql-nested-quoted
  (fn (_ text)
    (let ((n (Str8 length text)))
      (if (or (= n 0) (= (%sql-byte text 0) 32) (= (%sql-byte text (- n 1)) 32)
              (Str8 ci=? text "null")
              (List any? (fn (_ i) (List includes? (%sql-byte text i) %sql-quoting-bytes))
                         (List range 0 n)))
        (Str8 append "'" (Str8 replace "'" "\\'" (Str8 replace "\\" "\\\\" text)) "'")
        text))))

; A value inside a list or a struct
(def %sql-nested-text
  (fn (_ v)
    (let ((t (first v)))
      (if (or (null? (rest v)) (%sql-nested? t) (%sql-numeric? t) (eq? t (lit boolean)))
        (sql-value-text v)
        (%sql-nested-quoted (sql-value-text v))))))

; The values a list holds, each with the list's element type
(def %sql-elements
  (fn (_ v) (List map (fn (_ e) (pair (List second (first v)) e)) (first (rest v)))))

; The values a struct holds, each with its field's type
(def %sql-members
  (fn (_ v) (List map (fn (_ f e) (pair (List second f) e)) (rest (first v)) (rest v))))

; --- BLOB ----------------------------------------------------------------------
;
; A BLOB's bytes are held as text of two hexadecimal digits a byte, the
; letters in upper case.  Text of that form stands in the order the bytes
; do and is equal just when they are, so a BLOB is ordered, grouped and
; kept once as text is; and it holds a zero byte, which the platform's
; text does not.

(def %sql-hex-digits "0123456789ABCDEF")

; The digits of every byte, 00 to FF, one after another
(def %sql-hex-pairs
  (Str8 join ""
    (List flat-map
      (fn (_ hi)
        (List map
          (fn (_ lo) (Str8 append (Str8 sub hi 1 %sql-hex-digits) (Str8 sub lo 1 %sql-hex-digits)))
          (List range 0 16)))
      (List range 0 16))))

; The two digits of the byte B
(def %sql-byte-hex (fn (_ b) (Str8 sub (* b 2) 2 %sql-hex-pairs)))

; What the digit with the code C is worth; nil when C is no digit
(def %sql-hex-value
  (fn (_ c)
    (match
      ((and (>= c 48) (<= c 57)) (- c 48))
      ((and (>= c 65) (<= c 70)) (- c 55))
      ((and (>= c 97) (<= c 102)) (- c 87))
      (#t ()))))

; The byte of TEXT at I, 0 to 255
(def %sql-octet
  (fn (_ text i) (Num remainder (+ (Char ->int (Str8 ref i text)) 256) 256)))

; The characters a BLOB is shown with as they are, from the space on
(def %sql-blob-plain
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")

; The code of the first of them, of the last, and of the three that are
; shown by their digits all the same: the backslash and both quotes
(def %sql-blob-first 32)
(def %sql-blob-last 126)
(def %sql-blob-escaped (list 92 39 34))

; A BLOB as a result shows it: a plain character as it is, any other byte
; as \x and its two digits
(def %sql-blob-text
  (fn (_ hex)
    (Str8 join ""
      (List map
        (fn (_ i)
          (let ((b (+ (* 16 (%sql-hex-value (%sql-octet hex (* i 2))))
                      (%sql-hex-value (%sql-octet hex (+ (* i 2) 1))))))
            (if (and (>= b %sql-blob-first) (<= b %sql-blob-last)
                     (not (List includes? b %sql-blob-escaped)))
              (Str8 sub (- b %sql-blob-first) 1 %sql-blob-plain)
              (Str8 append "\\x" (%sql-byte-hex b)))))
        (List range 0 (Num quotient (Str8 length hex) 2))))))

; The BLOB every byte of TEXT is a byte of
(def sql-text-blob
  (fn (_ text)
    (Str8 join ""
      (List map (fn (_ i) (%sql-byte-hex (%sql-octet text i)))
                (List range 0 (Str8 length text))))))

; The BLOB of BYTES, a list of whole numbers 0 to 255
(def sql-bytes-blob
  (fn (_ bytes) (Str8 join "" (List map %sql-byte-hex bytes))))

; The BLOB the text TEXT says: a character below 128 is its byte, and \x
; with two digits the byte they say.  Anything else is DuckDB's error.
(def %sql-blob-read
  (fn (_ text)
    (let ((n (Str8 length text))
          (bad (fn (_ what)
                 (error (Str8 append "Conversion Error: Invalid hex escape code encountered in string -> blob conversion of string \""
                                     text "\": " what)))))
      (let ((go (fn (self i parts)
                  (if (>= i n) (Str8 join "" (List reverse parts))
                    (let ((b (%sql-octet text i)))
                      (match
                        ((>= b 128)
                          (error (Str8 append "Conversion Error: Invalid byte encountered in STRING -> BLOB conversion of string \""
                                              text "\". All non-ascii characters must be escaped with hex codes (e.g. \\xAA)")))
                        ((not (= b 92)) (self (+ i 1) (pair (%sql-byte-hex b) parts)))
                        ((>= (+ i 3) n) (bad "unterminated escape code at end of blob"))
                        (#t
                          (let ((hi (%sql-hex-value (%sql-octet text (+ i 2))))
                                (lo (%sql-hex-value (%sql-octet text (+ i 3)))))
                            (if (or (not (= (%sql-octet text (+ i 1)) 120)) (null? hi) (null? lo))
                              (bad (Str8 sub i 4 text))
                              (self (+ i 4) (pair (%sql-byte-hex (+ (* 16 hi) lo)) parts)))))))))))
        (go 0 ())))))

; The BLOB the hexadecimal digits of TEXT say, a lone first digit a byte
; of its own.  A character that is no digit is DuckDB's error.
(def %sql-unhex
  (fn (_ text)
    (let ((whole (if (= (Num remainder (Str8 length text) 2) 0) text (Str8 append "0" text))))
      (let ((bad (List find (fn (_ i) (null? (%sql-hex-value (%sql-octet whole i))))
                            (List range 0 (Str8 length whole)))))
        (if (null? bad) (Str8 upcase whole)
          (error (Str8 append "Invalid Input Error: Invalid input for hex digit: "
                              (Str8 sub bad 1 whole))))))))

; A value as a result shows it
(def sql-value-text
  (fn (_ v)
    (let ((t (first v)) (x (rest v)))
      (match
        ((null? x) "NULL")
        ((%sql-list? t)
          (Str8 append "[" (Str8 join ", " (List map %sql-nested-text (%sql-elements v))) "]"))
        ; A tuple of one member is written with a comma after it
        ((%sql-tuple? t)
          (Str8 append "("
            (Str8 join ", " (List map %sql-nested-text (%sql-members v)))
            (if (null? (rest (rest t))) ",)" ")")))
        ((%sql-struct? t)
          (Str8 append "{"
            (Str8 join ", "
              (List map (fn (_ f m) (Str8 append "'" (first f) "': " (%sql-nested-text m)))
                        (rest t) (%sql-members v)))
            "}"))
        ((eq? t (lit boolean)) (if x "true" "false"))
        ((eq? t (lit varchar)) x)
        ((%sql-double? t) (sql-double-text x))
        ((%sql-real? t) (sql-real-text x))
        ((eq? t (lit date)) (sql-date-text x))
        ((eq? t (lit timestamp)) (sql-timestamp-text x))
        ((eq? t (lit timestamptz)) (%sql-zoned-text x (sql-zone-session)))
        ((eq? t (lit time)) (sql-clock-text x))
        ((eq? t (lit interval)) (sql-interval-text x))
        ((eq? t (lit blob)) (%sql-blob-text x))
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
        ((and (List all? %sql-moment-type? known) (List any? %sql-zoned? known))
          (lit timestamptz))
        ((List all? %sql-list? known)
          (list (lit list) (sql-common-type (List map (fn (_ t) (List second t)) known))))
        ((and (List all? %sql-struct? known)
              (List all?
                (fn (_ t)
                  (and (= (List length t) (List length (first known)))
                       (List all? (fn (_ same) same)
                         (List map (fn (_ f g) (sql-same-name? (first f) (first g)))
                                   (rest t) (rest (first known))))))
                known))
          (pair (lit struct)
            (List map
              (fn (_ fields)
                (list (first (first fields))
                      (sql-common-type (List map (fn (_ f) (List second f)) fields))))
              (List transpose (List map rest known)))))
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

(def %sql-temporal-types
  (list (lit date) (lit time) (lit timestamp) (lit timestamptz) (lit interval)))
(def %sql-zoned? (fn (_ t) (eq? t (lit timestamptz))))
(def %sql-temporal? (fn (_ t) (List includes? t %sql-temporal-types)))

; A date or a timestamp as a moment of a clock with no zone, in
; microseconds: for a timestamp with a zone, what the session's clock shows
(def %sql-moment
  (fn (_ v)
    (match
      ((eq? (first v) (lit date)) (* (rest v) sql-micros-day))
      ((%sql-zoned? (first v)) (%sql-zone-local (rest v) (sql-zone-session)))
      (#t (rest v)))))

(def %sql-moment-type?
  (fn (_ t) (or (eq? t (lit date)) (eq? t (lit timestamp)) (%sql-zoned? t))))

; A moment with a zone and an interval: the months and days are counted on
; the session's clock, so a day on is the same time the next day whatever
; the clock did between, and the rest is time gone by
(def %sql-zoned-plus
  (fn (_ micros interval)
    (let ((zone (sql-zone-session)))
      (+ (%sql-zone-global
           (sql-timestamp-plus (%sql-zone-local micros zone)
                               (list (first interval) (List second interval) 0))
           zone)
         (List third interval)))))

; T, or NULL of it when either operand is NULL, else what COMPUTE answers
(def %sql-unless-null
  (fn (_ t a b compute)
    (pair t (if (or (%sql-null? a) (%sql-null? b)) () (compute)))))

; + and - where a date, a time, a timestamp or an interval is an operand,
; and * of an interval by an integer.  A date and a count of days is a
; date; two dates apart are days; a date or a timestamp and an interval is
; a timestamp; two moments apart are an interval; a time and an interval
; is a time, on the clock of one day.  A moment with a zone and an
; interval is a moment with a zone, and two moments apart are told on the
; session's clock, as DuckDB tells them.
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
        ((and (%sql-zoned? ta) (eq? tb (lit interval)) (or plus minus))
          (%sql-unless-null (lit timestamptz) a b
            (fn (_) (%sql-zoned-plus (rest a)
                      (if plus (rest b) (sql-interval-negated (rest b)))))))
        ((and (eq? ta (lit interval)) (%sql-zoned? tb) plus)
          (%sql-unless-null (lit timestamptz) a b
            (fn (_) (%sql-zoned-plus (rest b) (rest a)))))
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

; // or %: integers only.  NAME answers the expression spelled out, and is
; asked only when the refusal is written.
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
                           (name) ".")))
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

; -1, 0 or 1: how two runs of values stand, the first pair that differs
; deciding and the shorter run first.  Inside a list or a struct a NULL is
; after every value and beside another NULL.
(def %sql-order-each
  (fn (self xs ys)
    (match
      ((and (null? xs) (null? ys)) 0)
      ((null? xs) -1)
      ((null? ys) 1)
      (#t
        (let ((a (first xs)) (b (first ys)))
          (let ((c (match
                     ((and (%sql-null? a) (%sql-null? b)) 0)
                     ((%sql-null? a) 1)
                     ((%sql-null? b) -1)
                     (#t (%sql-order a b)))))
            (if (= c 0) (self (rest xs) (rest ys)) c)))))))

; How a list stands beside a list and a struct beside a struct.  Beside
; anything else neither stands: the other would have to be made one.
(def %sql-nested-order
  (fn (_ a b)
    (let ((ta (first a)) (tb (first b)))
      (match
        ((and (%sql-list? ta) (%sql-list? tb))
          (%sql-order-each (%sql-elements a) (%sql-elements b)))
        ((and (%sql-struct? ta) (%sql-struct? tb))
          (%sql-order-each (%sql-members a) (%sql-members b)))
        (#t
          (let ((from (if (%sql-nested? tb) ta tb)) (to (if (%sql-nested? tb) tb ta)))
            (error (Str8 str "Conversion Error: Unimplemented type for cast ("
                             (%sql-type-name from) " -> " (%sql-type-name to) ")"))))))))

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
        ((and (or (%sql-zoned? ta) (%sql-zoned? tb))
              (or (%sql-moment-type? ta) (eq? ta (lit varchar)))
              (or (%sql-moment-type? tb) (eq? tb (lit varchar))))
          (let ((mx (sql-cast a (lit timestamptz))) (my (sql-cast b (lit timestamptz))))
            (if (< mx my) -1 (if (= mx my) 0 1))))
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
        ((and (eq? ta (lit blob)) (eq? tb (lit blob)))
          (if (Str8 <? x y) -1 (if (Str8 =? x y) 0 1)))
        ; Text beside a BLOB is read as one
        ((and (eq? ta (lit blob)) (eq? tb (lit varchar))) (%sql-order a (%sql-as b ta)))
        ((and (eq? ta (lit varchar)) (eq? tb (lit blob))) (%sql-order (%sql-as a tb) b))
        ((or (%sql-nested? ta) (%sql-nested? tb)) (%sql-nested-order a b))
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
;
; An operator is a static method of two values and NAME, a function that
; answers the expression spelled out.  It is a function and not the text
; because an operator is answered for every row and the text is wanted
; only in an error.

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
      (match
        ((or (eq? (first a) (lit null)) (eq? (first b) (lit null)))
          (pair (lit null) ()))
        ((or (%sql-list? (first a)) (%sql-list? (first b)))
          (%sql-lists-joined (list a b)))
        ((and (eq? (first a) (lit blob)) (eq? (first b) (lit blob)))
          (pair (lit blob)
            (if (or (%sql-null? a) (%sql-null? b)) () (Str8 append (rest a) (rest b)))))
        (#t
          (pair (lit varchar)
            (if (or (%sql-null? a) (%sql-null? b)) ()
              (Str8 append (sql-value-text a) (sql-value-text b)))))))
    (method eq (self a b name) (%sql-compare a b (fn (_ c) (= c 0))))
    (method ne (self a b name) (%sql-compare a b (fn (_ c) (not (= c 0)))))
    (method lt (self a b name) (%sql-compare a b (fn (_ c) (< c 0))))
    (method le (self a b name) (%sql-compare a b (fn (_ c) (<= c 0))))
    (method gt (self a b name) (%sql-compare a b (fn (_ c) (> c 0))))
    (method ge (self a b name) (%sql-compare a b (fn (_ c) (>= c 0))))
    ; Lists that share a value, a list that holds another's values, and
    ; one whose values another holds
    (method overlap (self a b name) (%sql-has-any "&&" (list a b)))
    (method holds (self a b name) (%sql-has-all "@>" (list a b)))
    (method held (self a b name) (%sql-has-all "<@" (list b a)))))

; --- pieces the expressions share --------------------------------------------

; Two truths, each #t, #f or nil for NULL, as AND joins them
(def %sql-both
  (fn (_ a b)
    (match
      ((or (eq? a #f) (eq? b #f)) #f)
      ((or (null? a) (null? b)) ())
      (#t #t))))

; The type E has in SCOPE, found over a row of NULLs so that nothing a row
; holds is computed; nil when even that cannot be computed.  What the
; scope holds for its windows and unnests it holds still.
(def %sql-type-in
  (fn (_ e scope)
    (guard (_ (lit null))
      (first (sql-eval e
               (if (null? scope) ()
                 (list (first scope)
                       (List repeat (List length (first scope)) ())
                       (List third scope)
                       (%sql-fourth scope)
                       (%sql-scope-windows scope))))))))

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

; The one argument of NAME, a BLOB, as its bytes; nil for a NULL
(def %sql-blob-arg
  (fn (_ name args)
    (if (eq? (first (first args)) (lit blob)) (rest (first args))
      (%sql-no-match name args))))

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
      (#t (sql-floor-mod (%sql-moment v) sql-micros-day)))))

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
; The zone NAME names, or the error of KIND that there is none
(def %sql-zone-named
  (fn (_ name kind)
    (let ((zone (sql-zone-find name)))
      (if (null? zone) (error (Str8 str kind " Error: Unknown TimeZone '" name "'!")) zone))))

; --- lists and structs -------------------------------------------------------

; A list in twos: (A B C D) as ((A B) (C D))
(def %sql-pairs
  (fn (self l)
    (if (null? l) () (pair (list (first l) (List second l)) (self (rest (rest l)))))))

; The first of ARGS is a list or a NULL constant, or the function has no
; such form
(def %sql-list-first
  (fn (_ name args)
    (when (or (null? args)
              (not (or (%sql-list? (first (first args))) (%sql-null-type? (first (first args))))))
      (%sql-no-match name args))))

; The characters of a text or the elements of a list, counted
(def %sql-length
  (fn (_ name args)
    (%sql-arity name args (list 1))
    (let ((a (first args)))
      (if (%sql-list? (first a))
        (pair (lit bigint) (if (%sql-null? a) () (List length (first (rest a)))))
        (do (%sql-texts name args)
            (pair (lit bigint) (if (%sql-null? a) () (Str length (rest a)))))))))

; An argument that is a place or a count, as an integer; nil for NULL
(def %sql-place
  (fn (_ v) (if (%sql-null? v) () (sql-cast v (lit bigint)))))

; The place in a run of N that the SQL place I names, counted from 0: I
; from 1, or from the end when below zero; nil when it names none
(def %sql-place-in
  (fn (_ i n)
    (let ((at (if (< i 0) (+ n i) (- i 1))))
      (if (and (>= at 0) (< at n)) at ()))))

; The run of places LOW to HIGH names in a run of N, as (FROM . COUNT)
; counted from 0: each end from 1, or from the end when below zero, and
; held inside the run
(def %sql-run-in
  (fn (_ low high n)
    (let ((from (%sql-max 1 (if (< low 0) (+ n low 1) low)))
          (to (%sql-min n (if (< high 0) (+ n high 1) high))))
      (pair (- from 1) (%sql-max 0 (+ (- to from) 1))))))

; Every STEP-th of ITEMS, from the first
(def %sql-stepped
  (fn (self items step)
    (if (null? items) ()
      (pair (first items) (self (List drop step items) step)))))

; The place of the field NAME among FIELDS, from I, or nil
(def %sql-field-place
  (fn (self name fields i)
    (match
      ((null? fields) ())
      ((sql-same-name? (first (first fields)) name) i)
      (#t (self name (rest fields) (+ i 1))))))

; The field KEY of the struct S
(def %sql-struct-field
  (fn (_ s key)
    (let ((i (%sql-field-place key (rest (first s)) 0)))
      (when (null? i)
        (error (Str8 str "Binder Error: Could not find key \"" key "\" in struct")))
      (pair (List second (List ref i (rest (first s))))
            (if (%sql-null? s) () (List ref i (rest s)))))))

; The member of the tuple S at the place the integer value I says, from 1
(def %sql-tuple-member
  (fn (_ s i)
    (let ((n (List length (rest (first s)))) (at (rest i)))
      (unless (%sql-tuple? (first s))
        (error "Binder Error: struct_extract with an integer key can only be used on unnamed structs, use a string key instead"))
      (when (or (null? at) (< at 1) (> at n))
        (error (Str8 str "Binder Error: Key index " (if (null? at) "NULL" at)
                         " for struct_extract out of range - expected an index between 1 and " n)))
      (pair (List second (List ref (- at 1) (rest (first s))))
            (if (%sql-null? s) () (List ref (- at 1) (rest s)))))))

; A struct's field: the one a text names, or the member of a tuple at a
; place
(def %sql-struct-part
  (fn (_ name args)
    (let ((s (first args)) (key (List second args)))
      (match
        ((eq? (first key) (lit varchar)) (%sql-struct-field s (rest key)))
        ((%sql-int? (first key)) (%sql-tuple-member s key))
        (#t (%sql-no-match name args))))))

; The I-th element of a list or character of a text, or the field of a
; struct that a text names
(def %sql-extract
  (fn (_ name args)
    (%sql-arity name args (list 2))
    (let ((a (first args)) (i (List second args)))
      (match
        ((%sql-struct? (first a))
          (%sql-struct-part name args))
        ((%sql-list? (first a))
          (let ((at (%sql-place i)))
            (pair (List second (first a))
              (if (or (%sql-null? a) (null? at)) ()
                (let ((place (%sql-place-in at (List length (first (rest a))))))
                  (if (null? place) () (List ref place (first (rest a)))))))))
        ((eq? (first a) (lit varchar))
          (let ((at (%sql-place i)))
            (pair (lit varchar)
              (if (or (%sql-null? a) (null? at)) ()
                (let ((place (%sql-place-in at (Str length (rest a)))))
                  (if (null? place) "" (Str sub place 1 (rest a))))))))
        (#t (%sql-no-match name args))))))

; A run of a list or a text.  OPEN says which ends were not written: such
; an end is the run's own.  A NULL end that was written makes a NULL.
(def %sql-slice
  (fn (_ name args open)
    (%sql-arity name args (list 3 4))
    (let ((a (first args))
          (step (if (null? (List drop 3 args)) 1 (%sql-place (List ref 3 args))))
          (low (if (first open) 1 (%sql-place (List second args))))
          (high (if (List second open) -1 (%sql-place (List third args)))))
      (match
        ((%sql-list? (first a))
          (pair (first a)
            (if (or (%sql-null? a) (null? low) (null? high) (null? step)) ()
              (let ((run (%sql-run-in low high (List length (first (rest a))))))
                (when (< step 1)
                  (error "Not implemented Error: a slice with a step below one"))
                (list (%sql-stepped
                        (List take (rest run) (List drop (first run) (first (rest a))))
                        step))))))
        ((eq? (first a) (lit varchar))
          (pair (lit varchar)
            (if (or (%sql-null? a) (null? low) (null? high)) ()
              (let ((run (%sql-run-in low high (Str length (rest a)))))
                (if (> (rest run) 0) (Str sub (first run) (rest run) (rest a)) "")))))
        (#t (%sql-no-match name args))))))

; The type that lists of TYPES join into, or the error of two that do not
; go together
(def %sql-joined-type
  (fn (_ types)
    (let ((known (List reject %sql-null-type? types)))
      (let ((joined (guard (_ ())
                      (if (List all? %sql-list? known) (sql-common-type types) ()))))
        (when (null? joined)
          (let ((other (List find (fn (_ t) (not (equal? t (first known)))) known)))
            (error (Str8 str "Binder Error: Cannot concatenate "
                             (if (List all? %sql-list? known) "lists of " "")
                             "types " (%sql-type-name (first known)) " and "
                             (%sql-type-name other)
                             " - an explicit cast is required"))))
        joined))))

; Lists end to end, in the type they all go into.  A NULL is passed over,
; and the answer is one when every list is.
(def %sql-lists-joined
  (fn (_ args)
    (let ((t (%sql-joined-type (List map first args)))
          (held (List reject %sql-null? args)))
      (pair t
        (if (or (%sql-null-type? t) (null? held)) ()
          (list (List flat-map (fn (_ a) (first (sql-cast a t))) held)))))))

; A list with X at one end, in the type both go into
(def %sql-with-one
  (fn (_ l x at-end)
    (let ((t (sql-common-type
               (list (if (%sql-null-type? (first l)) (lit null) (List second (first l)))
                     (first x)))))
      (let ((own (if (%sql-null? l) () (List map (fn (_ e) (sql-cast e t)) (%sql-elements l))))
            (one (list (sql-cast x t))))
        (pair (list (lit list) t)
              (list (if at-end (List append own one) (List append one own))))))))

; ITEMS sorted, DOWN for the greatest first, the NULLs first or last
(def %sql-list-sorted
  (fn (_ items down nulls-first)
    (let ((nulls (List filter %sql-null? items))
          (sorted (List sort
                    (fn (_ a b) (if down (> (%sql-order a b) 0) (< (%sql-order a b) 0)))
                    (List reject %sql-null? items))))
      (if nulls-first (List append nulls sorted) (List append sorted nulls)))))

; What a word of list_sort says, among CHOICES of (WORD . ANSWER); the
; answer OTHERWISE when the word is not given
(def %sql-sort-word
  (fn (_ arg choices otherwise enum)
    (if (or (null? arg) (%sql-null? arg)) otherwise
      (let ((choice (List find (fn (_ c) (Str8 ci=? (first c) (rest arg))) choices)))
        (when (null? choice)
          (error (Str8 str "Not implemented Error: Enum value: unrecognized value \""
                           (Str8 upcase (rest arg)) "\" for enum \"" enum "\"")))
        (rest choice)))))

(def %sql-sort-ways (list (pair "ASC" #f) (pair "DESC" #t)))
(def %sql-sort-nulls (list (pair "NULLS FIRST" #t) (pair "NULLS LAST" #f)))

; A function of one list: NULL for a NULL list, else F of its elements.
; ANSWERS is the type of the answer, or says which it is: list for the
; list's own, element for its element's.
(def %sql-of-list
  (fn (_ name args counts answers f)
    (%sql-arity name args counts)
    (%sql-list-first name args)
    (let ((a (first args)))
      (if (%sql-null-type? (first a)) (pair (lit null) ())
        (pair (match
                ((eq? answers (lit list)) (first a))
                ((eq? answers (lit element)) (List second (first a)))
                (#t answers))
              (if (%sql-null? a) () (f (%sql-elements a))))))))

; The whole numbers from FROM by STEP that are before TO, or up to it
; when INCLUSIVE
(def %sql-range
  (fn (self from to step inclusive)
    (if (or (= step 0)
            (if (> step 0) (if inclusive (> from to) (>= from to))
              (if inclusive (< from to) (<= from to))))
      ()
      (pair from (self (+ from step) to step inclusive)))))

(def %sql-ranged
  (fn (_ name args inclusive)
    (%sql-arity name args (list 1 2 3))
    (let ((ns (List map %sql-place args)))
      (pair (list (lit list) (lit bigint))
        (if (List any? (fn (_ n) (null? n)) ns) ()
          (list (match
                  ((null? (rest ns)) (%sql-range 0 (first ns) 1 inclusive))
                  ((null? (rest (rest ns)))
                    (%sql-range (first ns) (List second ns) 1 inclusive))
                  (#t (%sql-range (first ns) (List second ns) (List third ns) inclusive)))))))))

; The sum of a list's elements, the NULLs left out, as sum adds a column
(def %sql-list-sum
  (fn (_ name args)
    (%sql-arity name args (list 1))
    (%sql-list-first name args)
    (let ((a (first args)))
      (let ((t (if (%sql-null-type? (first a)) (lit null) (List second (first a))))
            (values (if (%sql-null? a) () (List reject %sql-null? (%sql-elements a)))))
        (match
          ((%sql-int? t) (%sql-total (lit hugeint) values (%sql-limit (lit hugeint))))
          ((%sql-decimal? t)
            (%sql-total (list (lit decimal) %sql-decimal-width (List third t))
                        values (sql-pow10 %sql-decimal-width)))
          ((%sql-float? t)
            (pair (lit double)
              (if (null? values) ()
                (List fold (fn (_ acc v) (+ acc (rest v))) (rest (first values)) (rest values)))))
          ((%sql-null-type? t) (pair (lit hugeint) ()))
          (#t (error (Str8 str "Binder Error: No function matches the given name and argument types 'sum("
                               (%sql-type-name t) ")'."))))))))

; The least or the greatest of a list's elements, the NULLs left out
(def %sql-list-extreme
  (fn (_ name args pick)
    (%sql-of-list name args (list 1) (lit element)
      (fn (_ es)
        (let ((held (List reject %sql-null? es)))
          (if (null? held) ()
            (rest (List fold (fn (_ best v) (if (pick (%sql-order v best)) v best))
                             (first held) (rest held)))))))))

; The type of a list's elements; null for a NULL constant
(def %sql-element-type
  (fn (_ v) (if (%sql-null-type? (first v)) (lit null) (List second (first v)))))

; ARGS are as many as COUNTS says, each a list or a NULL constant, or the
; function has no such form
(def %sql-all-lists
  (fn (_ name args counts)
    (%sql-arity name args counts)
    (unless (List all? (fn (_ a) (or (%sql-list? (first a)) (%sql-null-type? (first a)))) args)
      (%sql-no-match name args))))

; Two lists as values of the one type their elements go into: (TYPE AS BS),
; a NULL list as no value.  ANSWER is what the function's form answers,
; for the error of two types that do not go together.
(def %sql-two-lists
  (fn (_ name args answer)
    (%sql-all-lists name args (list 2))
    (let ((t (guard (_ (error (Str8 str "Binder Error: Cannot deduce template type 'T' in function: '"
                                       name "(T[], T[]) -> " answer "'")))
               (sql-common-type (List map %sql-element-type args)))))
      (pair t
        (List map
          (fn (_ a)
            (if (%sql-null? a) ()
              (List map (fn (_ e) (pair t (sql-cast e t))) (%sql-elements a))))
          args)))))

; X, which is not NULL, is among ES
(def %sql-held?
  (fn (_ x es)
    (List any? (fn (_ e) (and (not (%sql-null? e)) (= (%sql-order e x) 0))) es)))

; Whether two lists share a value, and whether the first holds every
; value of the second.  A NULL among the elements is no value.
(def %sql-has-any
  (fn (_ name args)
    (let ((both (%sql-two-lists name args "BOOLEAN")))
      (pair (lit boolean)
        (if (%sql-any-null? args) ()
          (List any? (fn (_ x) (and (not (%sql-null? x)) (%sql-held? x (List second both))))
                     (List third both)))))))

(def %sql-has-all
  (fn (_ name args)
    (let ((both (%sql-two-lists name args "BOOLEAN")))
      (pair (lit boolean)
        (if (%sql-any-null? args) ()
          (List all? (fn (_ x) (or (%sql-null? x) (%sql-held? x (List second both))))
                     (List third both)))))))

; The values of ES that are not NULL
(def %sql-known (fn (_ es) (List reject %sql-null? es)))

; A list's elements as text with SEP between, the NULLs left out; NULL
; when none is left
(def %sql-list-text
  (fn (_ name args sep)
    (%sql-of-list name args (list 1) (lit varchar)
      (fn (_ es)
        (let ((held (%sql-known es)))
          (if (null? held) () (Str8 join sep (List map sql-value-text held))))))))

; The elements of a list of truths joined as AND joins them when EVERY,
; else as OR does, the NULLs left out
(def %sql-list-truth
  (fn (_ name args every)
    (%sql-arity name args (list 1))
    (%sql-list-first name args)
    (unless (List includes? (%sql-element-type (first args)) (list (lit boolean) (lit null)))
      (error "Binder Error: No matching aggregate function"))
    (%sql-of-list name args (list 1) (lit boolean)
      (fn (_ es)
        (let ((held (List map rest (%sql-known es))))
          (match
            ((null? held) ())
            (every (if (List all? (fn (_ x) x) held) #t #f))
            (#t (if (List any? (fn (_ x) x) held) #t #f))))))))

; A list N times over
(def %sql-list-repeated
  (fn (_ args)
    (let ((l (first args)) (n (List second args)))
      (unless (or (%sql-int? (first n)) (%sql-null-type? (first n))) (%sql-no-match "repeat" args))
      (if (%sql-null-type? (first n)) (pair (lit null) ())
        (pair (first l)
          (if (or (%sql-null? l) (%sql-null? n)) ()
            (list (List flat-map (fn (_ own) own)
                                 (List repeat (%sql-max 0 (rest n)) (first (rest l)))))))))))

; The elements of OWN that MASK is true beside, a NULL where MASK goes
; past them
(def %sql-masked
  (fn (self mask own)
    (let ((after (if (null? own) () (rest own))))
      (match
        ((null? mask) ())
        ((first mask) (pair (if (null? own) () (first own)) (self (rest mask) after)))
        (#t (self (rest mask) after))))))

; A list's second argument is a list of ELEMENT values, none of them
; NULL, or the function has no such form
(def %sql-second-list
  (fn (_ name args element?)
    (%sql-all-lists name args (list 2))
    (let ((t (%sql-element-type (List second args))))
      (unless (or (element? t) (%sql-null-type? t)) (%sql-no-match name args)))
    (when (and (not (%sql-null? (List second args)))
               (List any? %sql-null? (%sql-elements (List second args))))
      (error "Invalid Input Error: NULLs are not allowed as list elements in the second input parameter."))))

; A function of a list and a list that picks from it: NULL for a NULL
; constant on either side, else F of the x values of each
(def %sql-picked
  (fn (_ args f)
    (let ((l (first args)) (by (List second args)))
      (if (or (%sql-null-type? (first l)) (%sql-null-type? (first by))) (pair (lit null) ())
        (pair (first l)
          (if (or (%sql-null? l) (%sql-null? by)) ()
            (list (f (first (rest l)) (first (rest by))))))))))

; The aggregates list_aggregate knows by name
(def %sql-list-aggregates
  (list "sum" "min" "max" "avg" "count" "first" "last" "any_value" "product"
        "string_agg" "bool_and" "bool_or"))

(def-class SqlFunction ()
  (static
    ; Its arguments as a list, in the type they all go into.  A string
    ; constant beside values of another type is read as one of that type.
    (method list_value (self args node)
      (let ((firm (List filter (fn (_ t) (not (null? t)))
                    (List map (fn (_ a n) (if (eq? (first n) (lit str)) () (first a)))
                              args (List third node)))))
        (let ((common (guard (_ (error (Str8 str "Binder Error: Cannot deduce template type 'T' in function: 'list_value("
                                               (Str8 join ", " (List repeat (List length args) "T"))
                                               ") -> T[]'")))
                        (sql-common-type firm))))
          (let ((t (if (and (%sql-null-type? common)
                            (not (= (List length firm) (List length args))))
                     (lit varchar)
                     common)))
            (pair (list (lit list) t) (list (List map (fn (_ a) (sql-cast a t)) args)))))))
    (method list_pack (self args node) (SqlFunction list_value args node))
    ; Its arguments in twos, a name and a value
    (method struct_pack (self args node)
      (when (null? args) (%sql-no-match "struct_pack" args))
      (let ((pairs (%sql-pairs args)))
        (pair (pair (lit struct)
                (List map (fn (_ p) (list (rest (first p)) (first (List second p)))) pairs))
              (List map (fn (_ p) (rest (List second p))) pairs))))
    (method struct_extract (self args node)
      (%sql-arity "struct_extract" args (list 2))
      (unless (%sql-struct? (first (first args))) (%sql-no-match "struct_extract" args))
      (%sql-struct-part "struct_extract" args))
    ; Its arguments as a tuple, a struct whose fields have no names
    (method row (self args node)
      (when (null? args) (error "Not implemented Error: a row of nothing"))
      (pair (pair (lit struct) (List map (fn (_ a) (list "" (first a))) args))
            (List map rest args)))
    ; A list of tuples: the first elements of every list, then the second,
    ; and so on.  A shorter list is filled out with NULLs, or, when a
    ; truth is written last and is true, the longer are cut to it.  A NULL
    ; list is an empty one.
    (method list_zip (self args node)
      (when (null? args) (error "Binder Error: Provide at least one argument to list_zip"))
      (let ((flagged (eq? (first (List last args)) (lit boolean))))
        (let ((lists (if flagged (List take (- (List length args) 1) args) args)))
          (when (null? lists)
            (error "Binder Error: Provide at least one list argument to list_zip"))
          (unless (List all? (fn (_ l) (or (%sql-list? (first l)) (%sql-null-type? (first l)))) lists)
            (error "Binder Error: Parameter type needs to be List"))
          (let ((held (List map (fn (_ l) (if (%sql-null? l) () (first (rest l)))) lists)))
            (let ((lengths (List map (fn (_ l) (List length l)) held)))
              (pair (list (lit list)
                      (pair (lit struct)
                        (List map
                          (fn (_ l) (list "" (if (%sql-list? (first l)) (List second (first l)) (lit null))))
                          lists)))
                    (list (List map
                            (fn (_ k)
                              (List map (fn (_ l n) (if (< k n) (List ref k l) ())) held lengths))
                            (List range 0
                              (if (and flagged (eq? (rest (List last args)) #t))
                                (List fold (fn (_ a b) (if (< b a) b a)) (first lengths) lengths)
                                (List fold (fn (_ a b) (if (> b a) b a)) 0 lengths)))))))))))
    (method array_zip (self args node) (SqlFunction list_zip args node))
    (method array_extract (self args node) (%sql-extract "array_extract" args))
    (method list_extract (self args node) (%sql-extract "list_extract" args))
    (method list_element (self args node) (%sql-extract "list_element" args))
    (method list_slice (self args node)
      (let ((form (List drop 4 node)))
        (%sql-slice "list_slice" args
          (if (null? form) (list #f #f) (rest (first form))))))
    (method array_slice (self args node) (%sql-slice "array_slice" args (list #f #f)))
    ; Whether a list holds a value: NULL when the list or the value is
    (method list_contains (self args node)
      (%sql-arity "list_contains" args (list 2))
      (%sql-list-first "list_contains" args)
      (let ((l (first args)) (x (List second args)))
        (pair (lit boolean)
          (if (or (%sql-null? l) (%sql-null? x)) ()
            (List any? (fn (_ e) (and (not (%sql-null? e)) (= (%sql-order e x) 0)))
                       (%sql-elements l))))))
    (method list_has (self args node) (SqlFunction list_contains args node))
    (method array_contains (self args node) (SqlFunction list_contains args node))
    (method array_has (self args node) (SqlFunction list_contains args node))
    ; Where a list first holds a value, counted from 1; NULL when it does not
    (method list_position (self args node)
      (%sql-arity "list_position" args (list 2))
      (%sql-list-first "list_position" args)
      (let ((l (first args)) (x (List second args)))
        (pair (lit integer)
          (if (or (%sql-null? l) (%sql-null? x)) ()
            ((fn (self es i)
               (match
                 ((null? es) ())
                 ((and (not (%sql-null? (first es))) (= (%sql-order (first es) x) 0)) i)
                 (#t (self (rest es) (+ i 1)))))
             (%sql-elements l) 1)))))
    (method list_indexof (self args node) (SqlFunction list_position args node))
    (method array_position (self args node) (SqlFunction list_position args node))
    (method array_indexof (self args node) (SqlFunction list_position args node))
    (method list_concat (self args node)
      (when (null? args) (%sql-no-match "list_concat" args))
      (%sql-lists-joined args))
    (method list_cat (self args node) (SqlFunction list_concat args node))
    (method array_concat (self args node) (SqlFunction list_concat args node))
    (method array_cat (self args node) (SqlFunction list_concat args node))
    (method list_append (self args node)
      (%sql-arity "list_append" args (list 2))
      (%sql-list-first "list_append" args)
      (%sql-with-one (first args) (List second args) #t))
    (method array_append (self args node) (SqlFunction list_append args node))
    (method array_push_back (self args node) (SqlFunction list_append args node))
    (method list_prepend (self args node)
      (%sql-arity "list_prepend" args (list 2))
      (%sql-list-first "list_prepend" (list (List second args)))
      (%sql-with-one (List second args) (first args) #f))
    (method array_prepend (self args node) (SqlFunction list_prepend args node))
    (method array_push_front (self args node)
      (%sql-arity "array_push_front" args (list 2))
      (SqlFunction list_prepend (list (List second args) (first args)) node))
    ; A list in order: the least first and the NULLs last, unless a word
    ; after the list says DESC or NULLS FIRST
    (method list_sort (self args node)
      (%sql-arity "list_sort" args (list 1 2 3))
      (let ((down (%sql-sort-word (if (null? (rest args)) () (List second args))
                                  %sql-sort-ways #f "OrderType"))
            (nulls-first (%sql-sort-word (if (null? (List drop 2 args)) () (List third args))
                                         %sql-sort-nulls #f "OrderByNullType")))
        (%sql-of-list "list_sort" args (list 1 2 3) (lit list)
          (fn (_ es) (list (List map rest (%sql-list-sorted es down nulls-first)))))))
    (method array_sort (self args node) (SqlFunction list_sort args node))
    (method list_reverse_sort (self args node)
      (%sql-arity "list_reverse_sort" args (list 1 2))
      (let ((nulls-first (%sql-sort-word (if (null? (rest args)) () (List second args))
                                         %sql-sort-nulls #f "OrderByNullType")))
        (%sql-of-list "list_reverse_sort" args (list 1 2) (lit list)
          (fn (_ es) (list (List map rest (%sql-list-sorted es #t nulls-first)))))))
    (method array_reverse_sort (self args node) (SqlFunction list_reverse_sort args node))
    (method list_reverse (self args node)
      (%sql-of-list "list_reverse" args (list 1) (lit list)
        (fn (_ es) (list (List reverse (List map rest es))))))
    (method array_reverse (self args node) (SqlFunction list_reverse args node))
    ; A list of lists as one list of their elements, a NULL among them
    ; passed over
    (method flatten (self args node)
      (%sql-arity "flatten" args (list 1))
      (unless (and (%sql-list? (first (first args)))
                   (%sql-list? (List second (first (first args)))))
        (%sql-no-match "flatten" args))
      (let ((a (first args)))
        (pair (List second (first a))
          (if (%sql-null? a) ()
            (list (List flat-map (fn (_ e) (if (%sql-null? e) () (first (rest e))))
                                 (%sql-elements a)))))))
    (method range (self args node) (%sql-ranged "range" args #f))
    (method generate_series (self args node) (%sql-ranged "generate_series" args #t))
    ; A text cut at each separator; at each character when the separator
    ; is empty
    (method string_split (self args node)
      (%sql-arity "string_split" args (list 2))
      (%sql-texts "string_split" args)
      (pair (list (lit list) (lit varchar))
        (if (%sql-any-null? args) ()
          (let ((text (rest (first args))) (sep (rest (List second args))))
            (list (if (= (Str8 length sep) 0)
                    (List map (fn (_ i) (Str sub i 1 text)) (List range 0 (Str length text)))
                    (Str8 split sep text)))))))
    (method str_split (self args node) (SqlFunction string_split args node))
    (method split (self args node) (SqlFunction string_split args node))
    (method string_to_array (self args node) (SqlFunction string_split args node))
    ; A list's elements as text with a separator between, the NULLs left out
    (method array_to_string (self args node)
      (%sql-arity "array_to_string" args (list 2))
      (%sql-list-first "array_to_string" args)
      (pair (lit varchar)
        (if (%sql-any-null? args) ()
          (Str8 join (sql-value-text (List second args))
            (List map sql-value-text (List reject %sql-null? (%sql-elements (first args))))))))
    (method list_sum (self args node) (%sql-list-sum "list_sum" args))
    (method list_min (self args node) (%sql-list-extreme "list_min" args (fn (_ c) (< c 0))))
    (method list_max (self args node) (%sql-list-extreme "list_max" args (fn (_ c) (> c 0))))
    (method list_avg (self args node)
      (%sql-of-list "list_avg" args (list 1) (lit double)
        (fn (_ es)
          (let ((held (List reject %sql-null? es)))
            (if (null? held) ()
              (/ (List fold (fn (_ acc v) (+ acc (%sql-as-double v))) (Float from 0) held)
                 (Float from (List length held))))))))
    (method list_count (self args node)
      (%sql-of-list "list_count" args (list 1) (lit bigint)
        (fn (_ es) (List length (List reject %sql-null? es)))))
    (method list_first (self args node)
      (%sql-of-list "list_first" args (list 1) (lit element)
        (fn (_ es) (if (null? es) () (rest (first es))))))
    (method list_last (self args node)
      (%sql-of-list "list_last" args (list 1) (lit element)
        (fn (_ es) (if (null? es) () (rest (first (List reverse es)))))))
    (method list_any_value (self args node)
      (%sql-of-list "list_any_value" args (list 1) (lit element)
        (fn (_ es)
          (let ((held (List reject %sql-null? es)))
            (if (null? held) () (rest (first held)))))))
    ; A list's values once each, the NULLs left out.  DuckDB promises no
    ; order of them; here each stands where it first did.
    (method list_distinct (self args node)
      (%sql-of-list "list_distinct" args (list 1) (lit list)
        (fn (_ es) (list (List map rest (%sql-once (%sql-known es) ()))))))
    (method array_distinct (self args node) (SqlFunction list_distinct args node))
    ; How many different values a list holds, the NULLs left out
    (method list_unique (self args node)
      (%sql-arity "list_unique" args (list 1))
      (%sql-list-first "list_unique" args)
      (pair (lit ubigint)
        (if (%sql-null? (first args)) ()
          (List length (%sql-once (%sql-known (%sql-elements (first args))) ())))))
    (method array_unique (self args node) (SqlFunction list_unique args node))
    ; Whether two lists share a value, and whether the first holds every
    ; value of the second; a NULL among the elements is no value
    (method list_has_any (self args node) (%sql-has-any "list_has_any" args))
    (method array_has_any (self args node) (%sql-has-any "array_has_any" args))
    (method list_has_all (self args node) (%sql-has-all "list_has_all" args))
    (method array_has_all (self args node) (%sql-has-all "array_has_all" args))
    ; The values of the first list that the second holds, once each.  A
    ; NULL first list is NULL, and a NULL second holds nothing.
    (method list_intersect (self args node)
      (let ((both (%sql-two-lists "list_intersect" args "T[]")))
        (pair (list (lit list) (first both))
          (if (%sql-null? (first args)) ()
            (list (List map rest
                    (%sql-once (List filter (fn (_ x) (%sql-held? x (List third both)))
                                            (%sql-known (List second both)))
                               ())))))))
    (method array_intersect (self args node) (SqlFunction list_intersect args node))
    ; A list made N long: cut, or filled out with NULLs or with a value
    (method list_resize (self args node)
      (%sql-arity "list_resize" args (list 2 3))
      (%sql-list-first "list_resize" args)
      (let ((l (first args)) (t (%sql-element-type (first args))))
        (let ((n (if (%sql-null? (List second args)) 0 (sql-cast (List second args) (lit ubigint))))
              (fill (if (or (null? (List drop 2 args)) (%sql-null-type? t)) ()
                      (sql-cast (List third args) t))))
          (if (%sql-null-type? (first l)) (pair (lit null) ())
            (pair (first l)
              (if (%sql-null? l) ()
                (let ((own (first (rest l))))
                  (list (if (<= n (List length own)) (List take n own)
                          (List append own (List repeat (- n (List length own)) fill)))))))))))
    (method array_resize (self args node) (SqlFunction list_resize args node))
    ; The elements a list of truths is true beside
    (method list_where (self args node)
      (%sql-second-list "list_where" args (fn (_ t) (eq? t (lit boolean))))
      (%sql-picked args (fn (_ own mask) (%sql-masked mask own))))
    (method array_where (self args node) (SqlFunction list_where args node))
    ; The elements at the places a list of places names, counted from 1;
    ; a NULL for a place the list has not
    (method list_select (self args node)
      (%sql-second-list "list_select" args %sql-int?)
      (%sql-picked args
        (fn (_ own places)
          (List map
            (fn (_ i) (if (and (>= i 1) (<= i (List length own))) (List ref (- i 1) own) ()))
            places))))
    (method array_select (self args node) (SqlFunction list_select args node))
    ; The places of a list's elements in the order list_sort would put
    ; them in, counted from 1
    (method list_grade_up (self args node)
      (%sql-arity "list_grade_up" args (list 1 2 3))
      (%sql-list-first "list_grade_up" args)
      (let ((down (%sql-sort-word (if (null? (rest args)) () (List second args))
                                  %sql-sort-ways #f "OrderType"))
            (nulls-first (%sql-sort-word (if (null? (List drop 2 args)) () (List third args))
                                         %sql-sort-nulls #f "OrderByNullType")))
        (pair (list (lit list) (lit bigint))
          (if (%sql-null? (first args)) ()
            (let ((placed (List map (fn (_ e i) (pair e i)) (%sql-elements (first args))
                                    (List range 1 (+ (List length (first (rest (first args)))) 1)))))
              (let ((nulls (List filter (fn (_ p) (%sql-null? (first p))) placed))
                    (sorted (List sort
                              (fn (_ a b)
                                (if down (> (%sql-order (first a) (first b)) 0)
                                  (< (%sql-order (first a) (first b)) 0)))
                              (List reject (fn (_ p) (%sql-null? (first p))) placed))))
                (list (List map rest
                        (if nulls-first (List append nulls sorted) (List append sorted nulls))))))))))
    (method array_grade_up (self args node) (SqlFunction list_grade_up args node))
    (method array_pop_front (self args node)
      (%sql-of-list "array_pop_front" args (list 1) (lit list)
        (fn (_ es) (list (if (null? es) () (List map rest (rest es)))))))
    (method array_pop_back (self args node)
      (%sql-of-list "array_pop_back" args (list 1) (lit list)
        (fn (_ es)
          (list (if (null? es) () (List map rest (List reverse (rest (List reverse es)))))))))
    ; A list's elements multiplied, the NULLs left out
    (method list_product (self args node)
      (%sql-arity "list_product" args (list 1))
      (%sql-list-first "list_product" args)
      (let ((t (%sql-element-type (first args))))
        (unless (or (%sql-numeric? t) (%sql-null-type? t))
          (error "Binder Error: No matching aggregate function")))
      (%sql-of-list "list_product" args (list 1) (lit double)
        (fn (_ es)
          (let ((held (%sql-known es)))
            (if (null? held) ()
              (List fold (fn (_ acc v) (* acc (%sql-as-double v))) (Float from 1) held))))))
    (method list_string_agg (self args node) (%sql-list-text "list_string_agg" args ","))
    (method list_bool_and (self args node) (%sql-list-truth "list_bool_and" args #t))
    (method list_bool_or (self args node) (%sql-list-truth "list_bool_or" args #f))
    ; An aggregate, named by a text, of a list's elements
    (method list_aggregate (self args node)
      (when (or (null? args) (null? (rest args))) (%sql-no-match "list_aggregate" args))
      (%sql-list-first "list_aggregate" args)
      (let ((name (if (%sql-null? (List second args)) "NULL" (rest (List second args)))))
        (let ((low (sql-lower name)) (more (List drop 2 args)))
          (match
            ((%sql-null-type? (first (first args))) (pair (lit null) ()))
            ((List includes? low (list "list" "array_agg")) (first args))
            ((not (List includes? low %sql-list-aggregates))
              (error (Str8 str "Catalog Error: Aggregate Function with name " name
                               " does not exist!")))
            ((and (str=? low "string_agg") (not (null? more)))
              (%sql-list-text "list_aggregate" (list (first args)) (sql-value-text (first more))))
            (#t ((class-static-ref SqlFunction (Str8 ->sym (Str8 append "list_" low)))
                 SqlFunction (list (first args)) node))))))
    (method list_aggr (self args node) (SqlFunction list_aggregate args node))
    (method array_aggregate (self args node) (SqlFunction list_aggregate args node))
    (method array_aggr (self args node) (SqlFunction list_aggregate args node))
    ; The functions that take a lambda have no form without one
    (method list_transform (self args node) (%sql-no-match (sql-lower (List second node)) args))
    (method list_apply (self args node) (SqlFunction list_transform args node))
    (method array_transform (self args node) (SqlFunction list_transform args node))
    (method array_apply (self args node) (SqlFunction list_transform args node))
    (method apply (self args node) (SqlFunction list_transform args node))
    (method list_filter (self args node) (SqlFunction list_transform args node))
    (method array_filter (self args node) (SqlFunction list_transform args node))
    (method filter (self args node) (SqlFunction list_transform args node))
    (method list_reduce (self args node) (SqlFunction list_transform args node))
    (method array_reduce (self args node) (SqlFunction list_transform args node))
    (method reduce (self args node) (SqlFunction list_transform args node))
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
    (method length (self args node) (%sql-length "length" args))
    ; How many bytes a BLOB has
    (method octet_length (self args node)
      (%sql-arity "octet_length" args (list 1))
      (let ((b (%sql-blob-arg "octet_length" args)))
        (pair (lit bigint) (if (null? b) () (Num quotient (Str8 length b) 2)))))
    ; The bytes of a BLOB, or of text, as hexadecimal digits
    (method hex (self args node)
      (%sql-arity "hex" args (list 1))
      (let ((a (first args)))
        (match
          ((eq? (first a) (lit blob)) (pair (lit varchar) (rest a)))
          ((or (eq? (first a) (lit varchar)) (%sql-null-type? (first a)))
            (pair (lit varchar) (if (%sql-null? a) () (sql-text-blob (rest a)))))
          (#t (%sql-no-match "hex" args)))))
    (method unhex (self args node)
      (%sql-arity "unhex" args (list 1))
      (%sql-texts "unhex" args)
      (pair (lit blob)
        (if (%sql-any-null? args) ()
          (%sql-unhex (rest (first args))))))
    (method from_hex (self args node) (SqlFunction unhex args node))
    ; Text as the BLOB of its bytes
    (method encode (self args node)
      (%sql-arity "encode" args (list 1))
      (%sql-texts "encode" args)
      (pair (lit blob) (if (%sql-any-null? args) () (sql-text-blob (rest (first args))))))
    (method len (self args node) (%sql-length "len" args))
    (method array_length (self args node)
      (%sql-list-first "array_length" args)
      (%sql-length "array_length" args))
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
      (if (%sql-list? (first (first args))) (%sql-list-repeated args)
        (do (%sql-texts "repeat" (list (first args)))
            (let ((n (%sql-count-arg "repeat" args (List second args))))
              (pair (lit varchar)
                (if (%sql-any-null? args) () (Str8 repeat n (rest (first args)))))))))
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
      (let ((zoned (%sql-zoned? (first (List second args)))))
        (pair (if zoned (lit timestamptz) (lit timestamp))
          (if (%sql-any-null? args) ()
            (let ((start (sql-moment-trunc (rest (first args)) (%sql-moment (List second args)))))
              (if zoned (%sql-zone-global start (sql-zone-session)) start))))))
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
    ; The clock's time, a moment the session's zone shows
    (method now (self args node)
      (%sql-arity "now" args (list 0))
      (pair (lit timestamptz) (* (Sys now) sql-micros-second)))
    (method current_timestamp (self args node) (SqlFunction now args node))
    (method current_date (self args node)
      (%sql-arity "current_date" args (list 0))
      (pair (lit date)
            (sql-floor-div (%sql-zone-local (* (Sys now) sql-micros-second) (sql-zone-session))
                           sql-micros-day)))
    ; A timestamp as the moment a zone's clock shows it, and a moment as
    ; the timestamp a zone's clock shows: AT TIME ZONE is this function
    (method timezone (self args node)
      (%sql-arity "timezone" args (list 2))
      (%sql-texts "timezone" (list (first args)))
      (%sql-moments "timezone" args (rest args))
      (let ((v (List second args)))
        (pair (if (%sql-zoned? (first v)) (lit timestamp) (lit timestamptz))
          (if (%sql-any-null? args) ()
            (let ((zone (%sql-zone-named (rest (first args)) "Not implemented")))
              (if (%sql-zoned? (first v)) (%sql-zone-local (rest v) zone)
                (%sql-zone-global (%sql-moment v) zone)))))))
    (method current_setting (self args node)
      (%sql-arity "current_setting" args (list 1))
      (%sql-texts "current_setting" args)
      (if (str=? (sql-lower (rest (first args))) "timezone")
        (pair (lit varchar) (sql-zone-name (sql-zone-session)))
        (error (Str8 str "Catalog Error: unrecognized configuration parameter \""
                         (rest (first args)) "\""))))
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

; A function's name as it is written, to the symbol its methods are named
; by: the name in lower case.  Each spelling is folded once and held; a
; call is answered for every row, and folding a name costs far more than
; finding it.
(def %sql-call-symbols (Dict make))

(def %sql-call-symbol
  (fn (_ name)
    (let ((held (%sql-call-symbols get name)))
      (if (null? held)
        (let ((made (Str8 ->sym (sql-lower name))))
          (%sql-call-symbols set! name made)
          made)
        held))))

; Whether X is one of ITEMS, the same thing and not one like it
(def %sql-among?
  (fn (self x items)
    (match
      ((null? items) #f)
      ((eq? x (first items)) #t)
      (#t (self x (rest items))))))

; The window functions' names as the symbols a call's name is
(def %sql-window-symbols (List map (fn (_ name) (Str8 ->sym name)) sql-window-functions))

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

; --- sweeping ----------------------------------------------------------------
;
; The platform sweeps what a computation left behind when it is asked to.
; A statement over many rows is one asking, and would hold every row's
; leavings until its end; so the loops that go over a statement's rows
; ask as they go.

; How many rows are answered between sweeps
(def %sql-sweep-every 200)

; ITEMS as F answers each, a sweep asked for every EVERY of them
(def %sql-swept-map-every
  (fn (_ every f items)
    (let ((go (fn (self left done n)
                (if (null? left) (List reverse done)
                  (do (when (= (Num remainder n every) 0) (Heap collect))
                      (self (rest left) (pair (f (first left)) done) (+ n 1)))))))
      (go items () 1))))

; ITEMS as F answers each
(def sql-swept-map
  (fn (_ f items) (%sql-swept-map-every %sql-sweep-every f items)))

; ITEMS as F answers each, where F itself goes over INNER rows for each: a
; sweep is asked for as often as that many rows have been gone over, and
; no less often than every item
(def sql-swept-map-over
  (fn (_ inner f items)
    (%sql-swept-map-every
      (let ((every (Num quotient %sql-sweep-every (if (< inner 1) 1 inner))))
        (if (< every 1) 1 every))
      f items)))

; The ITEMS that KEEP? is true of
(def sql-swept-filter
  (fn (_ keep? items)
    (let ((go (fn (self left kept n)
                (if (null? left) (List reverse kept)
                  (do (when (= (Num remainder n %sql-sweep-every) 0) (Heap collect))
                      (self (rest left)
                            (if (keep? (first left)) (pair (first left) kept) kept)
                            (+ n 1)))))))
      (go items () 1))))

; F called for each of ITEMS, for what it does
(def sql-swept-each
  (fn (_ f items)
    (let ((go (fn (self left n)
                (if (null? left) ()
                  (do (when (= (Num remainder n %sql-sweep-every) 0) (Heap collect))
                      (f (first left))
                      (self (rest left) (+ n 1)))))))
      (go items 1))))

; The values ARG has over a group's rows, the NULLs left out, and each
; value once when DISTINCT
(def %sql-values
  (fn (_ node scope)
    (let ((arg (first (List third node))))
      (let ((values (List filter (fn (_ v) (not (%sql-null? v)))
                      (sql-swept-map (fn (_ member) (sql-eval arg member))
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
    ; A group's values as a list, the NULLs among them; NULL for no row
    (method list (self node scope)
      (%sql-one-argument node)
      (let ((values (List map (fn (_ member) (sql-eval (first (List third node)) member))
                              (first (List third scope)))))
        (pair (list (lit list) (%sql-arg-type node scope))
          (if (null? values) ()
            (list (List map rest (if (List ref 3 node) (%sql-once values ()) values)))))))
    (method array_agg (self node scope) (SqlAggregate list node scope))
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

; --- lambdas -----------------------------------------------------------------
;
; A lambda node is (lambda NAMES BODY).  It is a value nowhere: a function
; that takes one reads the node, and answers its body for each element of
; a list, the parameters being the columns of a row of their own and the
; row the lambda was written for the row outside it.

(def %sql-lambda? (fn (_ node) (and (pair? node) (eq? (first node) (lit lambda)))))

; NODE holds a select statement, at any depth
(def %sql-queried?
  (fn (self node)
    (match
      ((not (pair? node)) #f)
      ((List includes? (first node) (list (lit subquery) (lit exists) (lit in-query))) #t)
      (#t (or (self (first node)) (self (rest node)))))))

; The scope a lambda's body is answered in: its parameters NAMES, of
; TYPES, the columns of a row holding the x values XS, and SCOPE outside.
; Where no row is outside, a name that is no parameter meets a scope of no
; table, and is refused as one with no FROM is.
(def %sql-lambda-scope
  (fn (_ names types xs scope)
    (list (List map (fn (_ n t) (sql-column "" n t)) names types)
          xs ()
          (if (null? scope) (sql-scope () () () ()) scope)
          (if (null? scope) () (%sql-scope-windows scope)))))

; The value of a lambda's body with its parameters, of TYPES, holding XS
(def %sql-lambda-value
  (fn (_ lnode types xs scope)
    (sql-eval (List third lnode)
              (%sql-lambda-scope (List second lnode) types xs scope))))

; The types of the parameters of a lambda over elements of type T: the
; element, and its place when a second parameter is named
(def %sql-lambda-types
  (fn (_ lnode t)
    (when (> (List length (List second lnode)) 2)
      (error "Binder Error: This lambda function only supports up to two lambda parameters!"))
    (if (null? (rest (List second lnode))) (list t) (list t (lit bigint)))))

; The body's value for each of ES, values of a list's elements
(def %sql-lambda-each
  (fn (_ lnode types es scope)
    (List map
      (fn (_ e i)
        (%sql-lambda-value lnode types
          (if (null? (rest types)) (list (rest e)) (list (rest e) i))
          scope))
      es (List range 1 (+ (List length es) 1)))))

; The body's type, read over parameters that are NULL
(def %sql-lambda-type
  (fn (_ lnode types scope)
    (first (%sql-lambda-value lnode types (List repeat (List length types) ()) scope))))

(def %sql-lambda-no-match
  (fn (_ node scope)
    (error (Str8 str "Binder Error: No function matches the given name and argument types '"
                     (sql-lower (List second node)) "("
                     (Str8 join ", "
                       (List map
                         (fn (_ a)
                           (if (%sql-lambda? a) "LAMBDA" (%sql-type-name (first (sql-eval a scope)))))
                         (List third node)))
                     ")'."))))

; What a call that takes a lambda is given, when it has one of COUNTS
; arguments and the second is the lambda: (LIST LAMBDA ELEMENT-TYPE)
(def %sql-lambda-read
  (fn (_ node scope counts)
    (let ((args (List third node)))
      (unless (and (List includes? (List length args) counts)
                   (%sql-lambda? (List second args))
                   (not (List any? %sql-lambda? (pair (first args) (List drop 2 args)))))
        (%sql-lambda-no-match node scope))
      (let ((lnode (List second args)))
        (when (sql-aggregated? (List third lnode))
          (error "Binder Error: aggregate functions cannot reference lambda parameters"))
        (when (%sql-queried? (List third lnode))
          (error "Binder Error: subqueries in lambda expressions are not supported"))
        (let ((l (sql-eval (first args) scope)))
          (unless (or (%sql-list? (first l)) (%sql-null-type? (first l)))
            (error "Binder Error: Invalid LIST argument during lambda function binding!"))
          (list l lnode (%sql-element-type l)))))))

; A list of the body's value for each element
(def %sql-transform
  (fn (_ node scope)
    (let ((read (%sql-lambda-read node scope (list 2))))
      (let ((l (first read)) (lnode (List second read)))
        (let ((types (%sql-lambda-types lnode (List third read))))
          (let ((t (%sql-lambda-type lnode types scope)))
            (match
              ((%sql-null-type? (first l)) (pair (lit null) ()))
              ((%sql-null? l) (pair (list (lit list) t) ()))
              (#t (pair (list (lit list) t)
                    (list (List map (fn (_ v) (sql-cast v t))
                                    (%sql-lambda-each lnode types (%sql-elements l) scope))))))))))))

; The elements the body is true of
(def %sql-filter
  (fn (_ node scope)
    (let ((read (%sql-lambda-read node scope (list 2))))
      (let ((l (first read)) (lnode (List second read)))
        (let ((types (%sql-lambda-types lnode (List third read))))
          (%sql-lambda-type lnode types scope)
          (if (or (%sql-null-type? (first l)) (%sql-null? l)) l
            (let ((es (%sql-elements l)))
              (pair (first l)
                (list (List map (fn (_ kept) (rest (first kept)))
                        (List filter (fn (_ p) (eq? (sql-cast (rest p) (lit boolean)) #t))
                          (List map (fn (_ e v) (pair e v)) es
                                    (%sql-lambda-each lnode types es scope)))))))))))))

; The type list_reduce answers in: the body's, read with the value so far
; as START's type when a start is given, and else as an element, when it
; must also be a type an element goes into
(def %sql-reduce-type
  (fn (_ lnode et start scope)
    (let ((placed (not (null? (List drop 2 (List second lnode))))))
      (let ((r (%sql-lambda-type lnode
                 (pair (if (null? start) et (first start))
                       (if placed (list et (lit bigint)) (list et)))
                 scope)))
        (let ((joined (if (null? start) (guard (_ ()) (sql-common-type (list et r))) r)))
          (when (null? joined)
            (error (Str8 str "Binder Error: No common super type between list element type "
                             (%sql-type-name et) " and lambda return type "
                             (%sql-type-name r))))
          joined)))))

; ES folded from FIRST, both values, by the body, which is given the
; value so far, an element, and the element's place when it names a third
(def %sql-reduced
  (fn (_ lnode t et first-value es from scope)
    (let ((placed (not (null? (List drop 2 (List second lnode))))))
      (List fold
        (fn (_ acc entry)
          (sql-cast
            (%sql-lambda-value lnode
              (pair t (if placed (list et (lit bigint)) (list et)))
              (pair acc (if placed (list (rest (first entry)) (rest entry))
                          (list (rest (first entry)))))
              scope)
            t))
        (sql-cast first-value t)
        (List map (fn (_ e i) (pair e i)) es
                  (List range from (+ from (List length es))))))))

; A list's elements folded into one value, from the first of them or from
; a start
(def %sql-reduce
  (fn (_ node scope)
    (let ((read (%sql-lambda-read node scope (list 2 3)))
          (given (List drop 2 (List third node))))
      (let ((l (first read)) (lnode (List second read)) (et (List third read))
            (start (if (null? given) () (sql-eval (first given) scope))))
        (unless (List includes? (List length (List second lnode)) (list 2 3))
          (error "Binder Error: list_reduce expects a function with 2 or 3 arguments"))
        (let ((t (%sql-reduce-type lnode et start scope)))
          (match
            ((%sql-null-type? (first l)) (pair (lit null) ()))
            ((%sql-null? l) (pair t ()))
            ((not (null? start))
              (pair t (%sql-reduced lnode t et start (%sql-elements l) 1 scope)))
            ((null? (%sql-elements l))
              (error "Parameter Not Allowed Error: Cannot perform list_reduce on an empty input list"))
            (#t (pair t (%sql-reduced lnode t et (first (%sql-elements l))
                                      (rest (%sql-elements l)) 2 scope)))))))))

(def-class SqlLambda ()
  (static
    (method list_transform (self node scope) (%sql-transform node scope))
    (method list_apply (self node scope) (%sql-transform node scope))
    (method array_transform (self node scope) (%sql-transform node scope))
    (method array_apply (self node scope) (%sql-transform node scope))
    (method apply (self node scope) (%sql-transform node scope))
    (method list_filter (self node scope) (%sql-filter node scope))
    (method array_filter (self node scope) (%sql-filter node scope))
    (method filter (self node scope) (%sql-filter node scope))
    (method list_reduce (self node scope) (%sql-reduce node scope))
    (method array_reduce (self node scope) (%sql-reduce node scope))
    (method reduce (self node scope) (%sql-reduce node scope))))

(def-class SqlNode ()
  (static
    ; A lambda is read by the function it is given to, and is nothing
    ; anywhere else
    (method lambda (self node scope) (error "Binder Error: invalid lambda expression"))
    ; An argument written name := value is its value to a function that
    ; reads no names
    (method named (self node scope) (sql-eval (List third node) scope))
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
    ; An unnest's value was worked out for the row before the row's items
    ; are, as a window's is; anywhere no row was made for it, it has none
    (method unnest (self node scope)
      (let ((held (if (null? scope) ()
                    (List find (fn (_ h) (same? (first h) node))
                               (%sql-scope-windows scope)))))
        (if (null? held) (error "Binder Error: UNNEST not supported here")
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
      (let ((name (%sql-call-symbol (List second node))))
       (let ((aggregate (class-static-ref SqlAggregate name)))
        (match
          ((List any? %sql-lambda? (List third node))
            (let ((taker (class-static-ref SqlLambda name)))
              (if (null? taker) (error "Binder Error: This scalar function does not support lambdas!")
                (taker SqlLambda node scope))))
          ((null? aggregate)
            (let ((function (class-static-ref SqlFunction name)))
              (when (%sql-among? name %sql-window-symbols)
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
          (#t (aggregate SqlAggregate node scope))))))
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
         (fn (_) (sql-expr-name node)))))))

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
        (pair "second" "\"second\"") (pair "quarter" "\"quarter\"")
        (pair "range" "\"range\"") (pair "filter" "\"filter\"")
        (pair "row" "\"row\"")))

(def %sql-call-name
  (fn (_ name)
    (let ((own (List find (fn (_ row) (str=? (first row) (sql-lower name))) %sql-call-names)))
      (if (null? own) (sql-lower name) (rest own)))))

; A table of a FROM spelled out: its name, a select statement in
; parentheses, or an unnest; the column names an alias gave it are not
; spelled
(def %sql-table-text
  (fn (self table)
    (match
      ((not (pair? table)) table)
      ((eq? (first table) (lit renamed)) (self (List second table)))
      ((eq? (first table) (lit unnest))
        (Str8 append "unnest(" (Str8 join ", " (List map sql-expr-name (List second table))) ")"))
      (#t (Str8 append "(" (%sql-select-text table) ")")))))

; The column names an alias gave TABLE, in parentheses; nothing when it
; gave none
(def %sql-table-names-text
  (fn (_ table)
    (if (and (pair? table) (eq? (first table) (lit renamed)))
      (Str8 append "(" (Str8 join ", " (List third table)) ")")
      "")))

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
                        (%sql-table-text (first named))
                        (if (null? (List second named)) ""
                          (Str8 append " AS " (List second named)
                                       (%sql-table-names-text (first named)))))))
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

; NODE is a field written with points alone: column.field, as the
; executor marks one, or a field of such a field or of a column named
; with its table
(def sql-pointed?
  (fn (self node)
    (and (eq? (first node) (lit call)) (not (null? (List drop 4 node)))
         (let ((form (first (List ref 4 node))) (of (first (List third node))))
           (or (eq? form (lit dotted))
               (and (eq? form (lit field))
                    (or (and (eq? (first of) (lit col)) (not (null? (List third of))))
                        (self of))))))))

; A call the parser made from a form of its own, spelled as DuckDB spells
; the form back.  The form is the call node's fifth element, a list
; starting with its name.
(def-class SqlForm ()
  (static
    (method subscript (self node)
      (let ((args (List third node)))
        (Str8 append (sql-expr-name (first args)) "[" (sql-expr-name (List second args)) "]")))
    ; The ends that were not written are not shown
    (method slice (self node)
      (let ((args (List third node)) (open (rest (first (List drop 4 node)))))
        (Str8 append (sql-expr-name (first args)) "["
          (if (first open) "" (sql-expr-name (List second args))) ":"
          (if (List second open) "" (sql-expr-name (List third args)))
          (if (null? (List drop 3 args)) ""
            (Str8 append ":" (sql-expr-name (List ref 3 args))))
          "]")))
    ; A field of a value in parentheses; of a column named with its table,
    ; the three names with points between
    (method field (self node)
      (let ((args (List third node)))
        (if (sql-pointed? node)
          (Str8 append (sql-expr-name (first args)) "."
                       (%sql-key-name (List second (List second args))))
          (Str8 append "(" (sql-expr-name (first args)) ")."
                       (%sql-key-name (List second (List second args)))))))
    ; A column's field, written column.field
    (method dotted (self node)
      (let ((args (List third node)))
        (Str8 append (sql-expr-name (first args)) "."
                     (%sql-key-name (List second (List second args))))))
    (method struct (self node)
      (Str8 append "struct_pack("
        (Str8 join ", "
          (List map
            (fn (_ p) (Str8 append (%sql-key-name (List second (first p))) " := "
                                   (sql-expr-name (List second p))))
            (%sql-pairs (List third node))))
        ")"))))

(def-class SqlName ()
  (static
    ; A count of rows is count() before an OVER, count_star() elsewhere
    (method over (self node)
      (let ((call (sql-expr-name (List second node))))
        (Str8 append (if (str=? call "count_star()") "count()" call)
                     " OVER (" (Str8 join " " (%sql-window-texts node)) ")")))
    (method unnest (self node)
      (Str8 append "unnest(" (Str8 join ", " (List map sql-expr-name (List second node))) ")"))
    (method named (self node)
      (Str8 append (%sql-key-name (List second node)) " := "
                   (sql-expr-name (List third node))))
    (method lambda (self node)
      (Str8 append "(lambda " (Str8 join ", " (List second node)) ": "
                   (sql-expr-name (List third node)) ")"))
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
    ; A name that is a keyword is in double quotes
    (method col (self node)
      (if (null? (List third node)) (%sql-key-name (List second node))
        (Str8 append (%sql-key-name (List third node)) "." (%sql-key-name (List second node)))))
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
      (let ((args (List third node)) (form (List drop 4 node)))
        (match
          ((not (null? form))
            ((class-static-ref SqlForm (first (first form))) SqlForm node))
          ((and (%sql-aggregate? (List second node))
                (sql-same-name? (List second node) "count")
                (or (null? args) (eq? (first (first args)) (lit star))))
            "count_star()")
          (#t
            (Str8 append (%sql-call-name (List second node)) "("
                         (if (List ref 3 node) "DISTINCT " "")
                         (Str8 join ", " (List map sql-expr-name args))
                         ")")))))
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

; --- text as a moment with a zone ----------------------------------------------

(def %sql-digits?
  (fn (_ text)
    ((fn (self i)
       (if (>= i (Str8 length text)) (> (Str8 length text) 0)
         (if (and (>= (%sql-byte text i) 48) (<= (%sql-byte text i) 57)) (self (+ i 1)) #f)))
     0)))

; The seconds an offset's digits say, HH, HHMM or HHMMSS, or nil
(def %sql-offset-seconds
  (fn (_ digits)
    (if (not (and (%sql-digits? digits) (List includes? (Str8 length digits) (list 2 4 6)))) ()
      (let ((n (first (sql-decimal-read digits))))
        (match
          ((= (Str8 length digits) 2) (* n 3600))
          ((= (Str8 length digits) 4) (+ (* (Num quotient n 100) 3600) (* (Num remainder n 100) 60)))
          (#t (+ (* (Num quotient n 10000) 3600)
                 (* (Num remainder (Num quotient n 100) 100) 60)
                 (Num remainder n 100))))))))

; Where a date's own minus signs are over: an offset's sign comes later
(def %sql-date-width 10)

; TEXT as (BODY . ZONE): the timestamp, and after it nil, or a list of the
; seconds east of an offset written +HH[:MM[:SS]] or Z, or the name of a
; zone
(def %sql-zoned-parts
  (fn (_ text)
    (let ((space (Str8 last-index-of " " text))
          (plus (Str8 last-index-of "+" text))
          (minus (Str8 last-index-of "-" text))
          (end (Str8 length text)))
      (let ((sign (match
                    ((not (null? plus)) plus)
                    ((and (not (null? minus)) (>= minus %sql-date-width)) minus)
                    (#t ()))))
        (match
          ((and (not (null? space)) (< (+ space 1) end)
                (let ((c (%sql-byte text (+ space 1))))
                  (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)))))
            (pair (Str8 trim (Str8 sub 0 space text)) (Str8 sub (+ space 1) end text)))
          ((and (> end 1) (or (Str8 ends? "Z" text) (Str8 ends? "z" text)))
            (pair (Str8 sub 0 (- end 1) text) (list 0)))
          ((null? sign) (pair text ()))
          (#t
            (let ((seconds (%sql-offset-seconds
                             (Str8 replace ":" "" (Str8 sub (+ sign 1) end text)))))
              (if (null? seconds) (pair text ())
                (pair (Str8 trim (Str8 sub 0 sign text))
                      (list (if (eq? sign plus) seconds (- 0 seconds))))))))))))

; TEXT with the T that may stand between a date and a time made a blank
(def %sql-spaced
  (fn (_ text)
    (if (and (> (Str8 length text) %sql-date-width) (= (%sql-byte text %sql-date-width) 84))
      (Str8 append (Str8 sub 0 %sql-date-width text) " "
                   (Str8 sub (+ %sql-date-width 1) (Str8 length text) text))
      text)))

; The moment TEXT names: a timestamp on the session's clock, or on the
; clock of the offset or the zone written after it
(def %sql-zoned-read
  (fn (_ text)
    (let ((parts (%sql-zoned-parts (%sql-spaced (Str8 trim text)))))
      (let ((local (%sql-read-or sql-timestamp-read (first parts) "timestamp"
                     (Str8 append "invalid timestamp field format: \"" text
                                  "\", expected format is (YYYY-MM-DD HH:MM[:SS[.US]][±HH[:MM[:SS]]| ZONE])")))
            (zone (rest parts)))
        (match
          ((null? zone) (%sql-zone-global local (sql-zone-session)))
          ((pair? zone) (- local (* (first zone) sql-micros-second)))
          (#t (%sql-zone-global local (%sql-zone-named zone "Conversion"))))))))

(def-class SqlCast ()
  (static
    (method varchar (self v t) (sql-value-text v))
    (method blob (self v t)
      (if (eq? (first v) (lit blob)) (rest v) (%sql-blob-read (rest v))))
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
          ((or (eq? from (lit timestamp)) (%sql-zoned? from))
            (sql-floor-div (%sql-moment v) sql-micros-day))
          ((eq? from (lit varchar))
            (%sql-read-or sql-date-read x "date"
              (Str8 append "invalid date field format: \"" x "\", expected format is (YYYY-MM-DD)")))
          (#t (%sql-no-cast from t)))))
    (method timestamp (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit timestamp)) x)
          ((%sql-zoned? from) (%sql-moment v))
          ((eq? from (lit date)) (* x sql-micros-day))
          ((eq? from (lit varchar))
            (%sql-read-or sql-timestamp-read x "timestamp"
              (Str8 append "invalid timestamp field format: \"" x
                           "\", expected format is (YYYY-MM-DD HH:MM:SS[.US][±HH[:MM[:SS]]| ZONE])")))
          (#t (%sql-no-cast from t)))))
    ; A moment with a zone from one without is the moment the session's
    ; clock shows it; text may end in an offset or a zone's name
    (method timestamptz (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((%sql-zoned? from) x)
          ((%sql-moment-type? from) (%sql-zone-global (%sql-moment v) (sql-zone-session)))
          ((eq? from (lit varchar)) (%sql-zoned-read x))
          (#t (%sql-no-cast from t)))))
    (method time (self v t)
      (let ((from (first v)) (x (rest v)))
        (match
          ((eq? from (lit time)) x)
          ((%sql-zoned? from)
            (error "Conversion Error: Unimplemented type for cast (TIMESTAMP WITH TIME ZONE -> TIME)"))
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
    ; Each element as the list's element type
    (method list (self v t)
      (if (%sql-list? (first v))
        (list (List map (fn (_ e) (sql-cast e (List second t))) (%sql-elements v)))
        (%sql-no-cast (first v) t)))
    ; Each field of T from the member of its name; NULL when there is none,
    ; and a member T has no field for is left out
    (method struct (self v t)
      (unless (%sql-struct? (first v)) (%sql-no-cast (first v) t))
      (when (and (%sql-tuple? (first v)) (not (= (List length (first v)) (List length t))))
        (error (Str8 str "Mismatch Type Error: Type " (%sql-type-name (first v))
                         " does not match with " (%sql-type-name t)
                         ". Cannot cast STRUCTs of different size")))
      (let ((held (List map (fn (_ f m) (pair (first f) m)) (rest (first v)) (%sql-members v))))
        (let ((found (if (%sql-tuple? (first v)) held
                       (List map
                         (fn (_ f) (List find (fn (_ h) (sql-same-name? (first h) (first f))) held))
                         (rest t)))))
          (when (List all? (fn (_ h) (null? h)) found)
            (error (Str8 str "Binder Error: STRUCT to STRUCT cast must have at least one matching member, inputs are ("
                             (%sql-type-name (first v)) ") and (" (%sql-type-name t) ")")))
          (List map (fn (_ f h) (if (null? h) () (sql-cast (rest h) (List second f))))
                    (rest t) found))))
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
(def %sql-nested-kind (fn (_ t) (if (%sql-nested? t) (first t) ())))

; The x value of V as the type T holds it.  A list goes into a list and a
; struct into a struct; text is what either shows.  A BLOB is made of text
; and of nothing else, and makes nothing else.
(def sql-cast
  (fn (_ v t)
    (match
      ((%sql-null? v) ())
      ((and (not (eq? t (lit varchar))) (not (eq? (first v) (lit varchar)))
            (or (not (eq? (%sql-nested-kind (first v)) (%sql-nested-kind t)))
                (not (eq? (eq? (first v) (lit blob)) (eq? t (lit blob))))))
        (error (Str8 str "Conversion Error: Unimplemented type for cast ("
                         (%sql-type-name (first v)) " -> " (%sql-type-name t) ")")))
      (#t ((class-static-ref SqlCast (if (pair? t) (first t) t)) SqlCast v t)))))

; The name of every function there is to call: those of a row's values,
; those that take a lambda, those of a group, and those of a window
(def sql-function-names
  (fn (_)
    (List append
      (List map (fn (_ name) (Str8 str name))
        (List append (class-static-methods SqlFunction) (class-static-methods SqlLambda)
                     (class-static-methods SqlAggregate)))
      sql-window-functions)))

(def sql-int-type? %sql-int?)
(def sql-truth %sql-truth)
(def sql-order %sql-order)
(def sql-null? %sql-null?)

(provide sql/eval
  sql-eval sql-expr-name sql-scope sql-select-runner! sql-column
  sql-column-hidden? sql-column-hide sql-column-node sql-column-index
  sql-aggregated? sql-aggregate-call? sql-common-type sql-cast
  sql-windowed? sql-scope-windowed sql-window-aggregate
  sql-truth sql-order sql-null? sql-value-text sql-type-heading
  sql-type-name sql-numeric-type? sql-pointed? sql-function-names
  sql-text-blob sql-bytes-blob
  sql-swept-map sql-swept-map-over sql-swept-filter sql-swept-each sql-int-type?)

; # x-sql -- SQL on x-lang
;
; ## lib/sql/files.x -- a CSV or JSON file as a table, and a table as a file
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file is read whole and its columns' types are found from what it
; holds, as DuckDB finds them: a column of whole numbers is a BIGINT, one
; with a fraction a DOUBLE, one of true and false a BOOLEAN, one of dates a
; DATE, one with times a TIMESTAMP, and any other text.  An empty field of
; a CSV and a null of a JSON are NULL.  An array of a JSON file is a list
; and an object a struct, as sql/eval has those types and values.
;
; The codecs are the platform's (x/codec/csv, x/codec/json).  A value's
; kind is read with the bundle's own lexer.  A JSON file is read from
; tokens of its own, the codec reading each string and number, because
; the codec's objects keep their keys in no order and a struct's fields
; are in the order the file first has them.
;
; A format is a static method named for it, of SqlFormat to read and of
; SqlWriter to write.

(module sql/files)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/type/dict)
(import x/num/tower)
(import x/num/float)
(import x/reader/lexer)
(import x/codec/csv)
(import x/codec/json)
(import x/sys/file)
(import sql/lex sql-lex)
(import sql/eval sql-cast sql-value-text sql-null? sql-numeric-type?)
(import sql/parse sql-type-read)

; --- what a text is ----------------------------------------------------------

(def %sql-tokens
  (fn (_ text)
    (List reject (fn (_ tok) (eq? (first tok) (lit blank))) (sql-lex (Str8 trim text)))))

(def %sql-num? (fn (_ tok kind) (and (eq? (first tok) (lit num)) (= (List third tok) kind))))
(def %sql-mark?
  (fn (_ tok mark) (and (eq? (first tok) (lit op)) (str=? (List second tok) mark))))

; TOKENS start with a date's: number - number - number
(def %sql-date-shaped?
  (fn (_ tokens)
    (and (>= (List length tokens) 5)
         (%sql-num? (first tokens) 1) (%sql-mark? (List second tokens) "-")
         (%sql-num? (List third tokens) 1) (%sql-mark? (List ref 3 tokens) "-")
         (%sql-num? (List ref 4 tokens) 1))))

; The words that are a BOOLEAN in a file
(def %sql-truths (list "true" "false"))

; What a text of a file is: integer, number, boolean, date, timestamp, or
; text.  A date is three numbers with minus signs between, and a timestamp
; a date and more; whether there is such a day is the cast's to say.
(def %sql-kind
  (fn (_ text)
    (let ((tokens (%sql-tokens text)))
      (let ((unsigned (if (and (not (null? tokens)) (%sql-mark? (first tokens) "-")) (rest tokens)
                        tokens)))
        (match
          ((and (not (null? unsigned)) (null? (rest unsigned)) (%sql-num? (first unsigned) 1))
            (lit integer))
          ((and (not (null? unsigned)) (null? (rest unsigned)) (%sql-num? (first unsigned) 2))
            (lit number))
          ((and (not (null? tokens)) (null? (rest tokens)) (eq? (first (first tokens)) (lit id))
                (List includes? (Str8 downcase (List second (first tokens))) %sql-truths))
            (lit boolean))
          ((and (%sql-date-shaped? tokens) (null? (List drop 5 tokens))) (lit date))
          ((%sql-date-shaped? tokens) (lit timestamp))
          (#t (lit text)))))))

; The kinds a column holds, and the type that takes them all; narrowest
; first, so the first row every kind is in is the column's.  A column of no
; kind at all, every value NULL, is text.
(def %sql-kind-types
  (list (list (list (lit integer)) (lit bigint))
        (list (list (lit integer) (lit number)) (lit double))
        (list (list (lit boolean)) (lit boolean))
        (list (list (lit date)) (lit date))
        (list (list (lit date) (lit timestamp)) (lit timestamp))))

(def %sql-column-type
  (fn (_ kinds)
    (let ((row (if (null? kinds) ()
                 (List find
                   (fn (_ r) (List all? (fn (_ k) (List includes? k (first r))) kinds))
                   %sql-kind-types))))
      (if (null? row) (lit varchar) (List second row)))))

; The kinds among KINDS, each once; nil is a NULL's and is left out
(def %sql-kinds-present
  (fn (_ kinds)
    (List filter (fn (_ k) (List includes? k kinds))
      (list (lit integer) (lit number) (lit boolean) (lit date) (lit timestamp) (lit text)))))

; COLUMNS of values, each (VALUE . KIND) with VALUE one of sql/eval's and
; KIND nil for a NULL, as (TYPES COLUMNS): each column's type, and its
; values cast to it.  A column whose values do not all cast, whole numbers
; too wide for a BIGINT or a day there is not, is text.
(def %sql-typed-columns
  (fn (_ columns texts)
    (let ((typed (List map
                   (fn (_ column text-of)
                     (let ((t (%sql-column-type (%sql-kinds-present (List map rest column)))))
                       (let ((cast (guard (_ ())
                                     (List map (fn (_ c) (pair t (sql-cast (first c) t))) column))))
                         (if (and (null? cast) (not (null? column)))
                           (pair (lit varchar)
                                 (List map
                                   (fn (_ c)
                                     (pair (lit varchar)
                                           (if (sql-null? (first c)) () (text-of (first c)))))
                                   column))
                           (pair t cast)))))
                   columns texts)))
      (list (List map first typed) (List map rest typed)))))

; ROWS as columns, WIDTH of them; with no row every column is empty
(def %sql-as-columns
  (fn (_ rows width)
    (if (null? rows) (List repeat width ()) (List transpose rows))))

; COLUMNS as rows; with no value in the first there is no row
(def %sql-as-rows
  (fn (_ columns)
    (if (or (null? columns) (null? (first columns))) () (List transpose columns))))

; --- CSV ---------------------------------------------------------------------

; A field of a CSV as (VALUE . KIND): an empty one a NULL, and one that
; is NULLSTR, the text a file writes a NULL as, when there is one.  With
; PLAIN every field is text whatever it could be read as.
(def %sql-field
  (fn (_ text nullstr plain)
    (if (or (= (Str8 length text) 0) (and (not (null? nullstr)) (str=? text nullstr)))
      (pair (pair (lit varchar) ()) ())
      (pair (pair (lit varchar) text) (if plain (lit text) (%sql-kind text))))))

; The names an option of a function that reads a CSV may have, and the
; one each is held under
(def %sql-csv-options
  (list (pair "delim" "sep") (pair "sep" "sep") (pair "delimiter" "sep")
        (pair "header" "header") (pair "skip" "skip") (pair "nullstr" "nullstr")
        (pair "names" "names") (pair "column_names" "names")
        (pair "columns" "columns")
        (pair "types" "types") (pair "dtypes" "types") (pair "column_types" "types")
        (pair "all_varchar" "all_varchar")))

; The value OPTIONS has under NAME by any of its names; nil when none
(def %sql-csv-option
  (fn (_ options name)
    (let ((held (List find
                  (fn (_ o)
                    (let ((row (List find (fn (_ r) (str=? (first r) (first o))) %sql-csv-options)))
                      (and (not (null? row)) (str=? (rest row) name))))
                  options)))
      (if (null? held) () (rest held)))))

; An option's value as a text, a truth, and a whole number
(def %sql-option-text
  (fn (_ v) (if (null? v) () (sql-cast v (lit varchar)))))

(def %sql-option-true?
  (fn (_ v) (eq? (sql-cast v (lit boolean)) #t)))

; An option that is a struct of names and types' names, {'age': 'DOUBLE'},
; as ((NAME . TYPE) ...)
(def %sql-option-types
  (fn (_ v)
    (if (null? v) ()
      (do (unless (and (pair? (first v)) (eq? (first (first v)) (lit struct)))
            (error "Binder Error: the types of a file's columns are a struct of names and types"))
          (List map (fn (_ f text) (pair (first f) (sql-type-read text)))
                    (rest (first v)) (rest v))))))

; TEXT without its first N lines
(def %sql-lines-skipped
  (fn (self text n)
    (if (< n 1) text
      (let ((at (Str8 index-of "\n" text)))
        (if (null? at) ""
          (self (Str8 sub (+ at 1) (Str8 length text) text) (- n 1)))))))

; The separators a file is tried with when none is said, and how many of
; its lines are read to find which
(def %sql-separators (list "," ";" "\t" "|"))
(def %sql-sniffed-lines 20)

; The first N lines of TEXT
(def %sql-lines-first
  (fn (_ text n)
    (let ((cut (fn (self at left)
                 (if (< left 1) at
                   (let ((next (Str8 index-of "\n" (Str8 sub at (Str8 length text) text))))
                     (if (null? next) (Str8 length text) (self (+ at next 1) (- left 1))))))))
      (Str8 sub 0 (cut 0 n) text))))

; The separator of TEXT: the one of %sql-separators that reads its first
; lines as rows all of one width, the widest; a comma when none makes
; more than one column
(def %sql-separator
  (fn (_ text)
    (let ((head (%sql-lines-first text %sql-sniffed-lines)))
      (first
        (List fold
          (fn (_ best sep)
            (let ((rows (guard (_ ()) (Csv parse-by sep head))))
              (let ((width (if (null? rows) 0 (List length (first rows)))))
                (if (and (> width (rest best))
                         (List all? (fn (_ row) (= (List length row) width)) rows))
                  (pair sep width)
                  best))))
          (pair "," 1)
          %sql-separators)))))

; A column's values, each (VALUE . KIND), as the type T
(def %sql-column-as
  (fn (_ column t)
    (List map
      (fn (_ c) (pair t (if (sql-null? (first c)) () (sql-cast (first c) t))))
      column)))

; NAMES with the first of them replaced by GIVEN
(def %sql-renamed
  (fn (_ names given)
    (List append given (List drop (List length given) names))))

; A CSV's first row names its columns when every field of it is text that
; could be no other kind of value
(def %sql-header?
  (fn (_ row)
    (List all? (fn (_ field) (and (> (Str8 length field) 0) (eq? (%sql-kind field) (lit text)))) row)))

(def %sql-numbered
  (fn (_ width)
    (List map (fn (_ i) (Str8 str "column" i)) (List range 0 width))))

; --- JSON --------------------------------------------------------------------

; The bytes of a JSON number, and of true, false and null
(def %sql-json-word (list (pair 48 57) (pair 65 90) (pair 97 122) 43 45 46))

; JSON's tokens: a string with its escapes, the six marks, and a number or
; a word.  The lexer is made when a JSON text is first read, so a session
; that reads none makes no lexer, and an image written before one is read
; has none to make again when it loads.
(def %sql-json-held (Dict make))

(def %sql-json-lexer
  (fn (_)
    (unless (%sql-json-held has? (lit lexer))
      (%sql-json-held set! (lit lexer)
        (Lexer make
          (list (Lexer skip " \t\r\n")
                (Lexer quoted (lit str) 34 34 92)
                (Lexer table (lit mark) (list "{" "}" "[" "]" ":" ","))
                (Lexer run (lit word) %sql-json-word %sql-json-word)
                (Lexer any (lit other))))))
    (%sql-json-held get (lit lexer))))

(def %sql-json-malformed
  (fn (_) (error "Invalid Input Error: Malformed JSON")))

(def %sql-json-mark?
  (fn (_ tokens text)
    (and (not (null? tokens)) (eq? (first (first tokens)) (lit mark))
         (str=? (List second (first tokens)) text))))

; A JSON value read from TOKENS, as (VALUE . tokens-left).  A string, a
; number and a boolean are the codec's; a null is the symbol null; an
; array is (array VALUE ...) and an object (object (KEY . VALUE) ...), its
; keys in the order they are written, which the codec's own objects do
; not keep.
(def %sql-json-read
  (fn (_ tokens)
    (when (null? tokens) (%sql-json-malformed))
    (let ((tag (first (first tokens))) (text (List second (first tokens)))
          (after (rest tokens)))
      (match
        ((or (eq? tag (lit str)) (eq? tag (lit word)))
          (pair (guard (_ (%sql-json-malformed)) (Json parse text)) after))
        ((%sql-json-mark? tokens "[") (%sql-json-items after ()))
        ((%sql-json-mark? tokens "{") (%sql-json-fields after ()))
        (#t (%sql-json-malformed))))))

; An array's values, TOKENS after its bracket; ACC holds them newest first
(def %sql-json-items
  (fn (self tokens acc)
    (if (%sql-json-mark? tokens "]")
      (pair (pair (lit array) (List reverse acc)) (rest tokens))
      (let ((v (%sql-json-read tokens)))
        (match
          ((%sql-json-mark? (rest v) ",") (self (rest (rest v)) (pair (first v) acc)))
          ((%sql-json-mark? (rest v) "]")
            (pair (pair (lit array) (List reverse (pair (first v) acc))) (rest (rest v))))
          (#t (%sql-json-malformed)))))))

; An object's keys and values, TOKENS after its brace; ACC holds them
; newest first.  Of a key written twice the first is kept.
(def %sql-json-fields
  (fn (self tokens acc)
    (if (%sql-json-mark? tokens "}")
      (pair (pair (lit object) (List reverse acc)) (rest tokens))
      (do
        (unless (and (not (null? tokens)) (eq? (first (first tokens)) (lit str))
                     (%sql-json-mark? (rest tokens) ":"))
          (%sql-json-malformed))
        (let ((key (Json parse (List second (first tokens))))
              (v (%sql-json-read (rest (rest tokens)))))
          (let ((held (if (List any? (fn (_ f) (str=? (first f) key)) acc) acc
                        (pair (pair key (first v)) acc))))
            (match
              ((%sql-json-mark? (rest v) ",") (self (rest (rest v)) held))
              ((%sql-json-mark? (rest v) "}")
                (pair (pair (lit object) (List reverse held)) (rest (rest v))))
              (#t (%sql-json-malformed)))))))))

(def %sql-json-array? (fn (_ x) (and (pair? x) (eq? (first x) (lit array)))))
(def %sql-json-object? (fn (_ x) (and (pair? x) (eq? (first x) (lit object)))))

; Every value TOKENS hold, one after another
(def %sql-json-values
  (fn (self tokens acc)
    (if (null? tokens) (List reverse acc)
      (let ((v (%sql-json-read tokens)))
        (self (rest v) (pair (first v) acc))))))

; The objects of a JSON text: those of the array it is, the one it is, or
; one after another, as a file of one a line has them
(def %sql-json-objects
  (fn (_ text)
    (let ((values (%sql-json-values ((%sql-json-lexer) read-str text) ())))
      (let ((objects (if (and (not (null? values)) (null? (rest values))
                              (%sql-json-array? (first values)))
                       (rest (first values))
                       values)))
        (unless (List all? %sql-json-object? objects)
          (error "Invalid Input Error: a JSON file is read as a table when it holds objects"))
        objects))))

; A value as JSON text with nothing between its marks
(def %sql-json-emit
  (fn (self x)
    (match
      ((%sql-json-array? x)
        (Str8 append "[" (Str8 join "," (List map self (rest x))) "]"))
      ((%sql-json-object? x)
        (Str8 append "{"
          (Str8 join ","
            (List map (fn (_ f) (Str8 append (Json emit (first f)) ":" (self (rest f))))
                      (rest x)))
          "}"))
      (#t (Json emit x)))))

; --- what a JSON column holds -------------------------------------------------

; A shape says what the values of a column, or of a place inside one, are:
; nil when there is none but null, (scalar KIND ...) for the kinds of
; scalars, (list SHAPE) for arrays, (struct (KEY . SHAPE) ...) for objects
; with their keys in the order they first come, and the symbol mixed when
; they are not all one of those.

(def %sql-2^63 9223372036854775808)

; A scalar's kind.  A whole number too wide for a BIGINT is a number with
; a fraction, as DuckDB reads one.  A string that is a date or a
; timestamp is one; any other string is text, a number in it too.
(def %sql-json-kind
  (fn (_ x)
    (match
      ((or (eq? x #t) (eq? x #f)) (lit boolean))
      ((str? x)
        (let ((kind (%sql-kind x)))
          (if (or (eq? kind (lit date)) (eq? kind (lit timestamp))) kind (lit text))))
      ((Float float? x) (lit number))
      ((and (< x %sql-2^63) (>= x (- 0 %sql-2^63))) (lit integer))
      (#t (lit number)))))

(def %sql-shape-fields
  (fn (_ as bs)
    (List append
      (List map
        (fn (_ f)
          (let ((g (List find (fn (_ g) (str=? (first g) (first f))) bs)))
            (pair (first f) (if (null? g) (rest f) (%sql-shape-merged (rest f) (rest g))))))
        as)
      (List reject (fn (_ g) (List any? (fn (_ f) (str=? (first f) (first g))) as)) bs))))

; The shape that takes the values of both A and B
(def %sql-shape-merged
  (fn (self a b)
    (match
      ((null? a) b)
      ((null? b) a)
      ((or (eq? a (lit mixed)) (eq? b (lit mixed))) (lit mixed))
      ((not (eq? (first a) (first b))) (lit mixed))
      ((eq? (first a) (lit scalar))
        (pair (lit scalar)
          (List append (rest a)
            (List reject (fn (_ k) (List includes? k (rest a))) (rest b)))))
      ((eq? (first a) (lit list)) (list (lit list) (self (List second a) (List second b))))
      (#t (pair (lit struct) (%sql-shape-fields (rest a) (rest b)))))))

; The shape of one value.  An object with no key has no fields to be a
; struct of, and is mixed.
(def %sql-json-shape
  (fn (self x)
    (match
      ((eq? x (lit null)) ())
      ((%sql-json-array? x)
        (list (lit list)
          (List fold (fn (_ acc e) (%sql-shape-merged acc (self e))) () (rest x))))
      ((%sql-json-object? x)
        (if (null? (rest x)) (lit mixed)
          (pair (lit struct) (List map (fn (_ f) (pair (first f) (self (rest f)))) (rest x)))))
      (#t (list (lit scalar) (%sql-json-kind x))))))

; The type of a shape, as sql/eval has types: a list of its elements'
; type, a struct of its fields', the type of a scalar's kinds, and text
; for what is mixed or nothing but null
(def %sql-shape-type
  (fn (self shape)
    (match
      ((or (null? shape) (eq? shape (lit mixed))) (lit varchar))
      ((eq? (first shape) (lit list)) (list (lit list) (self (List second shape))))
      ((eq? (first shape) (lit struct))
        (pair (lit struct) (List map (fn (_ f) (list (first f) (self (rest f)))) (rest shape))))
      (#t (%sql-column-type (%sql-kinds-present (rest shape)))))))

; A scalar as one of sql/eval's values
(def %sql-json-scalar
  (fn (_ x)
    (match
      ((or (eq? x #t) (eq? x #f)) (pair (lit boolean) x))
      ((str? x) (pair (lit varchar) x))
      ((Float float? x) (pair (lit double) x))
      (#t (pair (lit hugeint) x)))))

; The x value of X as the type T, which SHAPE gave: a list boxed and a
; struct's fields in the type's order, as sql/eval holds them.  What is
; mixed is its JSON text.
(def %sql-json-x
  (fn (self x shape t)
    (match
      ((eq? x (lit null)) ())
      ((eq? shape (lit mixed)) (%sql-json-emit x))
      ((eq? (first shape) (lit list))
        (list (List map (fn (_ e) (self e (List second shape) (List second t))) (rest x))))
      ((eq? (first shape) (lit struct))
        (List map
          (fn (_ f field)
            (let ((held (List find (fn (_ h) (str=? (first h) (first f))) (rest x))))
              (if (null? held) () (self (rest held) (rest f) (List second field)))))
          (rest shape) (rest t)))
      (#t (sql-cast (%sql-json-scalar x) t)))))

; X as text, for a column whose values do not all go into its type: a
; scalar as it is shown, a list or an object as its JSON text
(def %sql-json-plain
  (fn (_ x)
    (match
      ((eq? x (lit null)) ())
      ((pair? x) (%sql-json-emit x))
      (#t (sql-cast (%sql-json-scalar x) (lit varchar))))))

; A column of a JSON file from its VALUES, as (TYPE . values).  When a
; value does not go into the type its kind promised, a day there is not,
; the column is text.
(def %sql-json-column
  (fn (_ values)
    (let ((shape (List fold (fn (_ acc x) (%sql-shape-merged acc (%sql-json-shape x)))
                            () values)))
      (let ((t (%sql-shape-type shape)))
        (let ((xs (guard (_ ())
                    (list (List map (fn (_ x) (%sql-json-x x shape t)) values)))))
          (if (null? xs)
            (pair (lit varchar)
                  (List map (fn (_ x) (pair (lit varchar) (%sql-json-plain x))) values))
            (pair t (List map (fn (_ x) (pair t x)) (first xs)))))))))

; The keys of OBJECTS, each once, in the order they first come
(def %sql-json-names
  (fn (_ objects)
    (let ((seen (Dict make)))
      (List reverse
        (List fold
          (fn (_ names o)
            (List fold
              (fn (_ acc f)
                (if (seen has? (first f)) acc
                  (do (seen set! (first f) #t) (pair (first f) acc))))
              names (rest o)))
          () objects)))))

; --- reading -----------------------------------------------------------------

; A table from a file's text: (NAMES TYPES ROWS), each row a list of
; sql/eval's values
(def-class SqlFormat ()
  (static
    (method csv (self text options)
      (let ((unknown (List find
                       (fn (_ o) (null? (List find (fn (_ r) (str=? (first r) (first o))) %sql-csv-options)))
                       options)))
        (unless (null? unknown)
          (error (Str8 append "Binder Error: Invalid named parameter \"" (first unknown)
                              "\" for function read_csv"))))
      (let ((body (let ((skip (%sql-csv-option options "skip")))
                    (if (null? skip) text (%sql-lines-skipped text (sql-cast skip (lit bigint))))))
            (said (%sql-option-text (%sql-csv-option options "sep")))
            (nullstr (%sql-option-text (%sql-csv-option options "nullstr")))
            (header (%sql-csv-option options "header"))
            (plain (let ((v (%sql-csv-option options "all_varchar")))
                     (and (not (null? v)) (%sql-option-true? v))))
            (columns (%sql-option-types (%sql-csv-option options "columns")))
            (types (%sql-option-types (%sql-csv-option options "types")))
            (given (let ((v (%sql-csv-option options "names")))
                     (if (null? v) () (first (rest v))))))
        (unless (or (null? said) (= (Str8 length said) 1))
          (error "Not implemented Error: a separator of more or less than one byte"))
        (let ((rows (Csv parse-by (if (null? said) (%sql-separator body) said) body)))
          (when (null? rows) (error "Invalid Input Error: the CSV file is empty"))
          (let ((width (List length (first rows))))
            (unless (List all? (fn (_ row) (= (List length row) width)) rows)
              (error "Invalid Input Error: the rows of the CSV file are not all as wide as its first"))
            (let ((headed (if (null? header)
                            (and (%sql-header? (first rows)) (not (null? (rest rows))))
                            (%sql-option-true? header))))
              (let ((fields (%sql-as-columns
                              (List map
                                (fn (_ row) (List map (fn (_ f) (%sql-field f nullstr plain)) row))
                                (if headed (rest rows) rows))
                              width))
                    (names (if (null? columns)
                             (%sql-renamed (if headed (first rows) (%sql-numbered width)) given)
                             (%sql-renamed (%sql-numbered width) (List map first columns)))))
                (let ((typed (%sql-typed-columns fields (List repeat width rest)))
                      (said-types (List append columns types)))
                  (let ((final (List map
                                 (fn (_ name t values column)
                                   (let ((own (List find
                                                (fn (_ row) (str=? (Str8 downcase (first row)) (Str8 downcase name)))
                                                said-types)))
                                     (if (null? own) (pair t values)
                                       (pair (rest own) (%sql-column-as column (rest own))))))
                                 names (first typed) (List second typed) fields)))
                    (list names
                          (List map first final)
                          (%sql-as-rows (List map rest final)))))))))))
    (method json (self text options)
      (unless (null? options)
        (error (Str8 append "Binder Error: Invalid named parameter \"" (first (first options))
                            "\" for function read_json")))
      (let ((objects (%sql-json-objects text)))
        (let ((names (%sql-json-names objects)))
          (when (null? names) (error "Invalid Input Error: the JSON file holds no object with a key"))
          (let ((columns (List map
                           (fn (_ name)
                             (%sql-json-column
                               (List map
                                 (fn (_ o)
                                   (let ((held (List find (fn (_ f) (str=? (first f) name)) (rest o))))
                                     (if (null? held) (lit null) (rest held))))
                                 objects)))
                           names)))
            (list names (List map first columns)
                  (%sql-as-rows (List map rest columns)))))))))

; The endings of a file's name that say it is JSON; any other file is CSV
(def %sql-json-endings (list ".json" ".ndjson" ".jsonl"))

; The format NAME names, or the one PATH's ending does when NAME is nil
(def sql-file-format
  (fn (_ path name)
    (match
      ((not (null? name)) (Str8 ->sym (Str8 downcase name)))
      ((List any? (fn (_ ending) (Str8 ends? ending (Str8 downcase path))) %sql-json-endings)
        (lit json))
      (#t (lit csv)))))

(def %sql-format
  (fn (_ class format)
    (let ((f (class-static-ref class format)))
      (when (null? f)
        (error (Str8 str "Not implemented Error: the file format " format)))
      f)))

; The table the file at PATH is, read as FORMAT, a name or nil, with
; OPTIONS, each (NAME . VALUE)
(def sql-file-read
  (fn (_ path format options)
    (unless (File exists? path)
      (error (Str8 append "IO Error: No files found that match the pattern \"" path "\"")))
    ((%sql-format SqlFormat (sql-file-format path format)) SqlFormat (File read-all path)
                                                           options)))

; A file's name without its directories and its ending: how its columns
; are qualified when it has no alias
(def sql-file-stem
  (fn (_ path)
    (let ((name (List last (Str8 split "/" path))))
      (let ((at (Str8 last-index-of "." name)))
        (if (or (null? at) (= at 0)) name (Str8 sub 0 at name))))))

; --- writing -----------------------------------------------------------------

; A value as JSON writes it: a number and a boolean as they are shown, a
; list as an array, a struct as an object, and anything else as a string
(def %sql-json-text
  (fn (self v)
    (let ((t (first v)))
      (match
        ((sql-null? v) "null")
        ((and (pair? t) (eq? (first t) (lit list)))
          (Str8 append "["
            (Str8 join "," (List map (fn (_ e) (self (pair (List second t) e))) (first (rest v))))
            "]"))
        ((and (pair? t) (eq? (first t) (lit struct)))
          (Str8 append "{"
            (Str8 join ","
              (List map
                (fn (_ f e) (Str8 append (Json emit (first f)) ":" (self (pair (List second f) e))))
                (rest t) (rest v)))
            "}"))
        ((or (sql-numeric-type? t) (eq? t (lit boolean))) (sql-value-text v))
        (#t (Json emit (sql-value-text v)))))))

; A result as a file's text.  HEADER says whether a CSV's first line names
; its columns, and OPTIONS its separator and the text a NULL is written
; as, a comma and nothing when they do not.
(def-class SqlWriter ()
  (static
    (method csv (self result header options)
      (let ((sep (%sql-option-text (%sql-csv-option options "sep")))
            (nullstr (%sql-option-text (%sql-csv-option options "nullstr"))))
        (Csv emit-by (if (null? sep) "," sep)
          (List append
            (if header (list (first result)) ())
            (List map
              (fn (_ row)
                (List map
                  (fn (_ v) (if (sql-null? v) (if (null? nullstr) "" nullstr) (sql-value-text v)))
                  row))
              (List third result))))))
    ; An object a line
    (method json (self result header options)
      (Str8 join ""
        (List map
          (fn (_ row)
            (Str8 append "{"
              (Str8 join ","
                (List map (fn (_ name v) (Str8 append (Json emit name) ":" (%sql-json-text v)))
                          (first result) row))
              "}\n"))
          (List third result))))))

; RESULT written to the file at PATH as FORMAT, a name or nil, with
; OPTIONS, each (NAME . VALUE)
(def sql-file-write
  (fn (_ result path format header options)
    (File write-all path
      ((%sql-format SqlWriter (sql-file-format path format)) SqlWriter result header options))
    ()))

(provide sql/files sql-file-read sql-file-write sql-file-stem sql-file-format)

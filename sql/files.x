; # x-sql -- SQL on x-lang
;
; ## sql/files.x -- a CSV or JSON file as a table, and a table as a file
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file is read whole and its columns' types are found from what it
; holds, as DuckDB finds them: a column of whole numbers is a BIGINT, one
; with a fraction a DOUBLE, one of true and false a BOOLEAN, one of dates a
; DATE, one with times a TIMESTAMP, and any other text.  An empty field of
; a CSV and a null of a JSON are NULL.
;
; The codecs are the platform's (x/codec/csv, x/codec/json).  A value's
; kind is read with the bundle's own lexer, and a JSON file's keys, which
; the codec keeps in no order, are found in the order they first come with
; a lexer of JSON's own tokens.
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
(import sql/eval sql-cast sql-value-text sql-null?)

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

; A field of a CSV as (VALUE . KIND): an empty one a NULL
(def %sql-field
  (fn (_ text)
    (if (= (Str8 length text) 0) (pair (pair (lit varchar) ()) ())
      (pair (pair (lit varchar) text) (%sql-kind text)))))

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

; JSON's tokens, for finding an object's keys in the order they come: a
; string with its escapes, the six marks, and a number or a word
(def %sql-json-lexer
  (Lexer make
    (list (Lexer skip " \t\r\n")
          (Lexer quoted (lit str) 34 34 92)
          (Lexer table (lit mark) (list "{" "}" "[" "]" ":" ","))
          (Lexer run (lit word) %sql-json-word %sql-json-word)
          (Lexer any (lit other)))))

; The keys of the objects at DEPTH in TOKENS, each once, in the order they
; first come.  OPEN holds the brackets not yet closed, innermost first;
; SEEN the keys so far, newest first.
(def %sql-json-keys
  (fn (self tokens open depth seen)
    (if (null? tokens) (List reverse seen)
      (let ((tok (first tokens)) (after (rest tokens)))
        (let ((text (List second tok)))
          (match
            ((and (eq? (first tok) (lit mark)) (or (str=? text "{") (str=? text "[")))
              (self after (pair text open) depth seen))
            ((and (eq? (first tok) (lit mark)) (or (str=? text "}") (str=? text "]")))
              (self after (if (null? open) () (rest open)) depth seen))
            ((and (eq? (first tok) (lit str)) (not (null? open)) (str=? (first open) "{")
                  (= (List length open) depth)
                  (not (null? after)) (eq? (first (first after)) (lit mark))
                  (str=? (List second (first after)) ":"))
              (let ((key (Json parse text)))
                (self after open depth (if (List includes? key seen) seen (pair key seen)))))
            (#t (self after open depth seen))))))))

; A value of a JSON object as (VALUE . KIND).  A string that is a date or
; a timestamp is one; any other string is text, a number in it too.
(def %sql-json-value
  (fn (_ x name)
    (match
      ((eq? x (lit null)) (pair (pair (lit varchar) ()) ()))
      ((or (eq? x #t) (eq? x #f)) (pair (pair (lit boolean) x) (lit boolean)))
      ((str? x)
        (let ((kind (%sql-kind x)))
          (pair (pair (lit varchar) x)
                (if (or (eq? kind (lit date)) (eq? kind (lit timestamp))) kind (lit text)))))
      ((Float float? x) (pair (pair (lit double) x) (lit number)))
      ((or (pair? x) (null? x) (Dict dict? x))
        (error (Str8 append "Not implemented Error: a list or an object as a value, in the column \""
                            name "\"")))
      (#t (pair (pair (lit hugeint) x) (lit integer))))))

; The objects of a JSON text: those of the array it is, the one it is, or
; one a line
(def %sql-json-objects
  (fn (_ text)
    (let ((whole (guard (_ (lit lines)) (Json parse text))))
      (let ((objects (match
                       ((eq? whole (lit lines))
                         (List map (fn (_ line) (Json parse line))
                           (List filter (fn (_ line) (> (Str8 length (Str8 trim line)) 0))
                                        (Str8 split "\n" text))))
                       ((Dict dict? whole) (list whole))
                       (#t whole))))
        (unless (List all? (fn (_ o) (Dict dict? o)) objects)
          (error "Invalid Input Error: a JSON file is read as a table when it holds objects"))
        objects))))

; --- reading -----------------------------------------------------------------

; A table from a file's text: (NAMES TYPES ROWS), each row a list of
; sql/eval's values
(def-class SqlFormat ()
  (static
    (method csv (self text)
      (let ((rows (Csv parse text)))
        (when (null? rows) (error "Invalid Input Error: the CSV file is empty"))
        (let ((width (List length (first rows))))
          (unless (List all? (fn (_ row) (= (List length row) width)) rows)
            (error "Invalid Input Error: the rows of the CSV file are not all as wide as its first"))
          (let ((headed (and (%sql-header? (first rows)) (not (null? (rest rows))))))
            (let ((typed (%sql-typed-columns
                           (%sql-as-columns
                             (List map (fn (_ row) (List map %sql-field row))
                                       (if headed (rest rows) rows))
                             width)
                           (List repeat width rest))))
              (list (if headed (first rows) (%sql-numbered width))
                    (first typed)
                    (%sql-as-rows (List second typed))))))))
    (method json (self text)
      (let ((objects (%sql-json-objects text)))
        (let ((names (%sql-json-keys (%sql-json-lexer read-str text) ()
                       (if (Str8 starts? "[" (Str8 trim text)) 2 1) ())))
          (when (null? names) (error "Invalid Input Error: the JSON file holds no object with a key"))
          (let ((typed (%sql-typed-columns
                         (List map
                           (fn (_ name)
                             (List map
                               (fn (_ o)
                                 (if (o has? name) (%sql-json-value (o get name) name)
                                   (pair (pair (lit varchar) ()) ())))
                               objects))
                           names)
                         (List repeat (List length names) sql-value-text))))
            (list names (first typed)
                  (%sql-as-rows (List second typed)))))))))

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

; The table the file at PATH is, read as FORMAT, a name or nil
(def sql-file-read
  (fn (_ path format)
    (unless (File exists? path)
      (error (Str8 append "IO Error: No files found that match the pattern \"" path "\"")))
    ((%sql-format SqlFormat (sql-file-format path format)) SqlFormat (File read-all path))))

; A file's name without its directories and its ending: how its columns
; are qualified when it has no alias
(def sql-file-stem
  (fn (_ path)
    (let ((name (List last (Str8 split "/" path))))
      (let ((at (Str8 last-index-of "." name)))
        (if (or (null? at) (= at 0)) name (Str8 sub 0 at name))))))

; --- writing -----------------------------------------------------------------

; A value as JSON writes it: a number as it is shown, text as a string
(def %sql-json-text
  (fn (_ v)
    (match
      ((sql-null? v) "null")
      ((List includes? (first v) (list (lit integer) (lit bigint) (lit hugeint) (lit double) (lit boolean)))
        (sql-value-text v))
      ((pair? (first v)) (sql-value-text v))
      (#t (Json emit (sql-value-text v))))))

; A result as a file's text.  HEADER says whether a CSV's first line names
; its columns.
(def-class SqlWriter ()
  (static
    (method csv (self result header)
      (Csv emit
        (List append
          (if header (list (first result)) ())
          (List map
            (fn (_ row) (List map (fn (_ v) (if (sql-null? v) "" (sql-value-text v))) row))
            (List third result)))))
    ; An object a line
    (method json (self result header)
      (Str8 join ""
        (List map
          (fn (_ row)
            (Str8 append "{"
              (Str8 join ","
                (List map (fn (_ name v) (Str8 append (Json emit name) ":" (%sql-json-text v)))
                          (first result) row))
              "}\n"))
          (List third result))))))

; RESULT written to the file at PATH as FORMAT, a name or nil
(def sql-file-write
  (fn (_ result path format header)
    (File write-all path
      ((%sql-format SqlWriter (sql-file-format path format)) SqlWriter result header))
    ()))

(provide sql/files sql-file-read sql-file-write sql-file-stem sql-file-format)

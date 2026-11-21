; # x-sql -- SQL on x-lang
;
; ## lib/sql/sqlite.x -- a table of a SQLite database file
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A SQLite file is pages of one size.  Its first hundred bytes say the size;
; the table every database has, the schema, starts on page 1 and has a row
; for each table with the page its rows start on and the statement that
; made it.  A table's rows are in a tree of pages: an interior page points
; at pages, a leaf holds rows, and a row too long for its leaf goes on
; through overflow pages.  A row is a record: a header of kinds, then the
; values, a whole number in as few bytes as hold it.
;
; The file is read a page at a time, where its bytes are, and only the
; pages of the table asked for.  A record's bytes are a list, read from
; its front: a text of the file may hold any byte, which a list holds and
; the platform's string functions do not.
;
; A column's type is DuckDB's for its declared type, by the words in it:
; INT a BIGINT, CHAR, CLOB or TEXT a VARCHAR, REAL, FLOA or DOUB a
; DOUBLE, TIME a TIMESTAMP, DATE a DATE, BOOL a BIGINT, DEC or NUM a
; DOUBLE, and anything else a VARCHAR.  A column with no declared type, or
; a BLOB, is a BLOB: a number or a text in it is the bytes it is written
; with.
;
; A view is a statement the file keeps.  It is answered here as its text,
; and run by what runs any statement, its tables the file's.
;
; A table made WITHOUT ROWID keeps its rows in the tree of an index, in the
; order of its key, each record with the key's columns first.

(module sql/sqlite)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/num/tower)
(import x/num/float)
(import x/sys/file)
(import x/core/doors char->int int& int+ int- int* int/ int< int= str-make str-byte-ref)
(import sql/words sql-lower)
(import sql/lex sql-lex)
(import sql/eval sql-cast sql-value-text sql-text-blob sql-bytes-blob)

; --- bytes -------------------------------------------------------------------
;
; A number of up to six bytes is worked out in the machine's own whole
; numbers, through the platform's doors, which make nothing as they go; a
; number of eight bytes may be wider than those and goes through the tower.

(def %sq-byte
  (fn (_ buf at) (int& (char->int (str-byte-ref buf at)) 255)))

; The N bytes of BUF from AT as one whole number, the first the highest;
; N is six or fewer
(def %sq-uint
  (fn (_ buf at n)
    (let ((go (fn (self i acc)
                (if (int= i n) acc
                  (self (int+ i 1) (int+ (int* acc 256) (%sq-byte buf (int+ at i))))))))
      (go 0 0))))

; The N bytes of BUF from AT as a list
(def %sq-bytes
  (fn (_ buf at n)
    (let ((go (fn (self i acc)
                (if (int< i 0) acc
                  (self (int- i 1) (pair (%sq-byte buf (int+ at i)) acc))))))
      (go (int- n 1) ()))))

; Two to the power K, K a whole number not below zero
(def %sq-two-to
  (fn (self k) (if (= k 0) 1 (* 2 (self (- k 1))))))

; Two to the powers the fields of a number are read with
(def %sq-2^32 (%sq-two-to 32))
(def %sq-2^48 (%sq-two-to 48))
(def %sq-2^63 (%sq-two-to 63))
(def %sq-2^64 (%sq-two-to 64))

; For a number of so many bytes, the least that is below zero in two's
; complement and what is taken from it then: bytes 0 to 6
(def %sq-signs
  (List map (fn (_ n) (if (= n 0) (pair 1 0) (pair (%sq-two-to (- (* 8 n) 1)) (%sq-two-to (* 8 n)))))
            (List range 0 7)))

; BYTES, a list of six or fewer, as one whole number, the first the highest
(def %sq-list-uint
  (fn (_ bytes) (List fold (fn (_ acc b) (int+ (int* acc 256) b)) 0 bytes)))

; The same read as a number with a sign, in two's complement.  Eight bytes
; are two halves, the higher with the sign.
(def %sq-list-int
  (fn (self bytes)
    (let ((n (List length bytes)))
      (if (int< n 7)
        (let ((u (%sq-list-uint bytes)) (sign (List ref n %sq-signs)))
          (if (int< u (first sign)) u (int- u (rest sign))))
        (+ (* (self (List take 4 bytes)) %sq-2^32)
           (%sq-list-uint (List drop 4 bytes)))))))

; How many bytes the longest varint has; its last byte is all value
(def %sq-varint-most 9)

; A varint's value as a number with a sign: a rowid below zero is written
; as the sixty-four bits of its two's complement
(def %sq-signed
  (fn (_ n) (if (>= n %sq-2^63) (- n %sq-2^64) n)))

; A varint at the front of BYTES, as (VALUE REST COUNT): seven bits a byte,
; the highest first, a byte below 128 the last, and the ninth byte whole.
; Only a ninth byte makes a number wider than the machine's.
(def %sq-varint
  (fn (_ bytes)
    (let ((go (fn (self left acc n)
                (let ((b (first left)))
                  (match
                    ((int= n 8) (list (%sq-signed (+ (* acc 256) b)) (rest left) 9))
                    ((int< b 128) (list (int+ (int* acc 128) b) (rest left) (int+ n 1)))
                    (#t (self (rest left) (int+ (int* acc 128) (int- b 128)) (int+ n 1))))))))
      (go bytes 0 0))))

; A varint of BUF at AT, as (VALUE . the place after it)
(def %sq-varint-at
  (fn (_ buf at)
    (let ((go (fn (self at acc n)
                (let ((b (%sq-byte buf at)))
                  (match
                    ((int= n 8) (pair (%sq-signed (+ (* acc 256) b)) (int+ at 1)))
                    ((int< b 128) (pair (int+ (int* acc 128) b) (int+ at 1)))
                    (#t (self (int+ at 1) (int+ (int* acc 128) (int- b 128)) (int+ n 1))))))))
      (go at 0 0))))

; --- a double from its bytes -------------------------------------------------

; The most a double is scaled by in one step, as sql/number has it
(def %sq-step 500)
(def %sq-float-two (Float from 2))

; X times 2^K, in steps a double can hold
(def %sq-scaled
  (fn (self x k)
    (match
      ((> k %sq-step)
        (self (* x (Float pow %sq-float-two (Float from %sq-step))) (- k %sq-step)))
      ((< k (- 0 %sq-step))
        (self (/ x (Float pow %sq-float-two (Float from %sq-step))) (+ k %sq-step)))
      ((>= k 0) (* x (Float pow %sq-float-two (Float from k))))
      (#t (/ x (Float pow %sq-float-two (Float from (- 0 k))))))))

; The fields of a double: how many bits its fraction has, the exponent
; field of every bit set, and what is taken from the field for the power
(def %sq-fraction-bits 52)
(def %sq-exponent-top 2047)
(def %sq-exponent-bias 1023)

; The double whose eight bytes are BYTES, the first the highest: a sign,
; an exponent field of eleven bits and a fraction of fifty-two, of which
; the first two bytes hold four.  The field of every bit set, an infinity
; or no number, is refused; a file's REAL is never one.
(def %sq-double
  (fn (_ bytes)
    (let ((top (%sq-list-uint (List take 2 bytes))))
      (let ((sign (int< 32767 top))
            (field (int& (int/ top 16) %sq-exponent-top))
            (fraction (int+ (int* (int& top 15) %sq-2^48) (%sq-list-uint (List drop 2 bytes)))))
        (when (int= field %sq-exponent-top)
          (error "Invalid Input Error: a REAL of the SQLite file is not a number"))
        (let ((x (if (int= field 0)
                   (%sq-scaled (Float from fraction)
                               (- 1 %sq-exponent-bias %sq-fraction-bits))
                   (%sq-scaled (Float from (int+ fraction (int* 16 %sq-2^48)))
                               (- field %sq-exponent-bias %sq-fraction-bits)))))
          (if sign (- (Float from 0) x) x))))))

; --- the file ----------------------------------------------------------------

; What a SQLite file starts with, and how long that is with its NUL
(def %sq-magic "SQLite format 3")
(def %sq-magic-size 16)

; How long the file's header is, and where in it are the page size, the
; bytes kept back at each page's end, and the text encoding
(def %sq-header-size 100)
(def %sq-page-size-at 16)
(def %sq-reserved-at 20)
(def %sq-encoding-at 56)
(def %sq-utf8 1)

; The page size the two bytes say when they say 1
(def %sq-largest-page 65536)

; An open file: its descriptor, its page size, and how much of a page is
; the file's to use
(def %sq-open
  (fn (_ path)
    (unless (File exists? path)
      (error (Str8 append "Invalid Error: Unable to open database \"" path
                          "\": unable to open database file")))
    (let ((fd (File open path (lit rdonly)))
          (head (str-make %sq-header-size)))
      (File read fd head %sq-header-size)
      (unless (and (str=? (bytes->str (%sq-bytes head 0 (- %sq-magic-size 1))) %sq-magic)
                   (= (%sq-byte head (- %sq-magic-size 1)) 0))
        (do (File close fd)
            (error "Invalid Input Error: the file is not a SQLite database")))
      (unless (= (%sq-uint head %sq-encoding-at 4) %sq-utf8)
        (do (File close fd)
            (error "Not implemented Error: a SQLite file whose text is UTF-16")))
      (let ((size (let ((said (%sq-uint head %sq-page-size-at 2)))
                    (if (= said 1) %sq-largest-page said)))
            (db (Dict make)))
        (db set! (lit fd) fd)
        (db set! (lit size) size)
        (db set! (lit usable) (- size (%sq-byte head %sq-reserved-at)))
        db))))

; Page N of DB, the first page 1, as a buffer of its bytes.  The buffer is
; a varint longer than the page, so that one read at the page's last byte
; reads inside it.
(def %sq-page
  (fn (_ db n)
    (let ((buf (str-make (+ (db get (lit size)) %sq-varint-most))))
      (File seek (db get (lit fd)) (* (- n 1) (db get (lit size))) (lit set))
      (File read (db get (lit fd)) buf (db get (lit size)))
      buf)))

; --- a tree of pages ---------------------------------------------------------

; The kinds of page a table's tree has
(def %sq-interior 5)
(def %sq-leaf 13)

; How long a page's own header is, by its kind, and where in it are the
; count of its cells and, of an interior page, its last page
(def %sq-leaf-header 8)
(def %sq-interior-header 12)
(def %sq-cells-at 3)
(def %sq-last-at 8)

; How many bytes say a page's number, and a cell's place
(def %sq-page-number 4)
(def %sq-cell-place 2)

; How much of a record of TOTAL bytes is on its page, by SQLite's rule:
; all of it when it fits, and when not the least the page keeps, with as
; much more as leaves the overflow pages full.  A page of an index, INDEX,
; keeps less of a long record than a leaf of a table does.
(def %sq-local
  (fn (_ usable total index)
    (let ((most (if index (- (Num quotient (* (- usable 12) 64) 255) 23) (- usable 35)))
          (least (- (Num quotient (* (- usable 12) 32) 255) 23)))
      (if (<= total most) total
        (let ((kept (+ least (Num remainder (- total least) (- usable %sq-page-number)))))
          (if (<= kept most) kept least))))))

; The LEFT bytes of a record that are on overflow pages from page N
(def %sq-overflow
  (fn (self db n left)
    (if (or (= n 0) (< left 1)) ()
      (let ((buf (%sq-page db n))
            (room (- (db get (lit usable)) %sq-page-number)))
        (let ((here (if (< left room) left room)))
          (List append (%sq-bytes buf %sq-page-number here)
                       (self db (%sq-uint buf 0 %sq-page-number) (- left here))))))))

; The TOTAL bytes of the record that starts at AT in BUF, the rest of it
; read from its overflow pages when it is longer than the page keeps
(def %sq-payload
  (fn (_ db buf at total index)
    (let ((local (%sq-local (db get (lit usable)) total index)))
      (if (= local total) (%sq-bytes buf at local)
        (List append
          (%sq-bytes buf at local)
          (%sq-overflow db (%sq-uint buf (+ at local) %sq-page-number) (- total local)))))))

; The row of a leaf's cell at AT, as (ROWID . BYTES of its record)
(def %sq-leaf-row
  (fn (_ db buf at)
    (let ((total (%sq-varint-at buf at)))
      (let ((rowid (%sq-varint-at buf (rest total))))
        (pair (first rowid) (%sq-payload db buf (rest rowid) (first total) #f))))))

; The rows of the tree whose top is page N, in the order of their rowids.
; Page 1 has the file's header before its own.  What reading the pages before
; left behind is swept at each leaf: the platform sweeps when it is asked
; to.
(def %sq-rows
  (fn (self db n)
    (let ((buf (%sq-page db n))
          (head (if (= n 1) %sq-header-size 0)))
      (let ((kind (%sq-byte buf head))
            (count (%sq-uint buf (+ head %sq-cells-at) %sq-cell-place)))
        (let ((places (fn (_ header)
                        (List map
                          (fn (_ i) (%sq-uint buf (+ head header (* i %sq-cell-place)) %sq-cell-place))
                          (List range 0 count)))))
          (match
            ((= kind %sq-leaf)
              (do (Heap collect)
                  (List map (fn (_ at) (%sq-leaf-row db buf at)) (places %sq-leaf-header))))
            ((= kind %sq-interior)
              (List append
                (List flat-map
                  (fn (_ at) (self db (%sq-uint buf at %sq-page-number)))
                  (places %sq-interior-header))
                (self db (%sq-uint buf (+ head %sq-last-at) %sq-page-number))))
            (#t (error "Invalid Input Error: the SQLite file has a page that is no page of a table"))))))))

; The kinds of page an index's tree has.  A table made WITHOUT ROWID keeps
; its rows in one: every cell is a row's record, an interior page's too.
(def %sq-index-interior 2)
(def %sq-index-leaf 10)

; The record of an index's cell whose record's length is written at AT,
; as (nil . BYTES): a row with no rowid
(def %sq-index-row
  (fn (_ db buf at)
    (let ((total (%sq-varint-at buf at)))
      (pair () (%sq-payload db buf (rest total) (first total) #t)))))

; The rows of the index tree whose top is page N, in the order of their
; keys: under an interior page, the rows of each cell's page and then the
; cell's own row, and after them all the rows of its last page
(def %sq-index-rows
  (fn (self db n)
    (let ((buf (%sq-page db n))
          (head (if (= n 1) %sq-header-size 0)))
      (let ((kind (%sq-byte buf head))
            (count (%sq-uint buf (+ head %sq-cells-at) %sq-cell-place)))
        (let ((places (fn (_ header)
                        (List map
                          (fn (_ i) (%sq-uint buf (+ head header (* i %sq-cell-place)) %sq-cell-place))
                          (List range 0 count)))))
          (match
            ((= kind %sq-index-leaf)
              (do (Heap collect)
                  (List map (fn (_ at) (%sq-index-row db buf at)) (places %sq-leaf-header))))
            ((= kind %sq-index-interior)
              (List append
                (List flat-map
                  (fn (_ at)
                    (List append
                      (self db (%sq-uint buf at %sq-page-number))
                      (list (%sq-index-row db buf (+ at %sq-page-number)))))
                  (places %sq-interior-header))
                (self db (%sq-uint buf (+ head %sq-last-at) %sq-page-number))))
            (#t (error "Invalid Input Error: the SQLite file has a page that is no page of an index"))))))))

; --- a record ----------------------------------------------------------------

; How many bytes a whole number of each of the first six kinds has
(def %sq-int-sizes (list 0 1 2 3 4 6 8))

; The value of kind K at the front of BYTES, as (VALUE . REST).  A value
; is nil for a NULL, or (int . N), (real . X), (text . TEXT) or (blob .
; BYTES), the bytes a list.
(def %sq-value
  (fn (_ k bytes)
    (match
      ((= k 0) (pair () bytes))
      ((< k 7)
        (let ((n (List ref k %sq-int-sizes)))
          (pair (pair (lit int) (%sq-list-int (List take n bytes))) (List drop n bytes))))
      ((= k 7)
        (pair (pair (lit real) (%sq-double (List take 8 bytes)))
              (List drop 8 bytes)))
      ((= k 8) (pair (pair (lit int) 0) bytes))
      ((= k 9) (pair (pair (lit int) 1) bytes))
      ((= (Num remainder k 2) 0)
        (let ((n (Num quotient (- k 12) 2)))
          (pair (pair (lit blob) (List take n bytes)) (List drop n bytes))))
      (#t
        (let ((n (Num quotient (- k 13) 2)))
          (pair (pair (lit text) (if (= n 0) "" (bytes->str (List take n bytes))))
                (List drop n bytes)))))))

; The varints BYTES is made of
(def %sq-kinds
  (fn (self bytes)
    (if (null? bytes) ()
      (let ((read (%sq-varint bytes)))
        (pair (first read) (self (List second read)))))))

; The values of the record BYTES is
(def %sq-record
  (fn (_ bytes)
    (let ((size (%sq-varint bytes)))
      (let ((kinds (%sq-kinds (List take (- (first size) (List third size)) (List second size))))
            (body (List drop (- (first size) (List third size)) (List second size))))
        (let ((go (fn (self kinds left)
                    (if (null? kinds) ()
                      (let ((v (%sq-value (first kinds) left)))
                        (pair (first v) (self (rest kinds) (rest v))))))))
          (go kinds body))))))

; --- the schema --------------------------------------------------------------

; A token's text, and whether it is one of WORDS in any case
(def %sq-text (fn (_ tok) (List second tok)))
(def %sq-word?
  (fn (_ tok words)
    (and (eq? (first tok) (lit id)) (List includes? (sql-lower (%sq-text tok)) words))))
(def %sq-mark?
  (fn (_ tok mark) (and (eq? (first tok) (lit op)) (str=? (%sq-text tok) mark))))

; TOKENS after an opening parenthesis, as (PARTS . the tokens after the
; one that closes it): PARTS what the commas at its own depth part
(def %sq-parts
  (fn (_ tokens)
    (let ((go (fn (self left depth part parts)
                (match
                  ((null? left) (pair (List reverse (pair (List reverse part) parts)) ()))
                  ((and (= depth 0) (%sq-mark? (first left) ")"))
                    (pair (List reverse (pair (List reverse part) parts)) (rest left)))
                  ((and (= depth 0) (%sq-mark? (first left) ","))
                    (self (rest left) depth () (pair (List reverse part) parts)))
                  (#t
                    (self (rest left)
                          (match
                            ((%sq-mark? (first left) "(") (+ depth 1))
                            ((%sq-mark? (first left) ")") (- depth 1))
                            (#t depth))
                          (pair (first left) part) parts))))))
      (go tokens 0 () ()))))

; The words a constraint on the whole table starts with, and the ones that
; end a column's type
(def %sq-table-words (list "constraint" "primary" "unique" "check" "foreign"))
(def %sq-type-ends
  (list "constraint" "primary" "not" "null" "unique" "check" "default" "collate"
        "references" "generated" "as"))

; A name as it is written: bare, or in quotes of any of SQLite's kinds
(def %sq-name
  (fn (_ tok)
    (let ((text (%sq-text tok)))
      (if (eq? (first tok) (lit id)) text
        (Str8 sub 1 (- (Str8 length text) 2) text)))))

; The type DuckDB reads a column of the declared type WORDS as, the words
; in lower case with nothing between them
(def %sq-type
  (fn (_ words)
    (let ((has (fn (_ parts) (List any? (fn (_ part) (Str8 includes? part words)) parts))))
      (match
        ((has (list "int")) (lit bigint))
        ((has (list "char" "clob" "text")) (lit varchar))
        ((or (= (Str8 length words) 0) (has (list "blob"))) (lit blob))
        ((has (list "real" "floa" "doub")) (lit double))
        ((has (list "time")) (lit timestamp))
        ((has (list "date")) (lit date))
        ((has (list "bool")) (lit bigint))
        ((has (list "dec" "num")) (lit double))
        (#t (lit varchar))))))

; One column of a CREATE TABLE's list, PART its tokens, as (NAME TYPE
; ROWID): ROWID whether it is the row's own number, which a column is
; when it is declared INTEGER PRIMARY KEY
(def %sq-column
  (fn (_ part)
    (let ((typed (List take-while (fn (_ tok) (not (%sq-word? tok %sq-type-ends))) (rest part)))
          (after (List drop-while (fn (_ tok) (not (%sq-word? tok %sq-type-ends))) (rest part))))
      (let ((words (sql-lower (Str8 join "" (List map %sq-text typed)))))
        (list (%sq-name (first part))
              (%sq-type words)
              (and (str=? words "integer")
                   (List any? (fn (_ tok) (%sq-word? tok (list "primary"))) after)))))))

; The names of the columns a table's PRIMARY KEY is, in the key's order:
; those of a constraint on the whole table, PRIMARY KEY (a, b), or the
; one column that is declared with it.  PARTS are the parts of the CREATE
; TABLE's list.
(def %sq-key-names
  (fn (_ parts)
    (let ((whole (List find
                   (fn (_ part)
                     (and (not (null? part)) (%sq-word? (first part) (list "primary"))))
                   parts)))
      (if (null? whole)
        (List map (fn (_ part) (%sq-name (first part)))
          (List filter
            (fn (_ part)
              (and (not (null? part)) (not (%sq-word? (first part) %sq-table-words))
                   (List any? (fn (_ tok) (%sq-word? tok (list "primary"))) (rest part))))
            parts))
        (List map (fn (_ part) (%sq-name (first part)))
          (List reject null?
            (first (%sq-parts (rest (List drop-while (fn (_ tok) (not (%sq-mark? tok "("))) whole))))))))))

; What the statement SQL made a table with, as (COLUMNS KEYS): its
; columns, each (NAME TYPE ROWID), and, of a table made WITHOUT ROWID, the
; names of its key's columns; nil for any other table.  A table WITHOUT
; ROWID has no column that is the row's own number.
(def %sq-columns
  (fn (_ sql)
    (let ((tokens (List reject
                    (fn (_ tok) (List includes? (first tok) (list (lit blank) (lit comment))))
                    (sql-lex sql))))
      (let ((parts (%sq-parts (rest (List drop-while (fn (_ tok) (not (%sq-mark? tok "("))) tokens)))))
        (let ((columns (List map %sq-column
                         (List reject
                           (fn (_ part) (or (null? part) (%sq-word? (first part) %sq-table-words)))
                           (first parts)))))
          (if (List any? (fn (_ tok) (%sq-word? tok (list "without"))) (rest parts))
            (list (List map (fn (_ c) (list (first c) (List second c) #f)) columns)
                  (%sq-key-names (first parts)))
            (list columns ())))))))

; The schema's row for the table NAME: (KIND NAME TABLE PAGE SQL), each a
; record's value
(def %sq-schema-row
  (fn (_ db name)
    (List find
      (fn (_ row)
        (and (not (null? (List second row)))
             (str=? (sql-lower (rest (List second row))) (sql-lower name))
             (List includes? (rest (first row)) (list "table" "view"))))
      (List map (fn (_ row) (%sq-record (rest row))) (%sq-rows db 1)))))

; --- reading -----------------------------------------------------------------

; A record's value as one of sql/eval's of the type T.  In a BLOB column
; a number is the bytes of its text and a text its own bytes; a BLOB in a
; column of any other type is DuckDB's error.
(def %sq-typed
  (fn (_ v t)
    (pair t
      (match
        ((null? v) ())
        ((eq? t (lit blob))
          (match
            ((eq? (first v) (lit blob)) (sql-bytes-blob (rest v)))
            ((eq? (first v) (lit int)) (sql-text-blob (sql-value-text (pair (lit bigint) (rest v)))))
            ((eq? (first v) (lit real)) (sql-text-blob (sql-value-text (pair (lit double) (rest v)))))
            (#t (sql-text-blob (rest v)))))
        ((eq? (first v) (lit int)) (sql-cast (pair (lit bigint) (rest v)) t))
        ((eq? (first v) (lit real)) (sql-cast (pair (lit double) (rest v)) t))
        ((eq? (first v) (lit text)) (sql-cast (pair (lit varchar) (rest v)) t))
        (#t (error "Mismatch Type Error: Invalid type in column: a BLOB in a column that is not one"))))))

; How many rows are read between sweeps of what reading them left behind:
; the platform sweeps when it is asked to, and a table of many rows is
; read in one asking
(def %sq-sweep-every 200)

; One row of COLUMNS from HELD, its rowid and its record's bytes
(def %sq-typed-row
  (fn (_ columns held)
    (let ((go (fn (self columns values)
                (if (null? columns) ()
                  (pair
                    (if (List third (first columns))
                      (pair (lit bigint) (first held))
                      (%sq-typed (if (null? values) () (first values))
                                 (List second (first columns))))
                    (self (rest columns) (if (null? values) () (rest values))))))))
      (go columns (%sq-record (rest held))))))

; The rows HELD, each a rowid and a record's bytes, as rows of COLUMNS
(def %sq-typed-rows
  (fn (_ columns held)
    (let ((go (fn (self left done n)
                (if (null? left) (List reverse done)
                  (do (when (= (Num remainder n %sq-sweep-every) 0) (Heap collect))
                      (self (rest left) (pair (%sq-typed-row columns (first left)) done)
                            (+ n 1)))))))
      (go held () 1))))

; Whether the column C has the name NAME, in any case
(def %sq-named?
  (fn (_ c name) (str=? (sql-lower (first c)) (sql-lower name))))

; The rows of a table made WITHOUT ROWID, whose tree starts on page N.  A
; row's record has the key's columns first, in the key's order, and then
; the rest in the table's; each row is put back in the table's order.
(def %sq-keyed-rows
  (fn (_ db columns keys n)
    (let ((stored (List append
                    (List map (fn (_ k) (List find (fn (_ c) (%sq-named? c k)) columns)) keys)
                    (List reject
                      (fn (_ c) (List any? (fn (_ k) (%sq-named? c k)) keys))
                      columns))))
      (let ((places (List map
                      (fn (_ c) (List index-of c stored))
                      columns)))
        (List map
          (fn (_ row) (List map (fn (_ at) (List ref at row)) places))
          (%sq-typed-rows stored (%sq-index-rows db n)))))))

; The table NAME of the open file DB: (NAMES TYPES ROWS), each row a list
; of sql/eval's values.  A record with fewer values than the table has
; columns, one written before a column was added, has NULLs for the rest.
(def %sq-table
  (fn (_ db name)
    (let ((row (%sq-schema-row db name)))
      (when (null? row)
        (error (Str8 append "Catalog Error: Table with name " name " does not exist!")))
      (let ((made (%sq-columns (rest (List ref 4 row)))))
        (let ((columns (first made)) (keys (List second made)))
          (list (List map first columns)
                (List map (fn (_ c) (List second c)) columns)
                (if (null? keys)
                  (%sq-typed-rows columns (%sq-rows db (rest (List ref 3 row))))
                  (%sq-keyed-rows db columns keys (rest (List ref 3 row))))))))))

; What F answers for the open file at PATH.  The file is closed whether F
; answered or an error was raised, and the error is raised again with its
; words.
(def %sq-with
  (fn (_ path f)
    (let ((db (%sq-open path)))
      (let ((read (guard (e (pair (lit failed) (Str8 str e)))
                    (pair (lit read) (f db)))))
        (File close (db get (lit fd)))
        (if (eq? (first read) (lit failed)) (error (rest read)) (rest read))))))

; The table NAME of the SQLite file at PATH, as %sq-table answers it
(def sql-sqlite-read
  (fn (_ path name) (%sq-with path (fn (_ db) (%sq-table db name)))))

; What SQLite names its own tables with at the start
(def %sq-own "sqlite_")

; The names of the tables and the views of the SQLite file at PATH, in the
; order the file has them, SQLite's own left out
(def sql-sqlite-tables
  (fn (_ path)
    (%sq-with path
      (fn (_ db)
        (List map (fn (_ row) (rest (List second row)))
          (List filter
            (fn (_ row)
              (and (not (null? (first row))) (not (null? (List second row)))
                   (List includes? (rest (first row)) (list "table" "view"))
                   (not (Str8 starts? %sq-own (sql-lower (rest (List second row)))))))
            (List map (fn (_ row) (%sq-record (rest row))) (%sq-rows db 1))))))))

; The columns of the table NAME of the SQLite file at PATH, each (NAME
; TYPE); nil for a view, whose columns its own statement says
(def sql-sqlite-columns
  (fn (_ path name)
    (%sq-with path
      (fn (_ db)
        (let ((row (%sq-schema-row db name)))
          (match
            ((null? row)
              (error (Str8 append "Catalog Error: Table with name " name " does not exist!")))
            ((str=? (rest (first row)) "view") ())
            (#t (List map (fn (_ c) (list (first c) (List second c)))
                          (first (%sq-columns (rest (List ref 4 row))))))))))))

; The tokens of TOKENS after the first AS that is inside no parentheses;
; nil when there is none
(def %sq-after-as
  (fn (_ tokens)
    (let ((go (fn (self left depth)
                (match
                  ((null? left) ())
                  ((and (= depth 0) (%sq-word? (first left) (list "as"))) (rest left))
                  (#t
                    (self (rest left)
                          (match
                            ((%sq-mark? (first left) "(") (+ depth 1))
                            ((%sq-mark? (first left) ")") (- depth 1))
                            (#t depth))))))))
      (go tokens 0))))

; The names a CREATE VIEW's TOKENS give its columns, in parentheses before
; its AS; nil when it gives none
(def %sq-view-names
  (fn (_ tokens)
    (let ((before (List take-while (fn (_ tok) (not (%sq-word? tok (list "as")))) tokens)))
      (let ((listed (List drop-while (fn (_ tok) (not (%sq-mark? tok "("))) before)))
        (if (null? listed) ()
          (List map
            (fn (_ part) (%sq-name (first part)))
            (List reject null?
              (List map
                (fn (_ part)
                  (List reject
                    (fn (_ tok) (List includes? (first tok) (list (lit blank) (lit comment))))
                    part))
                (first (%sq-parts (rest listed)))))))))))

; The view NAME of the SQLite file at PATH, as (NAMES SELECT SQL): the
; names its statement gives its columns, nil when it gives none, the
; statement it selects with, and the whole statement that made it.  Nil
; when NAME is a table, or nothing the file has.
(def sql-sqlite-view
  (fn (_ path name)
    (%sq-with path
      (fn (_ db)
        (let ((row (%sq-schema-row db name)))
          (if (or (null? row) (not (str=? (rest (first row)) "view"))) ()
            (let ((tokens (sql-lex (rest (List ref 4 row)))))
              (list (%sq-view-names tokens)
                    (Str8 join "" (List map %sq-text (%sq-after-as tokens)))
                    (rest (List ref 4 row))))))))))

(provide sql/sqlite sql-sqlite-read sql-sqlite-tables sql-sqlite-columns sql-sqlite-view)

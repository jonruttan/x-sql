; # x-sql -- SQL on x-lang
;
; ## sql/exec.x -- the tables, and what a statement does to them
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The tables are in memory, for the life of the process.  A table is
; (NAME COLUMNS ROWS): COLUMNS a list of (NAME TYPE), ROWS a list of lists
; of x values, nil for NULL, each value already of its column's type.
;
; A statement answers a result, (NAMES TYPES ROWS) with each row a list of
; sql/eval's values, or nil when it has nothing to show.  SqlStatement
; holds one static method a statement, named by the parser's head.

(module sql/exec)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/type/dict)
(import sql/eval
  sql-eval sql-expr-name sql-column-index sql-cast sql-truth sql-order
  sql-null?)

; --- the tables --------------------------------------------------------------

; A table's name in lower case to the table: names match in any case
(def %sql-tables (Dict make))

(def %sql-key (fn (_ name) (Str8 downcase name)))

(def %sql-table
  (fn (_ name)
    (let ((table (%sql-tables get (%sql-key name))))
      (if (null? table)
        (error (Str8 str "Catalog Error: Table with name " name " does not exist!"))
        table))))

(def sql-table-names
  (fn (_)
    (List sort (fn (_ a b) (Str8 <? a b))
               (List map first (%sql-tables vals)))))

; --- FROM --------------------------------------------------------------------

; A scope's columns for a FROM: (QUALIFIER NAME TYPE) each, the qualifier
; the alias when there is one and the table's name when not
(def %sql-scope-columns
  (fn (_ from)
    (let ((table (%sql-table (first from))))
      (let ((qualifier (if (null? (List second from)) (first table)
                         (List second from))))
        (List map (fn (_ c) (list qualifier (first c) (List second c)))
                  (List second table))))))

; The items a star stands for: every column, or every column of QUALIFIER
(def %sql-star
  (fn (_ qualifier columns)
    (let ((chosen (if (null? qualifier) columns
                    (List filter (fn (_ c) (Str8 ci=? (first c) qualifier))
                                 columns))))
      (match
        ((null? columns)
          (error "Binder Error: * expression without FROM clause!"))
        ((null? chosen)
          (error (Str8 str "Binder Error: Referenced table \"" qualifier
                           "\" not found!")))
        (#t
          (List map
            (fn (_ c) (list (list (lit col) (List second c) (first c)) ()))
            chosen))))))

; ITEMS with each star replaced by the items it stands for
(def %sql-expand
  (fn (_ items columns)
    (List flat-map
      (fn (_ item)
        (if (eq? (first (first item)) (lit star))
          (%sql-star (List second (first item)) columns)
          (list item)))
      items)))

; An item's heading: its alias, a column's name as the table has it, or the
; expression spelled out
(def %sql-heading
  (fn (_ item columns)
    (let ((e (first item)))
      (match
        ((not (null? (List second item))) (List second item))
        ((and (eq? (first e) (lit col)) (not (null? columns)))
          (List second
            (List ref (sql-column-index (List second e) (List third e) columns)
                      columns)))
        (#t (sql-expr-name e))))))

; --- ORDER BY ----------------------------------------------------------------

; What a term sorts by: an integer constant is the place of an item, and a
; bare name that is an item's alias is that item
(def %sql-order-expr
  (fn (_ e items)
    (match
      ((eq? (first e) (lit int))
        (let ((n (List second e)))
          (if (and (>= n 1) (<= n (List length items)))
            (first (List ref (- n 1) items))
            (error (Str8 str "Binder Error: ORDER term out of range - should be between 1 and "
                             (List length items))))))
      ((and (eq? (first e) (lit col)) (null? (List third e)))
        (let ((item (List find
                      (fn (_ i)
                        (and (not (null? (List second i)))
                             (Str8 ci=? (List second i) (List second e))))
                      items)))
          (if (null? item) e (first item))))
      (#t e))))

; -1, 0 or 1: how two values stand under one term.  A NULL is last unless
; the term says NULLS FIRST, whichever way the term sorts.
(def %sql-key-order
  (fn (_ a b term)
    (let ((nulls-first (eq? (List third term) (lit first))))
      (match
        ((and (sql-null? a) (sql-null? b)) 0)
        ((sql-null? a) (if nulls-first -1 1))
        ((sql-null? b) (if nulls-first 1 -1))
        (#t (let ((c (sql-order a b))) (if (List second term) (- 0 c) c)))))))

(def %sql-keys-order
  (fn (self xs ys terms)
    (if (null? terms) 0
      (let ((c (%sql-key-order (first xs) (first ys) (first terms))))
        (if (= c 0) (self (rest xs) (rest ys) (rest terms)) c)))))

; SCOPES in the order TERMS give; rows that tie keep their order
(def %sql-sorted
  (fn (_ scopes terms items)
    (if (null? terms) scopes
      (let ((exprs (List map (fn (_ term) (%sql-order-expr (first term) items))
                             terms)))
        (List map rest
          (List sort
            (fn (_ a b) (< (%sql-keys-order (first a) (first b) terms) 0))
            (List map
              (fn (_ s) (pair (List map (fn (_ e) (sql-eval e s)) exprs) s))
              scopes)))))))

; --- LIMIT and OFFSET --------------------------------------------------------

; The count an expression names, nil when there is none or it is NULL
(def %sql-count
  (fn (_ e)
    (if (null? e) ()
      (let ((n (sql-cast (sql-eval e ()) (lit bigint))))
        (when (and (not (null? n)) (< n 0))
          (error "Binder Error: LIMIT/OFFSET cannot be negative"))
        n))))

(def %sql-page
  (fn (_ rows offset limit)
    (let ((dropped (if (null? offset) rows (List drop offset rows))))
      (if (null? limit) dropped (List take limit dropped)))))

; --- CREATE and INSERT -------------------------------------------------------

; COLUMNS, or the error of a name given twice
(def %sql-distinct-columns
  (fn (self columns)
    (unless (null? columns)
      (when (List any? (fn (_ c) (Str8 ci=? (first c) (first (first columns))))
                       (rest columns))
        (error (Str8 str "Catalog Error: Column with name \"" (first (first columns))
                         "\" already exists!")))
      (self (rest columns)))))

; The place in COLUMNS of each of NAMES; every place in order when none is
; named
(def %sql-places
  (fn (_ table names)
    (let ((columns (List second table)))
      (if (null? names) (List range 0 (List length columns))
        (List map
          (fn (_ name)
            (let ((i (List find-index (fn (_ c) (Str8 ci=? (first c) name)) columns)))
              (if (null? i)
                (error (Str8 str "Binder Error: Table \"" (first table)
                                 "\" does not have a column with name \"" name "\""))
                i)))
          names)))))

; One row for TABLE from EXPRS, a value at each of PLACES and NULL elsewhere
(def %sql-insert-row
  (fn (_ table places named exprs)
    (let ((columns (List second table)))
      (unless (= (List length exprs) (List length places))
        (error
          (if named
            (Str8 str "Binder Error: Column name/value mismatch for insert on \""
                      (first table) "\": expected " (List length places)
                      " columns but " (List length exprs) " values were supplied")
            (Str8 str "Binder Error: table \"" (first table) "\" has "
                      (List length columns) " columns but " (List length exprs)
                      " values were supplied"))))
      (let ((given (List map
                     (fn (_ place e)
                       (pair place
                             (sql-cast (sql-eval e ())
                                       (List second (List ref place columns)))))
                     places exprs)))
        (List map
          (fn (_ j)
            (let ((g (List find (fn (_ g) (= (first g) j)) given)))
              (if (null? g) () (rest g))))
          (List range 0 (List length columns)))))))

; --- the statements ----------------------------------------------------------

; The rows of a SELECT: STMT's items over the scopes its FROM and WHERE
; leave, sorted and cut
(def %sql-select
  (fn (_ stmt columns)
    (let ((from (List third stmt)) (where (List ref 3 stmt)))
      (let ((scopes (if (null? from) (list ())
                      (List map (fn (_ row) (pair columns row))
                                (List third (%sql-table (first from)))))))
        (if (null? where) scopes
          (List filter (fn (_ s) (eq? (sql-truth (sql-eval where s)) #t))
                       scopes))))))

; The types of ITEMS' columns when no row shows them: each item's type over
; a row of NULLs
(def %sql-item-types
  (fn (_ items columns)
    (let ((scope (if (null? columns) ()
                   (pair columns (List repeat (List length columns) ())))))
      (List map (fn (_ i) (first (sql-eval (first i) scope))) items))))

(def-class SqlStatement ()
  (static
    (method select (self stmt)
      (let ((columns (if (null? (List third stmt)) ()
                       (%sql-scope-columns (List third stmt)))))
        (let ((items (%sql-expand (List second stmt) columns)))
          (let ((rows (List map
                        (fn (_ s) (List map (fn (_ i) (sql-eval (first i) s)) items))
                        (%sql-page
                          (%sql-sorted (%sql-select stmt columns) (List ref 4 stmt) items)
                          (%sql-count (List ref 6 stmt))
                          (%sql-count (List ref 5 stmt))))))
            (list (List map (fn (_ i) (%sql-heading i columns)) items)
                  (if (null? rows) (%sql-item-types items columns)
                    (List map first (first rows)))
                  rows)))))
    (method create (self stmt)
      (let ((name (List second stmt)) (columns (List third stmt)))
        (%sql-distinct-columns columns)
        (match
          ((not (%sql-tables has? (%sql-key name)))
            (%sql-tables set! (%sql-key name) (list name columns ())))
          ((List ref 3 stmt)
            (%sql-tables set! (%sql-key name) (list name columns ())))
          ((not (List ref 4 stmt))
            (error (Str8 str "Catalog Error: Table with name \"" name
                             "\" already exists!"))))
        ()))
    (method insert (self stmt)
      (let ((table (%sql-table (List second stmt))))
        (let ((places (%sql-places table (List third stmt))))
          (let ((rows (List map
                        (fn (_ exprs)
                          (%sql-insert-row table places (List third stmt) exprs))
                        (List ref 3 stmt))))
            (%sql-tables set! (%sql-key (first table))
              (list (first table) (List second table)
                    (List append (List third table) rows)))
            ()))))
    (method drop (self stmt)
      (let ((name (List second stmt)))
        (if (%sql-tables has? (%sql-key name))
          (%sql-tables del! (%sql-key name))
          (unless (List third stmt) (%sql-table name)))
        ()))))

(def sql-execute
  (fn (_ stmt) ((class-static-ref SqlStatement (first stmt)) SqlStatement stmt)))

(provide sql/exec sql-execute sql-table-names)

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
(import sql/words sql-lower sql-same-name?)
(import sql/eval
  sql-eval sql-expr-name sql-column sql-column-node sql-column-index
  sql-aggregated? sql-aggregate-call? sql-cast
  sql-truth sql-order sql-null? sql-value-text)

; --- the tables --------------------------------------------------------------

; A table's name in lower case to the table: names match in any case
(def %sql-tables (Dict make))

(def %sql-key (fn (_ name) (sql-lower name)))

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

; The columns of a table, each (NAME TYPE)
(def sql-table-columns (fn (_ name) (List second (%sql-table name))))

; --- FROM --------------------------------------------------------------------

; What FROM reads is (COLUMNS . ROWS): COLUMNS a list of
; sql/eval's columns, ROWS lists of x values.

; One table: the qualifier its alias when it has one, its name when not
(def %sql-source
  (fn (_ name alias)
    (let ((table (%sql-table name)))
      (let ((qualifier (if (null? alias) (first table) alias)))
        (pair (List map (fn (_ c) (sql-column qualifier (first c) (List second c)))
                        (List second table))
              (List third table))))))

(def %sql-nulls (fn (_ columns) (List repeat (List length columns) ())))

; LEFT joined to RIGHT: every pair of rows KEEPS? keeps, each left row's
; in turn.  A left row with none is kept beside NULLs in a left or full
; join, and a right row with none after them all in a right or full one.
(def %sql-join-rows
  (fn (_ left right kind keeps?)
    (let ((joined (List map
                    (fn (_ l)
                      (List filter keeps?
                        (List map (fn (_ r) (List append l r)) (rest right))))
                    (rest left))))
      (List append
        (List flat-map
          (fn (_ p)
            (if (and (null? (rest p))
                     (List includes? kind (list (lit left) (lit full))))
              (list (List append (first p) (%sql-nulls (first right))))
              (rest p)))
          (List zip (rest left) joined))
        (if (List includes? kind (list (lit right) (lit full)))
          (List map (fn (_ r) (List append (%sql-nulls (first left)) r))
            (List filter
              (fn (_ r)
                (List none? (fn (_ l) (keeps? (List append l r))) (rest left)))
              (rest right)))
          ())))))

(def %sql-join
  (fn (_ left right kind on)
    (when (sql-aggregated? on)
      (error "Binder Error: JOIN clause cannot contain aggregates!"))
    (let ((columns (List append (first left) (first right))))
      (pair columns
        (%sql-join-rows left right kind
          (fn (_ row)
            (if (null? on) #t
              (eq? (sql-truth (sql-eval on (list columns row ()))) #t))))))))

; Every table of a FROM, each joined to what is before it
(def %sql-from
  (fn (_ from)
    (List fold
      (fn (_ left join)
        (%sql-join left (%sql-source (List second join) (List third join))
                   (first join) (List ref 3 join)))
      (%sql-source (first (first from)) (List second (first from)))
      (rest from))))

; The items a star stands for: every column, or every column of QUALIFIER
(def %sql-star
  (fn (_ qualifier columns)
    (let ((chosen (if (null? qualifier) columns
                    (List filter (fn (_ c) (sql-same-name? (first c) qualifier))
                                 columns))))
      (match
        ((null? columns)
          (error "Binder Error: * expression without FROM clause!"))
        ((null? chosen)
          (error (Str8 str "Binder Error: Referenced table \"" qualifier
                           "\" not found!")))
        (#t
          (List map
            (fn (_ c) (list (sql-column-node (List second c) (first c)) ()))
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
            (List ref (sql-column-index e columns) columns)))
        (#t (sql-expr-name e))))))

; --- ORDER BY ----------------------------------------------------------------

; What a term of ORDER BY or GROUP BY stands for: an integer constant is
; the place of an item, and a bare name that is an item's alias is that
; item.  CLAUSE names the clause in the error of a place past the list.
(def %sql-term-expr
  (fn (_ e items clause)
    (match
      ((eq? (first e) (lit int))
        (let ((n (List second e)))
          (if (and (>= n 1) (<= n (List length items)))
            (first (List ref (- n 1) items))
            (error (Str8 str "Binder Error: " clause
                             " term out of range - should be between 1 and "
                             (List length items))))))
      ((and (eq? (first e) (lit col)) (null? (List third e)))
        (let ((item (List find
                      (fn (_ i)
                        (and (not (null? (List second i)))
                             (sql-same-name? (List second i) (List second e))))
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

; SCOPES in the order TERMS give, EXPRS what each term sorts by; rows that
; tie keep their order
(def %sql-sorted
  (fn (_ scopes terms exprs)
    (if (null? terms) scopes
      (List map rest
        (List sort
          (fn (_ a b) (< (%sql-keys-order (first a) (first b) terms) 0))
          (List map
            (fn (_ s) (pair (List map (fn (_ e) (sql-eval e s)) exprs) s))
            scopes))))))

; --- GROUP BY ----------------------------------------------------------------

; A text two lists of values share only when they are the same values: each
; value's length and text, and N for a NULL
(def %sql-values-key
  (fn (_ values)
    (Str8 join ""
      (List map
        (fn (_ v)
          (if (sql-null? v) "N"
            (let ((text (sql-value-text v)))
              (Str8 str (Str8 length text) ":" text))))
        values))))

; THINGS in lists that share a key KEY-OF answers, the lists in the order
; their keys first come and each in the order its things came
(def %sql-partition
  (fn (_ things key-of)
    (let ((held (Dict make)))
      (let ((keys (List fold
                    (fn (_ keys thing)
                      (let ((k (key-of thing)))
                        (if (held has? k)
                          (do (held set! k (pair thing (held get k))) keys)
                          (do (held set! k (list thing)) (pair k keys)))))
                    () things)))
        (List map (fn (_ k) (List reverse (held get k))) (List reverse keys))))))

; Whether a SELECT answers a row a group: it has a GROUP BY, a HAVING, or
; an aggregate among its items or its ORDER BY
(def %sql-grouped?
  (fn (_ stmt items)
    (or (not (null? (List ref 7 stmt)))
        (not (null? (List ref 8 stmt)))
        (List any? (fn (_ i) (sql-aggregated? (first i))) items)
        (List any? (fn (_ term) (sql-aggregated? (first term))) (List ref 4 stmt)))))

; What the rows are grouped by: GROUP BY's terms, or under ALL every item
; that holds no aggregate
(def %sql-group-keys
  (fn (_ group items)
    (match
      ((null? group) ())
      ((eq? group (lit all))
        (List map first
          (List reject (fn (_ i) (sql-aggregated? (first i))) items)))
      (#t
        (List map
          (fn (_ e)
            (let ((key (%sql-term-expr e items "GROUP BY")))
              (when (sql-aggregated? key)
                (error "Binder Error: GROUP BY clause cannot contain aggregates!"))
              key))
          group)))))

; Two expressions are one: the same tree, or two names for one column
(def %sql-same?
  (fn (_ a b columns)
    (or (equal? a b)
        (and (eq? (first a) (lit col)) (eq? (first b) (lit col))
             (= (sql-column-index a columns) (sql-column-index b columns))))))

; E can be answered for a group: every column in it is inside a key or an
; aggregate
(def %sql-check-grouped
  (fn (self e keys columns)
    (match
      ((List any? (fn (_ k) (%sql-same? e k columns)) keys) ())
      ((sql-aggregate-call? e) ())
      ((eq? (first e) (lit col))
        (error (Str8 str "Binder Error: column \"" (List second e)
                         "\" must appear in the GROUP BY clause or must be part of an aggregate function.")))
      (#t (%sql-check-parts (rest e) keys columns)))))

; Every expression among PARTS, at any depth of lists, checked
(def %sql-check-parts
  (fn (self parts keys columns)
    (List for-each
      (fn (_ x)
        (when (pair? x)
          (if (symbol? (first x)) (%sql-check-grouped x keys columns)
            (self x keys columns))))
      parts)))

; The scope of one group: its first row, or NULLs when it has none, and
; its rows' scopes
(def %sql-group-scope
  (fn (_ columns members)
    (list columns
          (if (or (null? members) (null? (first members))) (%sql-nulls columns)
            (List second (first members)))
          (list members))))

; SCOPES as a scope a group.  With no keys they are one group, though
; there be no row in it.
(def %sql-groups
  (fn (_ scopes keys columns)
    (if (null? keys) (list (%sql-group-scope columns scopes))
      (List map (fn (_ members) (%sql-group-scope columns members))
        (%sql-partition scopes
          (fn (_ s)
            (%sql-values-key (List map (fn (_ k) (sql-eval k s)) keys))))))))

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
      (when (List any? (fn (_ c) (sql-same-name? (first c) (first (first columns))))
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
            (let ((i (List find-index (fn (_ c) (sql-same-name? (first c) name)) columns)))
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

; The scopes a SELECT's FROM and WHERE leave: a row of the tables each, or
; one with nothing in it when there is no FROM
(def %sql-filtered
  (fn (_ stmt source)
    (let ((where (List ref 3 stmt)))
      (when (sql-aggregated? where)
        (error "Binder Error: WHERE clause cannot contain aggregates!"))
      (let ((scopes (if (null? source) (list ())
                      (List map (fn (_ row) (list (first source) row ()))
                                (rest source)))))
        (if (null? where) scopes
          (List filter (fn (_ s) (eq? (sql-truth (sql-eval where s)) #t))
                       scopes))))))

; SCOPES as the groups a grouped SELECT answers for, HAVING applied.  ITEMS
; and ORDER, what the terms of ORDER BY sort by, are checked against the
; keys first.
(def %sql-grouped
  (fn (_ stmt items order columns scopes)
    (let ((keys (%sql-group-keys (List ref 7 stmt) items))
          (having (List ref 8 stmt)))
      (List for-each (fn (_ i) (%sql-check-grouped (first i) keys columns)) items)
      (List for-each (fn (_ e) (%sql-check-grouped e keys columns)) order)
      (unless (null? having) (%sql-check-grouped having keys columns))
      (let ((groups (%sql-groups scopes keys columns)))
        (if (null? having) groups
          (List filter (fn (_ g) (eq? (sql-truth (sql-eval having g)) #t))
                       groups))))))

; The types of ITEMS' columns when no row shows them: each item's type over
; a row of NULLs, a group with no rows when GROUPED
(def %sql-item-types
  (fn (_ items columns grouped)
    (let ((scope (match
                   (grouped (%sql-group-scope columns ()))
                   ((null? columns) ())
                   (#t (list columns (%sql-nulls columns) ())))))
      (List map (fn (_ i) (first (sql-eval (first i) scope))) items))))

; ROWS with each row once, when DISTINCT
(def %sql-distinct
  (fn (_ rows distinct)
    (if distinct (List map first (%sql-partition rows %sql-values-key)) rows)))

(def-class SqlStatement ()
  (static
    (method select (self stmt)
      (let ((source (if (null? (List third stmt)) () (%sql-from (List third stmt)))))
        (let ((columns (if (null? source) () (first source))))
          (let ((items (%sql-expand (List second stmt) columns)))
            (let ((grouped (%sql-grouped? stmt items))
                  (order (List map (fn (_ term) (%sql-term-expr (first term) items "ORDER"))
                                   (List ref 4 stmt))))
              (let ((scopes (if grouped
                              (%sql-grouped stmt items order columns
                                            (%sql-filtered stmt source))
                              (%sql-filtered stmt source))))
                (let ((rows (%sql-page
                              (%sql-distinct
                                (List map
                                  (fn (_ s) (List map (fn (_ i) (sql-eval (first i) s)) items))
                                  (%sql-sorted scopes (List ref 4 stmt) order))
                                (List ref 9 stmt))
                              (%sql-count (List ref 6 stmt))
                              (%sql-count (List ref 5 stmt)))))
                  (list (List map (fn (_ i) (%sql-heading i columns)) items)
                        (if (null? rows) (%sql-item-types items columns grouped)
                          (List map first (first rows)))
                        rows))))))))
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

(provide sql/exec sql-execute sql-table-names sql-table-columns)

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
;
; A call OVER a window is answered for every row before any row's items
; are: SqlWindow holds one static method a window function, an aggregate
; is answered over each row's frame, and the value is left in the row's
; scope under the call's node.

(module sql/exec)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/type/dict)
(import x/num/tower)
(import x/num/float)
(import sql/words sql-lower sql-same-name?)
(import sql/zone sql-zone-session!)
(import sql/files sql-file-read sql-file-write sql-file-stem)
(import sql/eval
  sql-eval sql-expr-name sql-scope sql-select-runner! sql-column
  sql-column-hidden? sql-column-hide sql-column-node sql-column-index
  sql-common-type
  sql-aggregated? sql-aggregate-call? sql-cast
  sql-windowed? sql-scope-windowed sql-window-aggregate sql-type-name sql-pointed?
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

; The tables a WITH names, for the statement being run: a name in lower
; case to its result.  Emptied where a run begins.
(def %sql-withs (Dict make))

; A result as what FROM reads, under QUALIFIER
(def %sql-result-source
  (fn (_ result qualifier)
    (pair (List map (fn (_ name type) (sql-column qualifier name type))
                    (first result) (List second result))
          (List map (fn (_ row) (List map rest row)) (List third result)))))

; What DuckDB calls a select statement in a FROM that has no alias
(def %sql-unnamed "unnamed_subquery")

; One table of a FROM: a file, a select statement in parentheses, a table a
; WITH named, or a table there is.  A file's qualifier is its name without
; its directories and its ending.  The qualifier is its alias when it has one
; and its name when not.
(def %sql-source
  (fn (_ name alias)
    (match
      ((and (pair? name) (eq? (first name) (lit renamed)))
        (%sql-source-renamed (%sql-source (List second name) alias) (List third name)))
      ((and (pair? name) (eq? (first name) (lit file)))
        (%sql-result-source (sql-file-read (List second name) (List third name))
                            (if (null? alias) (sql-file-stem (List second name)) alias)))
      ((pair? name)
        (%sql-result-source (%sql-query-result name ()) (if (null? alias) %sql-unnamed alias)))
      ((%sql-withs has? (%sql-key name))
        (%sql-result-source (%sql-withs get (%sql-key name)) (if (null? alias) name alias)))
      (#t
        (let ((table (%sql-table name)))
          (let ((qualifier (if (null? alias) (first table) alias)))
            (pair (List map (fn (_ c) (sql-column qualifier (first c) (List second c)))
                            (List second table))
                  (List third table))))))))

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

; The columns of COLUMNS a name with no qualifier finds
(def %sql-named
  (fn (_ name columns)
    (List filter
      (fn (_ c) (and (sql-same-name? (List second c) name) (not (sql-column-hidden? c))))
      columns)))

; The one column NAME names on a SIDE of a join, left or right
(def %sql-using-column
  (fn (_ name columns side)
    (let ((found (%sql-named name columns)))
      (when (or (null? found) (not (null? (rest found))))
        (error (Str8 append "Binder Error: Column \"" name "\" does not exist on "
                            side " side of join!")))
      (first found))))

; The names a NATURAL join joins on: those both sides have, in the left's
; order
(def %sql-shared-names
  (fn (_ left right)
    (List map (fn (_ c) (List second c))
      (List filter
        (fn (_ c) (and (not (sql-column-hidden? c))
                       (not (null? (%sql-named (List second c) right)))))
        left))))

; The condition a USING stands for: each name's column on the left equal
; to its column on the right
(def %sql-using-condition
  (fn (_ names left right)
    (let ((tests (List map
                   (fn (_ name)
                     (list (lit bin) (lit eq)
                           (sql-column-node name (first (%sql-using-column name left "left")))
                           (sql-column-node name (first (%sql-using-column name right "right")))))
                   names)))
      (List fold (fn (_ all test) (list (lit and) all test)) (first tests) (rest tests)))))

; LEFT joined to RIGHT.  With USING, a list of names or the name natural,
; the rows kept are those equal in each name's column, and the right's
; column of each name is hidden: the left's stands for both.
(def %sql-join
  (fn (_ left right kind on using)
    (when (sql-aggregated? on)
      (error "Binder Error: JOIN clause cannot contain aggregates!"))
    (let ((names (if (eq? using (lit natural)) (%sql-shared-names (first left) (first right))
                   using)))
      (when (and (not (null? using)) (List includes? kind (list (lit right) (lit full))))
        (error "Not implemented Error: USING or NATURAL with a RIGHT or FULL JOIN"))
      (when (and (eq? using (lit natural)) (null? names))
        (error "Binder Error: No columns found to join on in NATURAL JOIN."))
      (let ((test (if (null? names) on (%sql-using-condition names (first left) (first right))))
            (columns (List append (first left)
                       (List map
                         (fn (_ c)
                           (if (List any? (fn (_ n) (sql-same-name? n (List second c))) names)
                             (sql-column-hide c)
                             c))
                         (first right)))))
        (let ((visible (List append (first left) (first right))))
          (pair columns
            (%sql-join-rows left right kind
              (fn (_ row)
                (if (null? test) #t
                  (eq? (sql-truth (sql-eval test (sql-scope visible row () ()))) #t))))))))))

; --- unnest ------------------------------------------------------------------

; The unnest nodes of NODE, at any depth of its own statement, each once,
; newest first.  One inside another is not looked for: the inner has no
; row to be answered on.
(def %sql-unnests-in
  (fn (self node found)
    (match
      ((not (pair? node)) found)
      ((eq? (first node) (lit unnest))
        (do (unless (null? (self (List second node) ()))
              (error "Binder Error: Nested UNNEST calls are not supported - use UNNEST(x, recursive := true) to unnest multiple levels"))
            (if (List any? (fn (_ f) (same? f node)) found) found (pair node found))))
      ((or (eq? (first node) (lit subquery)) (eq? (first node) (lit exists))) found)
      ((eq? (first node) (lit in-query)) (self (List second node) found))
      (#t (List fold (fn (_ seen inner) (self inner seen)) found node)))))

; What an unnest's ARGS unnest, in SCOPE: (TYPE . VALUES), the type of an
; element and the x values of the list's elements, none for a NULL list
(def %sql-unnest-list
  (fn (_ args scope)
    (when (null? args) (error "Binder Error: UNNEST() requires at least one argument"))
    (unless (null? (rest args))
      (error "Binder Error: UNNEST - unsupported extra argument, unnest only supports recursive := [true/false], max_depth := # or keep_parent_names := [true/false]"))
    (let ((v (sql-eval (first args) scope)))
      (let ((t (first v)))
        (match
          ((and (pair? t) (eq? (first t) (lit list)))
            (pair (List second t) (if (sql-null? v) () (first (rest v)))))
          ((eq? t (lit null)) (pair (lit null) ()))
          ((and (pair? t) (eq? (first t) (lit struct)))
            (error "Not implemented Error: unnest of a struct inside an expression"))
          (#t (error (Str8 str "Binder Error: UNNEST() can only be applied to lists, structs and NULL, not "
                               (sql-type-name t)))))))))

; SCOPES with each one once for every place of the longest list its
; UNNESTS unnest, an unnest's value held in the scope under its node as a
; window's is.  A shorter list gives NULLs past its end, and a scope whose
; lists are all empty or NULL is gone.
(def %sql-unnested
  (fn (_ scopes unnests outer)
    (if (null? unnests) scopes
      (List flat-map
        (fn (_ given)
          (let ((scope (if (null? given) (sql-scope () () () outer) given)))
            (let ((lists (List map (fn (_ u) (%sql-unnest-list (List second u) scope)) unnests)))
              (let ((n (List fold (fn (_ most l) (if (> (List length (rest l)) most) (List length (rest l)) most))
                                  0 lists)))
                (List map
                  (fn (_ k)
                    (List fold
                      (fn (_ held entry)
                        (sql-scope-windowed held
                          (pair (first entry)
                                (pair (first (rest entry))
                                      (if (< k (List length (rest (rest entry))))
                                        (List ref k (rest (rest entry)))
                                        ())))))
                      scope (List zip unnests lists)))
                  (List range 0 n))))))
        scopes))))

; SCOPE with a NULL of its element's type held for each of UNNESTS: what
; the types of a result with no row are read from
(def %sql-unnest-nulls
  (fn (_ scope unnests)
    (List fold
      (fn (_ held u)
        (sql-scope-windowed held
          (pair u (pair (first (%sql-unnest-list (List second u) scope)) ()))))
      scope unnests)))

; ITEM, when it is the unnest of a struct, as an item for each of the
; struct's fields under the field's name; nil when it is not one.  The
; struct's type is read over a row of NULLs.
(def %sql-unnest-struct
  (fn (_ item columns)
    (let ((e (first item)))
      (if (and (eq? (first e) (lit unnest)) (not (null? (List second e)))
               (null? (rest (List second e))))
        (let ((t (guard (_ ())
                   (first (sql-eval (first (List second e))
                            (if (null? columns) ()
                              (sql-scope columns (%sql-nulls columns) () ())))))))
          (if (and (pair? t) (eq? (first t) (lit struct)))
            (List map
              (fn (_ f)
                (list (list (lit call) "struct_extract"
                            (list (first (List second e)) (list (lit str) (first f)))
                            #f (list (lit field)))
                      (first f)))
              (rest t))
            ()))
        ()))))

; --- unnest as a table -------------------------------------------------------

; TABLE without the column names an alias gave it, and those names
(def %sql-table-plain
  (fn (_ table)
    (if (and (pair? table) (eq? (first table) (lit renamed))) (List second table) table)))

(def %sql-table-names
  (fn (_ table)
    (if (and (pair? table) (eq? (first table) (lit renamed))) (List third table) ())))

(def %sql-unnest-table?
  (fn (_ table)
    (let ((plain (%sql-table-plain table)))
      (and (pair? plain) (eq? (first plain) (lit unnest))))))

; LEFT joined to the unnest TABLE, whose list is read for each row of
; LEFT: the row once beside each element.  A row whose list is empty or
; NULL is gone, and in a LEFT JOIN is kept beside a NULL.  ON keeps the
; pairs it is true of.  The column is named unnest, and so is its table,
; when an alias does not say.
(def %sql-unnest-join
  (fn (_ left table alias kind on outer)
    (when (List includes? kind (list (lit right) (lit full)))
      (error "Not implemented Error: unnest in a RIGHT or FULL JOIN"))
    (let ((args (List second (%sql-table-plain table)))
          (names (%sql-table-names table))
          (scope-of (fn (_ row)
                      (if (and (null? (first left)) (null? outer)) ()
                        (sql-scope (first left) row () outer)))))
      (unless (or (null? args) (null? (rest args)))
        (error (Str8 str "Binder Error: No function matches the given name and argument types 'unnest("
                         (Str8 join ", "
                           (List map (fn (_ a) (sql-type-name (first (sql-eval a (scope-of (%sql-nulls (first left)))))))
                                     args))
                         ")'.")))
      (let ((t (first (guard (_ (error "Binder Error: UNNEST requires a single list or array as input"))
                        (%sql-unnest-list args (scope-of (%sql-nulls (first left))))))))
        (let ((columns (List append (first left)
                         (list (sql-column (if (null? alias) "unnest" alias)
                                           (if (null? names) "unnest" (first names))
                                           t)))))
          (pair columns
            (List flat-map
              (fn (_ row)
                (let ((kept (List filter
                              (fn (_ joined)
                                (or (null? on)
                                    (eq? (sql-truth (sql-eval on (sql-scope columns joined () outer))) #t)))
                              (List map (fn (_ x) (List append row (list x)))
                                        (rest (%sql-unnest-list args (scope-of row)))))))
                  (if (and (null? kept) (eq? kind (lit left)))
                    (list (List append row (list ())))
                    kept)))
              (rest left))))))))

; A source with the first of its columns named by NAMES
(def %sql-source-renamed
  (fn (_ source names)
    (when (> (List length names) (List length (first source)))
      (error (Str8 str "Binder Error: table \"" (first (first (first source))) "\" has "
                       (List length (first source)) " columns available but "
                       (List length names) " columns specified")))
    (pair ((fn (self columns names)
             (if (null? names) columns
               (pair (sql-column (first (first columns)) (first names) (List third (first columns)))
                     (self (rest columns) (rest names)))))
           (first source) names)
          (rest source))))

; Every table of a FROM, each joined to what is before it.  An unnest is
; read for each row of what is before it, and may name a column of OUTER,
; the row of the statement this one is a subquery of.
(def %sql-from
  (fn (_ from outer)
    (List fold
      (fn (_ left join)
        (if (%sql-unnest-table? (List second join))
          (%sql-unnest-join left (List second join) (List third join)
                            (first join) (List ref 3 join) outer)
          (%sql-join left (%sql-source (List second join) (List third join))
                     (first join) (List ref 3 join) (List ref 4 join))))
      (if (%sql-unnest-table? (first (first from)))
        (%sql-unnest-join (pair () (list ())) (first (first from)) (List second (first from))
                          (lit cross) () outer)
        (%sql-source (first (first from)) (List second (first from))))
      (rest from))))

; COLUMN is the one ENTRY of a star's list names: (QUALIFIER NAME ...),
; QUALIFIER nil for a column of any table
(def %sql-star-named?
  (fn (_ column entry)
    (and (sql-same-name? (List second column) (List second entry))
         (or (null? (first entry))
             (and (not (null? (first column)))
                  (sql-same-name? (first column) (first entry)))))))

; Every entry of a star's list WORD names a column the star has
(def %sql-star-check
  (fn (_ word entries own qualifier)
    (let ((lost (List find
                  (fn (_ e) (not (List any? (fn (_ c) (%sql-star-named? c e)) own)))
                  entries)))
      (unless (null? lost)
        (error (Str8 str "Binder Error: Column "
                         (if (null? (first lost)) "" (Str8 str "\"" (first lost) "\"."))
                         "\"" (List second lost) "\" in " word " list not found in "
                         (if (null? qualifier) "FROM clause" qualifier)))))))

; A star's columns that are shown.  A column a USING hid stays out while
; the column standing for it is shown, and takes its place when that one
; is excluded by its table's name.
(def %sql-star-shown
  (fn (_ kept)
    (List reject
      (fn (_ c)
        (and (sql-column-hidden? c)
             (List any? (fn (_ k) (and (not (sql-column-hidden? k))
                                       (sql-same-name? (List second k) (List second c))))
                        kept)))
      kept)))

; COLUMNS less each one that a REPLACE names and that follows another of
; its name: a REPLACE is used once, and DuckDB drops the columns it would
; have gone on to
(def %sql-star-once
  (fn (self columns replaces seen)
    (if (null? columns) ()
      (let ((name (List second (first columns))))
        (match
          ((not (List any? (fn (_ r) (sql-same-name? (List second r) name)) replaces))
            (pair (first columns) (self (rest columns) replaces seen)))
          ((List any? (fn (_ s) (sql-same-name? s name)) seen)
            (self (rest columns) replaces seen))
          (#t (pair (first columns)
                    (self (rest columns) replaces (pair name seen)))))))))

; The item a star gives for COLUMN: its REPLACE expression under the name
; written there, the column under its RENAME name, or the column.  Of two
; renames of one column the later holds.
(def %sql-star-column
  (fn (_ column replaces renames)
    (let ((replace (List find (fn (_ r) (sql-same-name? (List second r) (List second column)))
                              replaces))
          (rename (List find (fn (_ r) (%sql-star-named? column r)) (List reverse renames)))
          (node (sql-column-node (List second column) (first column))))
      (match
        ((not (null? replace)) (list (first replace) (List second replace)))
        ((not (null? rename)) (list node (List third rename)))
        (#t (list node ()))))))

; The items a star stands for: every column, or every column of its
; qualifier, less those its EXCLUDE names
(def %sql-star
  (fn (_ node columns)
    (let ((qualifier (List second node))
          (lists (if (null? (rest (rest node))) (list () () ()) (List third node))))
      (let ((own (if (null? qualifier) columns
                   (List filter (fn (_ c) (sql-same-name? (first c) qualifier))
                                columns)))
            (excludes (first lists))
            (replaces (List second lists)))
        (match
          ((null? columns)
            (error "Binder Error: * expression without FROM clause!"))
          ((null? own)
            (error (Str8 str "Binder Error: Referenced table \"" qualifier
                             "\" not found!")))
          (#t
            (do
              (%sql-star-check "EXCLUDE" excludes own qualifier)
              (%sql-star-check "REPLACE"
                (List map (fn (_ r) (list () (List second r))) replaces) own qualifier)
              (let ((kept (List reject
                            (fn (_ c) (List any? (fn (_ e) (%sql-star-named? c e)) excludes))
                            own)))
                (List map (fn (_ c) (%sql-star-column c replaces (List third lists)))
                          (%sql-star-once
                            (if (null? qualifier) (%sql-star-shown kept) kept)
                            replaces ()))))))))))

; ITEMS with each star replaced by the items it stands for
(def %sql-expand
  (fn (_ items columns)
    (let ((all (List flat-map
                 (fn (_ item)
                   (if (eq? (first (first item)) (lit star))
                     (%sql-star (first item) columns)
                     (let ((fields (%sql-unnest-struct item columns)))
                       (if (null? fields) (list item) fields))))
                 items)))
      (if (null? all)
        (error "Binder Error: SELECT list is empty after resolving * expressions!")
        all))))

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
        ((sql-pointed? e) (List second (List second (List third e))))
        (#t (sql-expr-name e))))))

; --- a column's field ----------------------------------------------------------

; E with each col node that names a field of a struct column made the
; call that takes the field: its name before the point is no table of
; COLUMNS and is a column of them.  A subquery has its own tables.
(def %sql-dotted
  (fn (self e columns)
    (match
      ((not (pair? e)) e)
      ((or (eq? (first e) (lit subquery)) (eq? (first e) (lit exists))) e)
      ((and (eq? (first e) (lit col)) (not (null? (List third e)))
            (null? (List find (fn (_ c) (str=? (List ref 3 c) (List ref 4 e))) columns))
            (not (null? (List find
                          (fn (_ c) (and (str=? (List ref 4 c) (List ref 4 e))
                                         (not (sql-column-hidden? c))))
                          columns))))
        (list (lit call) "struct_extract"
              (list (sql-column-node (List third e) ()) (list (lit str) (List second e)))
              #f (list (lit dotted))))
      (#t (pair (self (first e) columns) (self (rest e) columns))))))

; STMT, a select node, with the fields of struct columns found in every
; clause but its FROM; as it is when COLUMNS has no struct
(def %sql-dotted-select
  (fn (_ stmt columns)
    (if (List any? (fn (_ c) (and (pair? (List third c)) (eq? (first (List third c)) (lit struct))))
                   columns)
      (pair (first stmt)
        (pair (%sql-dotted (List second stmt) columns)
          (pair (List third stmt) (%sql-dotted (List drop 3 stmt) columns))))
      stmt)))

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
        (List any? (fn (_ term) (sql-aggregated? (first term))) (List ref 4 stmt))
        (sql-aggregated? (List ref 10 stmt)))))

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
              (when (sql-windowed? key)
                (error "Binder Error: GROUP BY clause cannot contain window functions!"))
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
      ((eq? (first e) (lit over))
        (do (%sql-check-parts (List third (List second e)) keys columns)
            (%sql-check-parts (list (List third e) (List ref 3 e)) keys columns)))
      ((or (eq? (first e) (lit subquery)) (eq? (first e) (lit exists))) ())
      ((eq? (first e) (lit in-query)) (self (List second e) keys columns))
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
  (fn (_ columns members outer)
    (sql-scope columns
               (if (or (null? members) (null? (first members))) (%sql-nulls columns)
                 (List second (first members)))
               (list members)
               outer)))

; SCOPES as a scope a group.  With no keys they are one group, though
; there be no row in it.
(def %sql-groups
  (fn (_ scopes keys columns outer)
    (if (null? keys) (list (%sql-group-scope columns scopes outer))
      (List map (fn (_ members) (%sql-group-scope columns members outer))
        (%sql-partition scopes
          (fn (_ s)
            (%sql-values-key (List map (fn (_ k) (sql-eval k s)) keys))))))))

; --- windows -----------------------------------------------------------------

; The over nodes in NODE that are not among FOUND, before FOUND: each node
; once, as the parser made it.  A subquery's windows are its own.
(def %sql-overs-in
  (fn (self node found)
    (match
      ((not (pair? node)) found)
      ((eq? (first node) (lit over))
        (do (when (or (sql-windowed? (List third (List second node)))
                      (sql-windowed? (rest (rest node))))
              (error "Parser Error: window functions are not allowed in window definitions"))
            (if (List any? (fn (_ f) (same? f node)) found) found (pair node found))))
      ((or (eq? (first node) (lit subquery)) (eq? (first node) (lit exists))) found)
      ((eq? (first node) (lit in-query)) (self (List second node) found))
      (#t (List fold (fn (_ seen inner) (self inner seen)) found node)))))

; The runs of ENTRIES that TERMS do not tell apart, an entry
; (INDEX ORDER-VALUES SCOPE): the rows that are peers
(def %sql-window-runs
  (fn (_ entries terms)
    (List reverse
      (List map (fn (_ run) (List reverse run))
        (List fold
          (fn (_ runs e)
            (if (and (not (null? runs))
                     (= (%sql-keys-order (List second (first (first runs))) (List second e) terms) 0))
              (pair (pair e (first runs)) (rest runs))
              (pair (list e) runs)))
          () entries)))))

; A row's place in its partition, a row of RUNS each: (INDEX RANK DENSE
; END), INDEX from 0, RANK one more than the index of its first peer, DENSE
; its run counted from 1, and END the index of its last peer
(def %sql-window-places
  (fn (self runs start dense)
    (if (null? runs) ()
      (let ((end (+ start (List length (first runs)))))
        (List append
          (List map (fn (_ i) (list i (+ start 1) dense (- end 1))) (List range start end))
          (self (rest runs) end (+ dense 1)))))))

; Each of RUNS as (START . END), the indexes of its first row and its last
(def %sql-run-ends
  (fn (self runs start)
    (if (null? runs) ()
      (let ((end (+ start (List length (first runs)))))
        (pair (pair start (- end 1)) (self (rest runs) end))))))

; A partition is (SCOPES PLACES FRAME COLUMNS OUTER KEYS TERMS RUNS): its
; rows' scopes in the window's order, each row's place, the window's
; frame, each row's values under the window's ORDER BY and that ORDER BY's
; terms, and each run of peers as (START . END).

; The count an end of a ROWS or GROUPS frame names, signed by its side
(def %sql-frame-count
  (fn (_ end)
    (let ((v (sql-eval (List second end) ())))
      (unless (and (List includes? (first v) %sql-whole-types) (not (sql-null? v))
                   (>= (rest v) 0))
        (error "Binder Error: a frame's count of rows is a whole number, not negative"))
      (* (first end) (rest v)))))

; The value a RANGE frame's END stands at for the row of SCOPE: the row's
; own under the window's one ORDER BY term, less or more the end's
; expression.  PRECEDING is toward the window's start, so it adds when
; the term sorts downward.
(def %sql-range-value
  (fn (_ end scope part)
    (let ((terms (List ref 6 part)))
      (unless (and (not (null? terms)) (null? (rest terms)))
        (error "Binder Error: RANGE frames must have only one ORDER BY expression"))
      (sql-eval
        (list (lit bin)
              (if (eq? (< (first end) 0) (List second (first terms))) (lit add) (lit sub))
              (first (first terms)) (List second end))
        scope))))

; How many of KEYS come before the first that PAST? is true of: KEYS are in
; the window's order, so the index of the first row past a value
(def %sql-keys-before
  (fn (self keys past? n)
    (if (or (null? keys) (past? (first keys))) n
      (self (rest keys) past? (+ n 1)))))

; One static method a kind of frame: the index END stands at for the row
; of PLACE and SCOPE, HIGH whether it is the frame's last end.  An index
; before the partition or after it is a frame's end all the same.
(def-class SqlFrame ()
  (static
    (method rows (self end high place scope part)
      (if (eq? end (lit current)) (first place)
        (+ (first place) (%sql-frame-count end))))
    (method groups (self end high place scope part)
      (if (eq? end (lit current))
        (if high (List ref 3 place) (- (List second place) 1))
        (let ((runs (List ref 7 part))
              (at (+ (- (List third place) 1) (%sql-frame-count end))))
          (match
            ((< at 0) (if high -1 0))
            ((>= at (List length runs)) (List length (first part)))
            (high (rest (List ref at runs)))
            (#t (first (List ref at runs)))))))
    (method range (self end high place scope part)
      (if (eq? end (lit current))
        (if high (List ref 3 place) (- (List second place) 1))
        (let ((value (%sql-range-value end scope part)) (term (first (List ref 6 part))))
          (if high
            (- (%sql-keys-before (List ref 5 part)
                 (fn (_ key) (> (%sql-key-order (first key) value term) 0)) 0)
               1)
            (%sql-keys-before (List ref 5 part)
              (fn (_ key) (>= (%sql-key-order (first key) value term) 0)) 0)))))))

; The frame a window has when none is written: from its partition's start
; to the row's last peer
(def %sql-frame-default (list (lit range) (lit unbounded) (lit current) ()))

; The index one END of FRAME stands at, kept inside the partition's N rows
; unless the frame is then empty
(def %sql-frame-index
  (fn (_ frame end high place scope part n)
    (if (eq? end (lit unbounded)) (if high (- n 1) 0)
      (let ((i ((class-static-ref SqlFrame (first frame)) SqlFrame end high place scope part)))
        (if high (Num min (- n 1) i) (Num max 0 i))))))

; SCOPES from the index LOW to HIGH, both counted; none when LOW is past HIGH
(def %sql-slice
  (fn (_ scopes low high)
    (if (> low high) ()
      (List take (+ (- high low) 1) (List drop low scopes)))))

; The scopes from LOW to HIGH less what EXCLUDE leaves out around the row
; of PLACE: the row, or its peers with or without it
(def %sql-frame-members
  (fn (_ scopes low high exclude place)
    (if (null? exclude) (%sql-slice scopes low high)
      (let ((i (first place))
            (from (if (first exclude) (- (List second place) 1) (first place)))
            (to (if (first exclude) (List ref 3 place) (first place))))
        (List append
          (%sql-slice scopes low (Num min high (- from 1)))
          (if (and (List second exclude) (>= i low) (<= i high)) (%sql-slice scopes i i) ())
          (%sql-slice scopes (Num max low (+ to 1)) high))))))

; The scopes in each row's frame, a list a row
(def %sql-window-frames
  (fn (_ part)
    (let ((scopes (first part)) (n (List length (first part)))
          (frame (if (null? (List third part)) %sql-frame-default (List third part))))
      (List map
        (fn (_ place scope)
          (%sql-frame-members scopes
            (%sql-frame-index frame (List second frame) #f place scope part n)
            (%sql-frame-index frame (List third frame) #t place scope part n)
            (List ref 3 frame) place))
        (List second part) scopes))))

; CALL has from LEAST to MOST arguments, or the error DuckDB gives, which
; names their types
(def %sql-window-arity
  (fn (_ call part least most)
    (let ((args (List third call)))
      (unless (and (>= (List length args) least) (<= (List length args) most)
                   (not (List any? (fn (_ a) (eq? (first a) (lit star))) args)))
        (%sql-window-no-match call part)))))

(def %sql-window-no-match
  (fn (_ call part)
    (error
      (Str8 str "Binder Error: No function matches the given name and argument types '"
                (sql-lower (List second call)) "("
                (Str8 join ", "
                  (List map
                    (fn (_ a)
                      (if (eq? (first a) (lit star)) "*"
                        (sql-type-name (first (sql-eval a (first (first part)))))))
                    (List third call)))
                ")'. You might need to add explicit type casts."))))

(def %sql-whole-types
  (list (lit tinyint) (lit smallint) (lit integer) (lit bigint) (lit hugeint)
        (lit utinyint) (lit usmallint) (lit uinteger) (lit ubigint) (lit uhugeint)))

; The whole number CALL's argument at the index I is, nil for a NULL
(def %sql-window-whole
  (fn (_ call part i)
    (let ((v (sql-eval (first (List drop i (List third call))) (first (first part)))))
      (unless (or (List includes? (first v) %sql-whole-types) (eq? (first v) (lit null)))
        (%sql-window-no-match call part))
      (rest v))))

; How many rows lag and lead reach: their second argument, or 1
(def %sql-window-offset
  (fn (_ call part)
    (if (null? (rest (List third call))) 1
      (let ((n (%sql-window-whole call part 1)))
        (if (null? n) 0 n)))))

; VALUES moved BY places toward the front, nil where no row comes
(def %sql-window-moved
  (fn (_ values by n)
    (if (< by 0)
      (List append (List repeat (Num min (- 0 by) n) ())
                   (List take (Num max 0 (+ n by)) values))
      (List append (List drop (Num min by n) values)
                   (List repeat (Num min by n) ())))))

; lag and lead: the argument's value WAY rows on, each offset's worth, and
; where no row is there the third argument as the first's type, or NULL
(def %sql-window-shifted
  (fn (_ call part way)
    (%sql-window-arity call part 1 3)
    (let ((args (List third call)) (scopes (first part)))
      (let ((values (List map (fn (_ s) (sql-eval (first args) s)) scopes)))
        (List map
          (fn (_ moved own scope)
            (match
              ((not (null? moved)) moved)
              ((< (List length args) 3) (pair (first own) ()))
              (#t (pair (first own)
                        (sql-cast (sql-eval (List third args) scope) (first own))))))
          (%sql-window-moved values (* way (%sql-window-offset call part))
                             (List length scopes))
          values scopes)))))

; first_value and last_value: the argument for the row PICK takes from each
; frame, NULL for a frame with no row
(def %sql-window-framed
  (fn (_ call part pick)
    (%sql-window-arity call part 1 1)
    (let ((arg (first (List third call))))
      (List map
        (fn (_ members scope)
          (if (null? members) (pair (first (sql-eval arg scope)) ())
            (sql-eval arg (pick members))))
        (%sql-window-frames part) (first part)))))

; An aggregate over each row's frame
(def %sql-window-aggregated
  (fn (_ call part)
    (let ((columns (List ref 3 part)) (outer (List ref 4 part)))
      (List map
        (fn (_ members scope)
          (sql-window-aggregate call
            (if (null? members)
              (sql-scope columns (List second scope) (list ()) outer)
              (%sql-group-scope columns members outer))))
        (%sql-window-frames part) (first part)))))

(def %sql-window-counted
  (fn (_ call part place-of)
    (%sql-window-arity call part 0 0)
    (List map (fn (_ place) (pair (lit bigint) (place-of place))) (List second part))))

; One static method a window function: CALL's values for the rows of PART,
; in their order
(def-class SqlWindow ()
  (static
    (method row_number (self call part)
      (%sql-window-counted call part (fn (_ place) (+ (first place) 1))))
    (method rank (self call part) (%sql-window-counted call part (fn (_ place) (List second place))))
    (method dense_rank (self call part) (%sql-window-counted call part (fn (_ place) (List third place))))
    (method percent_rank (self call part)
      (%sql-window-arity call part 0 0)
      (let ((n (List length (first part))))
        (List map
          (fn (_ place)
            (pair (lit double)
              (if (= n 1) (Float from 0)
                (/ (Float from (- (List second place) 1)) (Float from (- n 1))))))
          (List second part))))
    (method cume_dist (self call part)
      (%sql-window-arity call part 0 0)
      (let ((n (List length (first part))))
        (List map
          (fn (_ place)
            (pair (lit double) (/ (Float from (+ (List ref 3 place) 1)) (Float from n))))
          (List second part))))
    ; N buckets as near one size as the rows allow, the larger ones first
    (method ntile (self call part)
      (%sql-window-arity call part 1 1)
      (let ((buckets (%sql-window-whole call part 0)) (n (List length (first part))))
        (when (and (not (null? buckets)) (<= buckets 0))
          (error "Invalid Input Error: Argument for ntile must be greater than zero"))
        (List map
          (fn (_ place)
            (pair (lit bigint)
              (if (null? buckets) ()
                (let ((size (Num quotient n buckets)) (more (Num remainder n buckets))
                      (i (first place)))
                  (if (< i (* more (+ size 1)))
                    (+ (Num quotient i (+ size 1)) 1)
                    (+ more (Num quotient (- i (* more (+ size 1))) size) 1))))))
          (List second part))))
    (method nth_value (self call part)
      (%sql-window-arity call part 2 2)
      (let ((arg (first (List third call))) (nth (%sql-window-whole call part 1)))
        (List map
          (fn (_ members scope)
            (if (or (null? nth) (< nth 1) (> nth (List length members)))
              (pair (first (sql-eval arg scope)) ())
              (sql-eval arg (first (List drop (- nth 1) members)))))
          (%sql-window-frames part) (first part))))
    (method lag (self call part) (%sql-window-shifted call part -1))
    (method lead (self call part) (%sql-window-shifted call part 1))
    (method first_value (self call part) (%sql-window-framed call part first))
    (method last_value (self call part) (%sql-window-framed call part (fn (_ members) (List last members))))))

; One partition's values, each with its row's index: (INDEX . VALUE)
(def %sql-window-part
  (fn (_ node entries columns outer)
    (let ((call (List second node)) (terms (List ref 3 node)))
      (let ((sorted (if (null? terms) entries
                      (List sort
                        (fn (_ a b) (< (%sql-keys-order (List second a) (List second b) terms) 0))
                        entries))))
        (let ((part (let ((runs (%sql-window-runs sorted terms)))
                      (list (List map (fn (_ e) (List third e)) sorted)
                            (%sql-window-places runs 0 1)
                            (List ref 4 node) columns outer
                            (List map (fn (_ e) (List second e)) sorted) terms
                            (%sql-run-ends runs 0))))
              (window (class-static-ref SqlWindow
                        (Str8 ->sym (sql-lower (List second call))))))
          (List map pair
            (List map first sorted)
            (if (null? window) (%sql-window-aggregated call part)
              (window SqlWindow call part))))))))

; What the window of NODE answers for each of SCOPES, in their order
(def %sql-window-values
  (fn (_ node scopes columns outer)
    (let ((entries (List map
                     (fn (_ s i)
                       (list i (List map (fn (_ term) (sql-eval (first term) s)) (List ref 3 node)) s))
                     scopes (List range 0 (List length scopes)))))
      (List map rest
        (List sort (fn (_ a b) (< (first a) (first b)))
          (List flat-map
            (fn (_ rows) (%sql-window-part node rows columns outer))
            (%sql-partition entries
              (fn (_ e)
                (%sql-values-key
                  (List map (fn (_ p) (sql-eval p (List third e))) (List third node)))))))))))

; SCOPES with each of OVERS answered in them.  A row that is of no table
; has a scope here all the same, to hold the answers.
(def %sql-windowed
  (fn (_ scopes overs columns outer)
    (if (null? overs) scopes
      (List fold
        (fn (_ held node)
          (List map (fn (_ s v) (sql-scope-windowed s (pair node v)))
                    held (%sql-window-values node held columns outer)))
        (List map (fn (_ s) (if (null? s) (sql-scope () () () outer) s)) scopes)
        overs))))

; SCOPES that QUALIFY keeps
(def %sql-qualified
  (fn (_ scopes qualify)
    (if (null? qualify) scopes
      (List filter (fn (_ s) (eq? (sql-truth (sql-eval qualify s)) #t)) scopes))))

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

; One row for TABLE from VALUES, one at each of PLACES and NULL elsewhere
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
                             (sql-cast e (List second (List ref place columns)))))
                     places exprs)))
        (List map
          (fn (_ j)
            (let ((g (List find (fn (_ g) (= (first g) j)) given)))
              (if (null? g) () (rest g))))
          (List range 0 (List length columns)))))))

; --- the statements ----------------------------------------------------------

; The scopes a SELECT's FROM and WHERE leave: a row of the tables each, or
; one with nothing in it when there is no FROM.  OUTER is the scope of the
; row a subquery is answered for.
(def %sql-filtered
  (fn (_ stmt source outer)
    (let ((where (List ref 3 stmt)))
      (when (sql-aggregated? where)
        (error "Binder Error: WHERE clause cannot contain aggregates!"))
      (when (sql-windowed? where)
        (error "Binder Error: WHERE clause cannot contain window functions!"))
      (let ((scopes (match
                      ((not (null? source))
                        (List map (fn (_ row) (sql-scope (first source) row () outer))
                                  (rest source)))
                      ((null? outer) (list ()))
                      (#t (list (sql-scope () () () outer))))))
        (if (null? where) scopes
          (List filter (fn (_ s) (eq? (sql-truth (sql-eval where s)) #t))
                       scopes))))))

; SCOPES as the groups a grouped SELECT answers for, HAVING applied.  ITEMS
; and ORDER, what the terms of ORDER BY sort by, are checked against the
; keys first.
(def %sql-grouped
  (fn (_ stmt items order columns scopes outer)
    (let ((keys (%sql-group-keys (List ref 7 stmt) items))
          (having (List ref 8 stmt)))
      (List for-each (fn (_ i) (%sql-check-grouped (first i) keys columns)) items)
      (List for-each (fn (_ e) (%sql-check-grouped e keys columns)) order)
      (when (sql-windowed? having)
        (error "Binder Error: HAVING clause cannot contain window functions!"))
      (unless (null? having) (%sql-check-grouped having keys columns))
      (let ((groups (%sql-groups scopes keys columns outer)))
        (if (null? having) groups
          (List filter (fn (_ g) (eq? (sql-truth (sql-eval having g)) #t))
                       groups))))))

; The types of ITEMS' columns when no row shows them: each item's type over
; a row of NULLs, a group with no rows when GROUPED, and that row the one
; row of each of the windows OVERS
(def %sql-item-types
  (fn (_ items columns grouped outer overs unnests)
    (let ((windowed (first
                      (%sql-windowed
                        (list (match
                                (grouped (%sql-group-scope columns () outer))
                                ((and (null? columns) (null? outer)) ())
                                (#t (sql-scope columns (%sql-nulls columns) () outer))))
                        overs columns outer))))
      (let ((scope (if (null? unnests) windowed
                     (%sql-unnest-nulls
                       (if (null? windowed) (sql-scope () () () outer) windowed)
                       unnests))))
        (List map (fn (_ i) (first (sql-eval (first i) scope))) items)))))

; ROWS with each row once, when DISTINCT
(def %sql-distinct
  (fn (_ rows distinct)
    (if distinct (List map first (%sql-partition rows %sql-values-key)) rows)))

; A SELECT's result, (NAMES TYPES ROWS) with each row a list of values, for
; the row of OUTER when it is a subquery
(def %sql-select-result
  (fn (_ written outer)
    (let ((source (if (null? (List third written)) () (%sql-from (List third written) outer))))
      (let ((columns (if (null? source) () (first source))))
       (let ((stmt (%sql-dotted-select written columns)))
        (let ((items (%sql-expand (List second stmt) columns)))
          (let ((grouped (%sql-grouped? stmt items))
                (order (List map (fn (_ term) (%sql-term-expr (first term) items "ORDER"))
                                 (List ref 4 stmt))))
            (let ((qualify (List ref 10 stmt))
                  (unnests (List reverse (%sql-unnests-in (list items order) ())))
                  (overs (List reverse
                           (%sql-overs-in (list items order (List ref 10 stmt)) ()))))
            (let ((scopes (%sql-unnested (%sql-qualified
                            (%sql-windowed
                              (if grouped
                                (%sql-grouped stmt items
                                  (if (null? qualify) order (pair qualify order))
                                  columns (%sql-filtered stmt source outer) outer)
                                (%sql-filtered stmt source outer))
                              overs columns outer)
                            qualify)
                            unnests outer)))
              (let ((rows (%sql-page
                            (%sql-distinct
                              (List map
                                (fn (_ s) (List map (fn (_ i) (sql-eval (first i) s)) items))
                                (%sql-sorted scopes (List ref 4 stmt) order))
                              (List ref 9 stmt))
                            (%sql-count (List ref 6 stmt))
                            (%sql-count (List ref 5 stmt)))))
                (list (List map (fn (_ i) (%sql-heading i columns)) items)
                      (if (null? rows) (%sql-item-types items columns grouped outer overs unnests)
                        (List map first (first rows)))
                      rows)))))))))))

; A select statement's result: a SELECT's, or that of the SELECT a WITH
; ends in, its tables made first, each one there for the next.  A name a
; WITH gives hides a table of that name until the statement is done.
; --- set operations ----------------------------------------------------------

; How many times each row of ROWS comes, by its key
(def %sql-row-counts
  (fn (_ rows)
    (let ((counts (Dict make)))
      (List for-each
        (fn (_ row)
          (let ((k (%sql-values-key row)))
            (counts set! k (+ 1 (counts get-or 0 k)))))
        rows)
      counts)))

(def %sql-distinct-rows
  (fn (_ rows) (List map first (%sql-partition rows %sql-values-key))))

; The rows of LEFT that COUNTS, of the right's rows, has a count left
; for, or has none for when WANTED is not.  With ALL each row of the right
; answers for one of the left; without, a row is kept once.
(def %sql-matching
  (fn (_ left counts wanted all)
    (if all
      (List filter
        (fn (_ row)
          (let ((k (%sql-values-key row)))
            (let ((n (counts get-or 0 k)))
              (when (> n 0) (counts set! k (- n 1)))
              (if wanted (> n 0) (= n 0)))))
        left)
      (List filter
        (fn (_ row) (if wanted (counts has? (%sql-values-key row))
                      (not (counts has? (%sql-values-key row)))))
        (%sql-distinct-rows left)))))

; A set operation is a static method named for it, of the two sides' rows
; and whether rows that repeat are kept
(def-class SqlSet ()
  (static
    (method union (self left right all)
      (if all (List append left right) (%sql-distinct-rows (List append left right))))
    (method intersect (self left right all)
      (%sql-matching left (%sql-row-counts right) #t all))
    (method except (self left right all)
      (%sql-matching left (%sql-row-counts right) #f all))))

; The type a column of both sides goes into: text when either is, as
; DuckDB has it, else the type the two share
(def %sql-set-type
  (fn (_ a b)
    (if (or (eq? a (lit varchar)) (eq? b (lit varchar))) (lit varchar)
      (sql-common-type (list a b)))))

; A set operation's result: the left's names, each column in the type its
; two sides go into
(def %sql-set-result
  (fn (_ stmt outer)
    (let ((left (%sql-query-result (List ref 3 stmt) outer))
          (right (%sql-query-result (List ref 4 stmt) outer)))
      (unless (= (List length (first left)) (List length (first right)))
        (error "Binder Error: Set operations can only apply to expressions with the same number of result columns"))
      (let ((types (List map %sql-set-type (List second left) (List second right))))
        (let ((as-types (fn (_ result)
                          (List map
                            (fn (_ row) (List map (fn (_ v t) (pair t (sql-cast v t))) row types))
                            (List third result)))))
          (list (first left) types
                ((class-static-ref SqlSet (List second stmt)) SqlSet
                 (as-types left) (as-types right) (List third stmt))))))))

; --- WITH --------------------------------------------------------------------

; A FROM's ENTRY names the table KEY, a name in lower case
(def %sql-entry-reads?
  (fn (_ entry key)
    (let ((table (first (if (symbol? (first entry)) (rest entry) entry))))
      (and (not (pair? table)) (str=? (%sql-key table) key)))))

; NODE has, at any depth, a SELECT whose FROM names the table KEY
(def %sql-reads?
  (fn (self node key)
    (match
      ((not (pair? node)) #f)
      ((and (eq? (first node) (lit select))
            (List any? (fn (_ entry) (%sql-entry-reads? entry key)) (List third node)))
        #t)
      (#t (or (self (first node) key) (self (rest node) key))))))

; RESULT with COLUMNS for the names of its first columns
(def %sql-renamed
  (fn (_ result columns)
    (let ((n (Num min (List length columns) (List length (first result)))))
      (list (List append (List take n columns) (List drop n (first result)))
            (List second result) (List third result)))))

; ROWS, each value as the type of its place among TYPES
(def %sql-rows-as
  (fn (_ rows types)
    (List map (fn (_ row) (List map (fn (_ v t) (pair t (sql-cast v t))) row types)) rows)))

; The rows of a table that reads itself.  Its statement is a UNION: the
; left side is answered once, and the right side again and again, each
; time with the table holding only the rows the time before added, until
; a time adds none.  The names and the types are the left side's.  Under
; UNION without ALL a row is added once.
(def %sql-recursive-result
  (fn (_ table outer)
    (let ((key (%sql-key (first table))) (stmt (List second table))
          (seen (Dict make)))
      (let ((start (%sql-renamed (%sql-query-result (List ref 3 stmt) outer) (List third table)))
            (fresh (fn (_ rows)
                     (if (List third stmt) rows
                       (List filter
                         (fn (_ row)
                           (let ((k (%sql-values-key row)))
                             (if (seen has? k) #f (do (seen set! k #t) #t))))
                         rows)))))
        ((fn (self added all)
           (if (null? added) (list (first start) (List second start) all)
             (do (%sql-withs set! key (list (first start) (List second start) added))
                 (let ((step (%sql-query-result (List ref 4 stmt) outer)))
                   (unless (= (List length (first step)) (List length (first start)))
                     (error "Binder Error: Set operations can only apply to expressions with the same number of result columns"))
                   (self (fresh (%sql-rows-as (List third step) (List second start)))
                         (List append all added))))))
         (fresh (List third start)) ())))))

; What one table of a WITH holds.  A table that reads itself is a UNION
; whose right side alone reads it, under WITH RECURSIVE.
(def %sql-with-result
  (fn (_ table recursive outer)
    (let ((key (%sql-key (first table))) (stmt (List second table)))
      (match
        ((not (%sql-reads? stmt key))
          (%sql-renamed (%sql-query-result stmt outer) (List third table)))
        ((and recursive (eq? (first stmt) (lit set)) (eq? (List second stmt) (lit union))
              (not (%sql-reads? (List ref 3 stmt) key)))
          (%sql-recursive-result table outer))
        (#t (error (Str8 str "Binder Error: Circular reference to CTE \"" (first table)
                             "\", use WITH RECURSIVE to use recursive CTEs.")))))))

(def %sql-query-result
  (fn (_ stmt outer)
    (if (eq? (first stmt) (lit set)) (%sql-set-result stmt outer)
    (if (eq? (first stmt) (lit with))
      (let ((names (List map (fn (_ t) (%sql-key (first t))) (List second stmt))))
        (let ((hidden (List map (fn (_ name) (%sql-withs get name)) names)))
          (List for-each
            (fn (_ t)
              (%sql-withs set! (%sql-key (first t))
                          (%sql-with-result t (List ref 3 stmt) outer)))
            (List second stmt))
          (let ((result (%sql-query-result (List third stmt) outer)))
            (List for-each
              (fn (_ name was)
                (if (null? was) (%sql-withs del! name) (%sql-withs set! name was)))
              names hidden)
            result)))
      (%sql-select-result stmt outer)))))

(sql-select-runner! %sql-query-result)

; A table's columns as a scope's, under its own name
(def %sql-table-scope-columns
  (fn (_ table)
    (List map (fn (_ c) (sql-column (first table) (first c) (List second c)))
              (List second table))))

; TABLE with ROWS for its rows
(def %sql-store!
  (fn (_ table rows)
    (%sql-tables set! (%sql-key (first table))
      (list (first table) (List second table) rows))
    ()))

(def-class SqlStatement ()
  (static
    (method select (self stmt) (%sql-query-result stmt ()))
    (method with (self stmt) (%sql-query-result stmt ()))
    (method set (self stmt) (%sql-query-result stmt ()))
    ; Every SET is worked out from the row as it was
    ; A setting of the session: its time zone, the one there is
    (method setting (self stmt)
      (unless (str=? (sql-lower (List second stmt)) "timezone")
        (error (Str8 str "Catalog Error: unrecognized configuration parameter \""
                         (List second stmt) "\"")))
      (when (null? (sql-zone-session! (List third stmt)))
        (error (Str8 str "Not implemented Error: Unknown TimeZone '" (List third stmt) "'!")))
      ())
    (method update (self stmt)
      (when (sql-windowed? (rest (rest stmt)))
        (error "Binder Error: window functions are not allowed in UPDATE"))
      (let ((table (%sql-table (List second stmt))) (where (List ref 3 stmt)))
        (let ((columns (%sql-table-scope-columns table))
              (places (List map
                        (fn (_ set)
                          (let ((i (List find-index
                                     (fn (_ c) (sql-same-name? (first c) (first set)))
                                     (List second table))))
                            (when (null? i)
                              (error (Str8 str "Binder Error: Referenced update column "
                                               (first set) " not found in table!")))
                            (pair i (List second set))))
                        (List third stmt))))
          (%sql-store! table
            (List map
              (fn (_ row)
                (let ((scope (sql-scope columns row () ())))
                  (if (or (null? where) (eq? (sql-truth (sql-eval where scope)) #t))
                    (List map
                      (fn (_ j old column)
                        (let ((set (List find (fn (_ p) (= (first p) j)) places)))
                          (if (null? set) old
                            (sql-cast (sql-eval (rest set) scope) (List second column)))))
                      (List range 0 (List length row)) row (List second table))
                    row)))
              (List third table))))))
    ; A table's rows, or a select statement's, written to a file
    (method copy-to (self stmt)
      (let ((source (List second stmt)))
        (sql-file-write
          (if (pair? source) (%sql-query-result source ())
            (%sql-query-result
              (list (lit select) (list (list (list (lit star) ()) ())) (list (list source ()))
                    () () () () () () #f ())
              ()))
          (List third stmt) (List ref 3 stmt) (List ref 4 stmt))))
    ; A file's rows added to a table, each value cast to its column
    (method copy-from (self stmt)
      (let ((table (%sql-table (List second stmt)))
            (result (sql-file-read (List third stmt) (List ref 3 stmt))))
        (let ((places (%sql-places table ())))
          (%sql-store! table
            (List append (List third table)
              (List map (fn (_ values) (%sql-insert-row table places () values))
                        (List third result)))))))
    (method delete (self stmt)
      (let ((table (%sql-table (List second stmt))) (where (List third stmt)))
        (let ((columns (%sql-table-scope-columns table)))
          (%sql-store! table
            (if (null? where) ()
              (List reject
                (fn (_ row) (eq? (sql-truth (sql-eval where (sql-scope columns row () ()))) #t))
                (List third table)))))))
    ; A table made AS a select statement has its columns and its rows
    (method create (self stmt)
      (let ((name (List second stmt)))
        (let ((result (if (symbol? (first (List third stmt)))
                        (%sql-query-result (List third stmt) ())
                        ())))
          (let ((columns (if (null? result) (List third stmt)
                           (List map (fn (_ n t) (list n t)) (first result) (List second result))))
                (rows (if (null? result) ()
                        (List map (fn (_ row) (List map rest row)) (List third result)))))
            (%sql-distinct-columns columns)
            (match
              ((not (%sql-tables has? (%sql-key name)))
                (%sql-tables set! (%sql-key name) (list name columns rows)))
              ((List ref 3 stmt)
                (%sql-tables set! (%sql-key name) (list name columns rows)))
              ((not (List ref 4 stmt))
                (error (Str8 str "Catalog Error: Table with name \"" name
                                 "\" already exists!"))))
            ()))))
    (method insert (self stmt)
      (let ((table (%sql-table (List second stmt))) (given (List ref 3 stmt)))
        (let ((places (%sql-places table (List third stmt)))
              (rows-of-values
                (if (and (not (null? given)) (symbol? (first given)))
                  (List third (%sql-query-result given ()))
                  (List map (fn (_ exprs) (List map (fn (_ e) (sql-eval e ())) exprs)) given))))
          (%sql-store! table
            (List append (List third table)
              (List map
                (fn (_ values) (%sql-insert-row table places (List third stmt) values))
                rows-of-values))))))
    (method drop (self stmt)
      (let ((name (List second stmt)))
        (if (%sql-tables has? (%sql-key name))
          (%sql-tables del! (%sql-key name))
          (unless (List third stmt) (%sql-table name)))
        ()))))

; A statement run.  What a WITH named in a run that raised is not left for
; this one.
(def sql-execute
  (fn (_ stmt)
    (List for-each (fn (_ name) (%sql-withs del! name)) (%sql-withs keys))
    ((class-static-ref SqlStatement (first stmt)) SqlStatement stmt)))

(provide sql/exec sql-execute sql-table-names sql-table-columns)

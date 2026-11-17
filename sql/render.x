; # x-sql -- SQL on x-lang
;
; ## sql/render.x -- a result as a table
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; DuckDB's box: a heading of names and types, centred, then the rows, a
; number to the right of its column and anything else to the left.  A
; column is as wide as the widest thing in it, counted in terminal cells.
; A result with no rows is the heading, closed, and "0 rows" under it.
;
; On a terminal that takes colour the box and the types are dim, the names
; bold and a NULL dim.  A cell is padded before it is coloured, so the
; codes take no room, and with colour off the text is DuckDB's byte for
; byte.

(module sql/render)
(import x/type/list)
(import x/type/str)
(import x/tui/width)
(import x/repl/ansi)
(import sql/eval sql-value-text sql-type-heading sql-numeric-type? sql-null?)

(def %sql-spaces (fn (_ n) (Str8 repeat n " ")))

; TEXT in W cells: centred, to the right, or to the left
(def %sql-centre
  (fn (_ w text)
    (let ((room (- w (Width text text))))
      (let ((left (Num quotient room 2)))
        (Str8 append (%sql-spaces left) text (%sql-spaces (- room left)))))))
(def %sql-right
  (fn (_ w text) (Str8 append (%sql-spaces (- w (Width text text))) text)))
(def %sql-left
  (fn (_ w text) (Str8 append text (%sql-spaces (- w (Width text text))))))

; A rule: LEFT, a run of dashes a column, MID between two, RIGHT
(def %sql-dim (fn (_ text) (Ansi wrap (Ansi dim) text)))
(def %sql-bold (fn (_ text) (Ansi wrap (Ansi bold) text)))

(def %sql-rule
  (fn (_ left mid right widths)
    (Str8 append
      (%sql-dim
        (Str8 append left
          (Str8 join mid (List map (fn (_ w) (Str8 repeat (+ w 2) "─")) widths))
          right))
      "\n")))

; A line of cells, each already as wide as its column
(def %sql-line
  (fn (_ cells)
    (Str8 append (%sql-dim "│") " "
                 (Str8 join (Str8 append " " (%sql-dim "│") " ") cells)
                 " " (%sql-dim "│") "\n")))

(def %sql-max (fn (_ a b) (if (> a b) a b)))

; TEXT on one line: a newline, a return and a tab as DuckDB shows them in
; a cell, a backslash and a letter
(def %sql-one-line
  (fn (_ text)
    (Str8 replace "\t" "\\t"
      (Str8 replace "\r" "\\r"
        (Str8 replace "\n" "\\n" text)))))

; The J-th column's width: its name's, its type's, or its widest cell's.
; A cell of TEXTS is (TEXT . NULL).
(def %sql-width
  (fn (_ j name type texts)
    (List fold
      (fn (_ w row) (%sql-max w (Width text (first (List ref j row)))))
      (%sql-max (Width text name) (Width text (sql-type-heading type)))
      texts)))

; The line under a result with no rows: "0 rows", as far in as centres it
; under the box, the line two cells short of the box's width
(def %sql-no-rows
  (fn (_ widths)
    (let ((across (+ (List sum widths) (* 3 (List length widths)) 1)))
      (let ((left (Num quotient (- across 6) 2)))
        (Str8 append (%sql-spaces left) "0 rows"
                     (%sql-spaces (- across 8 left)) "\n")))))

; WIDTHS, a lone column made wide enough for "0 rows" when no row is shown
(def %sql-fitted
  (fn (_ widths texts)
    (if (and (null? texts) (null? (rest widths)) (< (first widths) 6))
      (list 6)
      widths)))

(def sql-render
  (fn (_ result)
    (let ((names (first result))
          (types (List second result))
          (texts (List map
                   (fn (_ row)
                     (List map
                       (fn (_ v) (pair (%sql-one-line (sql-value-text v)) (sql-null? v)))
                       row))
                   (List third result))))
      (let ((js (List range 0 (List length names))))
        (let ((widths (%sql-fitted
                        (List map
                          (fn (_ j) (%sql-width j (List ref j names) (List ref j types) texts))
                          js)
                        texts)))
          (Str8 append
            (%sql-rule "┌" "┬" "┐" widths)
            (%sql-line (List map (fn (_ j) (%sql-bold (%sql-centre (List ref j widths) (List ref j names)))) js))
            (%sql-line (List map (fn (_ j) (%sql-dim (%sql-centre (List ref j widths) (sql-type-heading (List ref j types))))) js))
            (if (null? texts) "" (%sql-rule "├" "┼" "┤" widths))
            (Str8 join ""
              (List map
                (fn (_ row)
                  (%sql-line
                    (List map
                      (fn (_ j)
                        (let ((cell ((if (sql-numeric-type? (List ref j types))
                                       %sql-right %sql-left)
                                     (List ref j widths) (first (List ref j row)))))
                          (if (rest (List ref j row)) (%sql-dim cell) cell)))
                      js)))
                texts))
            (%sql-rule "└" "┴" "┘" widths)
            (if (null? texts) (%sql-no-rows widths) "")))))))

(provide sql/render sql-render)

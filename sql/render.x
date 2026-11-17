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
; With colour off a text is itself, and wrapping it is not asked for
(def %sql-dim
  (fn (_ text) (if (Ansi enabled?) (Ansi wrap (Ansi dim) text) text)))
(def %sql-bold
  (fn (_ text) (if (Ansi enabled?) (Ansi wrap (Ansi bold) text) text)))

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
    (if (or (Str8 includes? "\n" text) (Str8 includes? "\r" text)
            (Str8 includes? "\t" text))
      (Str8 replace "\t" "\\t"
        (Str8 replace "\r" "\\r"
          (Str8 replace "\n" "\\n" text)))
      text)))

; Each column's width: its name's, its type's, or its widest cell's.  A
; cell of ROWS is (TEXT . NULL).  The rows are walked once, every column
; in step.
(def %sql-widths
  (fn (_ names headings rows)
    (List fold
      (fn (_ widths row)
        (List map (fn (_ w cell) (%sql-max w (Width text (first cell)))) widths row))
      (List map (fn (_ name heading) (%sql-max (Width text name) (Width text heading)))
                names headings)
      rows)))

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

; A table: NAMES and HEADINGS a text a column, RIGHTS whether each
; column's cells go to the right, ROWS lists of (TEXT . NULL) cells, each
; text on one line
(def sql-render-table
  (fn (_ names headings rights rows)
    (let ((widths (%sql-fitted (%sql-widths names headings rows) rows)))
      (Str8 append
        (%sql-rule "┌" "┬" "┐" widths)
        (%sql-line (List map (fn (_ w name) (%sql-bold (%sql-centre w name))) widths names))
        (%sql-line (List map (fn (_ w heading) (%sql-dim (%sql-centre w heading))) widths headings))
        (if (null? rows) "" (%sql-rule "├" "┼" "┤" widths))
        (Str8 join ""
          (List map
            (fn (_ row)
              (%sql-line
                (List map
                  (fn (_ w right cell)
                    (let ((text ((if right %sql-right %sql-left) w (first cell))))
                      (if (rest cell) (%sql-dim text) text)))
                  widths rights row)))
            rows))
        (%sql-rule "└" "┴" "┘" widths)
        (if (null? rows) (%sql-no-rows widths) "")))))

; ROWS with each cell's text on one line
(def sql-one-line-rows
  (fn (_ rows)
    (List map
      (fn (_ row) (List map (fn (_ c) (pair (%sql-one-line (first c)) (rest c))) row))
      rows)))

; A result of the engine's, (NAMES TYPES ROWS) with each row a list of its
; values.  Only text can hold a newline.
(def sql-render
  (fn (_ result)
    (sql-render-table
      (first result)
      (List map sql-type-heading (List second result))
      (List map sql-numeric-type? (List second result))
      (List map
        (fn (_ row)
          (List map
            (fn (_ v)
              (pair (if (eq? (first v) (lit varchar)) (%sql-one-line (sql-value-text v))
                      (sql-value-text v))
                    (sql-null? v)))
            row))
        (List third result)))))

(provide sql/render sql-render sql-render-table sql-one-line-rows)

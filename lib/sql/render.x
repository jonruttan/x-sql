; # x-sql -- SQL on x-lang
;
; ## lib/sql/render.x -- a result as a table
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; DuckDB's box: a heading of names and types, centred, then the rows, a
; number to the right of its column and anything else to the left.  A
; column is as wide as the widest thing in it, counted in terminal cells.
; A result with no rows is the heading, closed, and "0 rows" under it; one
; of ten rows or more has its rows counted there, and its columns when
; the box is wide enough.  A result too long for a terminal is cut there to its
; first and last rows, with dots between, and says how many it shows.
;
; On a terminal that takes colour the box and the types are dim, the names
; bold, a NULL dim, and a value the colour the theme in use gives its kind
; where a statement is written: a number, a text, a truth.  A cell is padded before it is coloured, so the
; codes take no room, and with colour off the text is DuckDB's byte for
; byte.

(module sql/render)
(import x/type/list)
(import x/type/str)
(import x/tui/width)
(import x/repl/ansi)
(import x/tool/syntax)
(import x/type/dict)
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

; How many rows a result has before DuckDB counts them under its box
(def %sql-counted-rows 10)

; The line under a box ACROSS cells wide: TEXT as far in as centres it,
; the line two cells short of the box
(def %sql-under
  (fn (_ across text)
    (let ((n (Str8 length text)))
      (let ((left (Num quotient (- across n) 2)))
        (Str8 append (%sql-spaces left) text (%sql-spaces (- across 2 n left)) "\n")))))

; The line of a cut result that says how many rows are shown: as far in as
; centres it, or two cells in under a line that counts the columns, and a
; cell short of the box, which is how DuckDB writes it
(def %sql-shown-under
  (fn (_ across text centred)
    (let ((n (Str8 length text)))
      (let ((left (if centred (Num quotient (- across n) 2) 2)))
        (Str8 append (%sql-spaces left) text (%sql-spaces (- across 1 n left)) "\n")))))

; What is under a box of COUNT rows in columns of WIDTHS, SHOWN of them
; shown when it was cut and nil when it was not.  No rows: "0 rows".  Ten
; or more: the rows counted, and the columns too, to the right,
; when there are several and the box has room for both; nothing when it
; has not room for the rows.  A cut result says how many rows are shown,
; beside the count where there is room and under it where not.
(def %sql-footer
  (fn (_ widths count shown)
    (let ((across (+ (List sum widths) (* 3 (List length widths)) 1))
          (rows (Str8 str count " rows"))
          (columns (Str8 str (List length widths) " columns"))
          (said (if (null? shown) () (Str8 str "(" shown " shown)"))))
      (match
        ((= count 0) (%sql-under across rows))
        ((< count %sql-counted-rows) "")
        ((and (not (null? (rest widths)))
              (>= across (+ (Str8 length rows) (Str8 length columns) 6)))
          (let ((room (- across 4 (Str8 length rows) (Str8 length columns))))
            (match
              ((null? said) (Str8 append "  " rows (%sql-spaces room) columns "\n"))
              ((> room (Str8 length said))
                (Str8 append "  " rows " " said
                             (%sql-spaces (- room 1 (Str8 length said))) columns "\n"))
              (#t (Str8 append "  " rows (%sql-spaces room) columns "\n"
                               (%sql-shown-under across said #f))))))
        ((null? said)
          (if (>= across (+ (Str8 length rows) 4)) (%sql-under across rows) ""))
        ((>= across (+ (Str8 length rows) (Str8 length said) 5))
          (%sql-under across (Str8 append rows " " said)))
        (#t
          (Str8 append
            (if (>= across (+ (Str8 length rows) 4)) (%sql-under across rows) "")
            (%sql-shown-under across said #t)))))))

; --- a long result -----------------------------------------------------------

; How many rows a terminal is shown before a result is cut, DuckDB's
; number, and how many rows of dots stand for what is left out.  A result
; with no more rows over the most than the dots would take is shown whole.
(def %sql-terminal-rows 40)
(def %sql-dot-rows 3)

; The most rows shown, when .maxrows has said
(def %sql-render-held (Dict make))

; The most rows of a result that are shown: what .maxrows said, or
; DuckDB's forty when the result goes to a terminal; nil, every row, when
; it goes anywhere else, where a cut would lose what a file or a pipe is
; for
(def sql-max-rows
  (fn (_)
    (match
      ((%sql-render-held has? (lit most)) (%sql-render-held get (lit most)))
      ((Sys isatty 1) %sql-terminal-rows)
      (#t ()))))

(def sql-max-rows!
  (fn (_ n) (%sql-render-held set! (lit most) n) n))

; ROWS as they are shown when MOST is the most of them: every row, or the
; first half of MOST, rows of dots, and the last half.  A dot stands under
; the middle of the cell above it, and to the right in a column of RIGHTS.
; Answers (ROWS . CUT), CUT whether rows were left out.
(def %sql-shown-rows
  (fn (_ rows rights most)
    (if (or (null? most) (<= (List length rows) (+ most %sql-dot-rows))) (pair rows #f)
      (let ((top (List take (- most (Num quotient most 2)) rows))
            (bottom (List drop (- (List length rows) (Num quotient most 2)) rows)))
        (pair
          (List append top
            (if (null? bottom) ()
              (List repeat %sql-dot-rows
                (List map
                  (fn (_ right above)
                    (pair (if right "·"
                            (Str8 append
                              (%sql-spaces (Num quotient (%sql-max 0 (- (Width text (first above)) 1)) 2))
                              "·"))
                          #t))
                  rights (List last top))))
            bottom)
          #t)))))

; WIDTHS with the last made wide enough that a box says how many of its
; rows are shown
(def %sql-widened
  (fn (_ widths most)
    (let ((short (- (+ (Str8 length (Str8 str "(" most " shown)")) 4)
                    (+ (List sum widths) (* 3 (List length widths)) 1))))
      (if (< short 1) widths
        (List append (List take (- (List length widths) 1) widths)
                     (list (+ (List last widths) short)))))))

; WIDTHS, a lone column made wide enough for "0 rows" when no row is shown
(def %sql-fitted
  (fn (_ widths texts)
    (if (and (null? texts) (null? (rest widths)) (< (first widths) 6))
      (list 6)
      widths)))

; The class of the theme a value of the type T is coloured as: a number,
; a truth as the constant it is written as, a list or a struct as nothing,
; and anything else, which a statement writes in quotes, as a string
(def sql-value-class
  (fn (_ t)
    (match
      ((sql-numeric-type? t) (lit number))
      ((eq? t (lit boolean)) (lit constant))
      ((or (pair? t) (eq? t (lit null))) ())
      (#t (lit string)))))

; Each column's colour code, nil for none; all nil with colour off
(def %sql-codes
  (fn (_ classes)
    (List map
      (fn (_ class) (if (and (Ansi enabled?) (not (null? class))) (Syntax code class) ()))
      classes)))

; A table: NAMES and HEADINGS a text a column, RIGHTS whether each
; column's cells go to the right, ROWS lists of (TEXT . NULL) cells, each
; text on one line, and CLASSES each column's class of the theme, nil for
; a column with no colour.  A result longer than sql-max-rows is cut.
(def sql-render-table
  (fn (_ names headings rights all classes)
    (let ((most (sql-max-rows)))
     (let ((shown (%sql-shown-rows all rights most)))
      (let ((rows (first shown)))
       (let ((widths (let ((fitted (%sql-fitted (%sql-widths names headings rows) rows)))
                       (if (rest shown) (%sql-widened fitted most) fitted)))
             (codes (%sql-codes classes)))
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
                  (fn (_ w right code cell)
                    (let ((text ((if right %sql-right %sql-left) w (first cell))))
                      (match
                        ((rest cell) (%sql-dim text))
                        ((null? code) text)
                        (#t (Ansi wrap code text)))))
                  widths rights codes row)))
            rows))
        (%sql-rule "└" "┴" "┘" widths)
        (%sql-footer widths (List length all) (if (rest shown) most ())))))))))

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
        (List third result))
      (List map sql-value-class (List second result)))))

(provide sql/render sql-render sql-render-table sql-one-line-rows sql-value-class
  sql-max-rows sql-max-rows!)

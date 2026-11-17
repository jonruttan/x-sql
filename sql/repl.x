; # x-sql -- SQL on x-lang
;
; ## sql/repl.x -- the prompt
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The line editor reads the lines; this says what they mean, how they are
; coloured, which brackets pair, and what Tab offers.  An entry is
; statements up to a closing semicolon, over as many lines as it takes, or
; one line starting with a dot: a command of the prompt's own.

(module sql/repl)
(import x/type/list)
(import x/type/str)
(import x/type/class)
(import x/type/dict)
(import x/reader/lexer)
(import x/repl/ansi)
(import x/repl/line)
(import x/repl/lang)
(import x/tool/syntax)
(import sql/words
  sql-reserved sql-words sql-constants sql-type-words sql-aggregates)
(import sql/lex sql-lex)
(import sql/syntax sql-syntax-rules sql-syntax-classes)
(import sql/base sql-run sql-error-text sql-connect! sql-disconnect! sql-connection)
(import sql/exec sql-table-names sql-table-columns)
(import sql/eval sql-type-name)
(import sql/help sql-help-topics sql-help-topic sql-help-show sql-help-index)

; --- a line's colours --------------------------------------------------------

; The grammar's lexer and the grammar over it, made when a line is first
; painted: a session that paints nothing compiles no states.  The image
; recache hook drops both, since what they hold is of the process that made
; them.
(def %sql-paint-held (Dict make))

(def %sql-paint-lexer
  (fn (_)
    (unless (%sql-paint-held has? (lit lexer))
      (%sql-paint-held set! (lit lexer) (Lexer make (sql-syntax-rules))))
    (%sql-paint-held get (lit lexer))))

(def %sql-paint-grammar
  (fn (_)
    (unless (%sql-paint-held has? (lit grammar))
      (%sql-paint-held set! (lit grammar)
        (Syntax over (%sql-paint-lexer) (sql-syntax-classes))))
    (%sql-paint-held get (lit grammar))))

; A bracket's code: its depth's colour, the three in turn as x-lang's own
; parens take them, inverse on the pair the cursor is beside; bold red for
; a close with nothing to close
(def %sql-mark-code
  (fn (_ mark)
    (let ((depth (List second mark)))
      (Str8 append
        (match
          ((< depth 0) (Ansi bold-red))
          ((= (Num remainder depth 3) 0) (Ansi yellow))
          ((= (Num remainder depth 3) 1) (Ansi magenta))
          (#t (Ansi cyan)))
        (if (List third mark) (Ansi inverse) "")))))

; The seam the editor calls: (%repl-paint window marks before).  WINDOW is
; the part of the line in view, MARKS the brackets in it by their offsets
; there, and BEFORE the text of the entry ahead of it, read with it so a
; string or a comment opened there colours the window's start.  Each span
; is drawn in its class's code of the theme in use, a marked bracket in its
; mark's.
(def sql-paint
  (fn (_ window . more)
    (if (not (Ansi enabled?)) window
      (let ((marks (if (null? more) () (first more)))
            (before (if (or (null? more) (null? (rest more)) (null? (List second more)))
                      "" (List second more))))
        (let ((text (Str8 append before window))
              (from (Str8 length before))
              (n (Str8 length window)))
          (Syntax ansi text ((%sql-paint-grammar) spans text from n) from n
            (fn (_ span)
              (let ((mark (List find
                            (fn (_ m) (= (+ from (first m)) (first span)))
                            marks)))
                (if (null? mark) (Syntax code (List third span))
                  (%sql-mark-code mark))))))))))

; --- brackets ----------------------------------------------------------------

(def %sql-openers (list "(" "[" "{"))
(def %sql-closers (list ")" "]" "}"))

; The brackets of TOKENS as (OFFSET . OPENS), in order: the ones the lexer
; reads as operators, so one inside a string or a comment is none
(def %sql-brackets
  (fn (self tokens at)
    (if (null? tokens) ()
      (let ((text (List second (first tokens))))
        (let ((more (self (rest tokens) (+ at (Str8 length text)))))
          (match
            ((not (eq? (first (first tokens)) (lit op))) more)
            ((List includes? text %sql-openers) (pair (pair at #t) more))
            ((List includes? text %sql-closers) (pair (pair at #f) more))
            (#t more)))))))

; BRACKETS as (OFFSET DEPTH PARTNER): the nesting depth from 0, shared by
; the two halves of a pair, and the other half's offset; a close with
; nothing to close is at depth -1 with no partner.  OPEN holds the opens
; not yet closed, innermost first, and DONE what is settled, newest first.
(def %sql-paired
  (fn (self brackets open done)
    (match
      ((null? brackets)
        (List append
          (List map (fn (_ o) (list (first o) (rest o) ())) open)
          done))
      ((rest (first brackets))
        (self (rest brackets)
              (pair (pair (first (first brackets)) (List length open)) open)
              done))
      ((null? open)
        (self (rest brackets) open
              (pair (list (first (first brackets)) -1 ()) done)))
      (#t
        (self (rest brackets) (rest open)
              (pair (list (first (first brackets)) (rest (first open)) (first (first open)))
                    (pair (list (first (first open)) (rest (first open)) (first (first brackets)))
                          done)))))))

; The bracket the cursor is beside: one just before it first, then one
; under it
(def %sql-beside
  (fn (_ paired at)
    (let ((before (List find (fn (_ m) (= (first m) (- at 1))) paired)))
      (if (null? before) (List find (fn (_ m) (= (first m) at)) paired) before))))

; The seam the editor calls: a mark for every bracket of S as
; (OFFSET DEPTH FOCUSED), FOCUSED on the pair the cursor at AT is beside
(def sql-marks
  (fn (_ s at)
    (let ((paired (%sql-paired (%sql-brackets ((%sql-paint-lexer) read-str s) 0) () ())))
      (let ((beside (%sql-beside paired at)))
        (List sort (fn (_ a b) (< (first a) (first b)))
          (List map
            (fn (_ m)
              (list (first m) (List second m)
                    (if (null? beside) #f
                      (or (= (first m) (first beside))
                          (and (not (null? (List third beside)))
                               (= (first m) (List third beside)))))))
            paired))))))

; --- completion --------------------------------------------------------------

(def %sql-word-byte?
  (fn (_ c)
    (let ((b (Char ->int c)))
      (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90))
          (and (>= b 48) (<= b 57)) (= b 95)))))

; The word being typed: the letters, digits and underscores at the end of
; TEXT
(def %sql-word-at
  (fn (_ text)
    (let ((n (Str8 length text)))
      (let ((start ((fn (self i)
                      (if (and (> i 0) (%sql-word-byte? (Str8 ref (- i 1) text)))
                        (self (- i 1))
                        i))
                    n)))
        (Str8 sub start (- n start) text)))))

; The words of the language, upper case
(def %sql-language-words
  (fn (_)
    (List append sql-reserved sql-words
                 (List map first sql-type-words))))

; Every name Tab may offer for WORD: the language's words in the case WORD
; is typed in, the functions, the tables and their columns
(def %sql-candidates
  (fn (_ word)
    (let ((lower (str=? word (Str8 downcase word))))
      (List append
        (List map (fn (_ w) (if lower (Str8 downcase w) w)) (%sql-language-words))
        sql-aggregates
        (sql-table-names)
        (List flat-map
          (fn (_ table) (List map first (sql-table-columns table)))
          (sql-table-names))))))

(def %sql-dot-names
  (list ".connect" ".disconnect" ".exit" ".help" ".quit" ".schema" ".tables"))

; The seam the editor calls: the word before the cursor and the names it
; could become, sorted and each once.  A line that starts with a dot
; completes the prompt's commands, and an empty word nothing.
(def sql-complete
  (fn (_ ed)
    (let ((text (ed before)))
      (if (and (Str8 starts? "." text) (null? (Str8 index-of " " text)))
        (pair text (List filter (fn (_ name) (Str8 starts? text name)) %sql-dot-names))
        (let ((word (%sql-word-at text)))
          (pair word
            (if (= (Str8 length word) 0) ()
              (List uniq
                (List sort (fn (_ a b) (Str8 <? a b))
                  (List filter
                    (fn (_ name) (Str8 starts? (Str8 downcase word) (Str8 downcase name)))
                    (%sql-candidates word)))))))))))

; --- an entry ----------------------------------------------------------------

; The last token of TEXT that is not a blank or a comment is a semicolon
(def %sql-closed?
  (fn (_ text)
    (let ((last (List find
                  (fn (_ tok)
                    (not (or (eq? (first tok) (lit blank))
                             (eq? (first tok) (lit comment)))))
                  (List reverse (sql-lex text)))))
      (if (null? last) #f
        (and (eq? (first last) (lit op)) (str=? (List second last) ";"))))))

; TEXT and the lines after it up to a closing semicolon; nil when the
; entry is abandoned.  The end of input closes it with what there is.  The
; editor is given the lines so far, so a line is painted as the rest of
; the entry: inside a string or a comment an earlier line opened.
(def %sql-entry
  (fn (self text)
    (if (%sql-closed? text) text
      (let ((line (Line read %repl-prompt-more text)))
        (match
          ((eq? line (lit cancel)) ())
          ((eq? line (lit eof)) text)
          (#t (self (Str8 append text "\n" line))))))))

; --- the prompt's commands ---------------------------------------------------

; A table as the statement that would make it
(def %sql-schema
  (fn (_ name)
    (display (Str8 append "CREATE TABLE " name "("
               (Str8 join ", "
                 (List map
                   (fn (_ c) (Str8 append (first c) " " (sql-type-name (List second c))))
                   (sql-table-columns name)))
               ");"))
    (newline)))

; The prompt says where statements go: sql> here, and a server's database
; and host when there is one
(def %sql-prompt!
  (fn (_)
    (Lang register! "sql"
      (list (pair (lit %repl-prompt)
                  (if (null? (sql-connection)) "sql> "
                    (Str8 append (sql-connection) "> ")))))
    (when (str=? (Lang current) "sql") (Lang use! "sql"))))

; A command is a static method named for it, taking what follows it on the
; line
(def-class SqlDot ()
  (static
    (method quit (self rest-of-line) (Sys exit 0))
    (method exit (self rest-of-line) (Sys exit 0))
    (method connect (self rest-of-line)
      (display (Str8 append "connected to " (sql-connect! rest-of-line)))
      (newline)
      (%sql-prompt!))
    (method disconnect (self rest-of-line)
      (sql-disconnect!)
      (%sql-prompt!))
    (method tables (self rest-of-line)
      (List for-each (fn (_ name) (display name) (newline)) (sql-table-names)))
    (method schema (self rest-of-line)
      (if (= (Str8 length rest-of-line) 0)
        (List for-each %sql-schema (sql-table-names))
        (%sql-schema rest-of-line)))
    (method help (self rest-of-line)
      (if (= (Str8 length rest-of-line) 0) (sql-help-index)
        (let ((topic (sql-help-topic rest-of-line)))
          (if (null? topic)
            (do (display (Str8 append "no help on " rest-of-line "; .help lists the topics"))
                (newline))
            (sql-help-show topic)))))))

; LINE without its dot: the command's name, and the rest of the line
(def %sql-dot
  (fn (_ line)
    (let ((at (Str8 index-of " " line)))
      (let ((word (if (null? at) line (Str8 sub 0 at line)))
            (rest-of-line (if (null? at) ""
                            (Str8 trim (Str8 sub at (Str8 length line) line)))))
        (let ((command (class-static-ref SqlDot (Str8 ->sym word))))
          (if (null? command)
            (do (display (Str8 append "unknown command: ." word "; try .help"))
                (newline))
            (guard (e (do (display (sql-error-text e)) (newline)))
              (command SqlDot rest-of-line))))))))

; The seam the editor calls with a finished line
(def sql-eval-line
  (fn (_ line)
    (let ((text (Str8 trim line)))
      (match
        ((= (Str8 length text) 0) ())
        ((Str8 starts? "." text) (%sql-dot (Str8 sub 1 (Str8 length text) text)))
        (#t
          (let ((entry (%sql-entry line)))
            (unless (null? entry)
              (guard (e (do (display (sql-error-text e)) (newline)))
                (display (sql-run entry))))))))))

(def sql-repl-register!
  (fn (_)
    (Lang register! "sql"
      (list (pair (lit %repl-prompt) "sql> ")
            (pair (lit %repl-prompt-more) "...> ")
            (pair (lit %repl-paint) sql-paint)
            (pair (lit %repl-marks) sql-marks)
            (pair (lit %repl-complete) sql-complete)
            (pair (lit %repl-eval-line) sql-eval-line)))))

; What the painter holds is of the process that made it: a state image
; loaded elsewhere makes its own
(set! %image-recache-hooks
  (pair (fn (_) (%sql-paint-held del! (lit lexer))
                (%sql-paint-held del! (lit grammar)))
        %image-recache-hooks))

; Whether this lang owns the session: the wrapper names the first -l in
; %lang-lead, and a bundle named by a later one is loaded beside it.  A
; wrapper older than the seam binds nothing, and the answer then is yes.
(def sql-leads?
  (fn (_) (guard (_ #t) (str=? %lang-lead "sql"))))

(provide sql/repl
  sql-eval-line sql-paint sql-marks sql-complete sql-leads?
  sql-repl-register!)

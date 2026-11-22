; # x-sql -- SQL on x-lang
;
; ## lib/sql/lex.x -- statement text to tokens
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Two readings of one text.  sql-lex is every byte of it as a token, blanks
; and comments included, which is what a painter colours.  sql-tokenize is
; what the parser reads, by a lexer that drops the blanks and the comments
; itself:
;
;   (kw "SELECT")   a reserved word, upper case
;   (id "name")     an identifier as written
;   (qid "Name")    an identifier written in double quotes, the quotes gone
;   (str "text")    a string constant, the quotes gone
;   (num "42" 1)    a number as written; 1 an integer, 2 a fraction or an
;                   exponent, 3 hexadecimal
;   (op "<=")       an operator or a punctuation mark
;
; A quote inside a quoted literal is written twice, and the Lexer reads
; 'it''s' as one literal; sql-tokenize writes the pair as one quote.  A
; literal left open is not a token, and its quote is the error.

(module sql/lex)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/type/dict)
(import sql/words sql-upper sql-reserved sql-ops)

; The text the Lexer appends so the last token meets a delimiter: a form
; feed, which the run of blanks leaves out, so a run at the end of the text
; ends on it.  A form feed in the text is a blank all the same, by a rule of
; its own.
(def %sql-end (Str8 make 1 (Char from-int 12)))
(def %sql-blanks (list 32 9 13 10))
(def %sql-name-start (list (pair 97 122) (pair 65 90) 95))
(def %sql-name-rest (list (pair 97 122) (pair 65 90) (pair 48 57) 95 36))

(def sql-lexer-rules
  (fn (_)
    (list (Lexer run (lit blank) %sql-blanks %sql-blanks)
          (Lexer table (lit blank) (list %sql-end))
          (Lexer until (lit comment) "--" "\n" (lit to-end))
          (Lexer until (lit comment) "/*" "*/")
          (Lexer quoted (lit str) 39 39 39)
          (Lexer quoted (lit qid) 34 34 34)
          (Lexer run (lit id) %sql-name-start %sql-name-rest)
          (Lexer number (lit num) ())
          (Lexer table (lit op) sql-ops)
          (Lexer any (lit bad)))))

(def %sql-lexer (Lexer make (sql-lexer-rules) %sql-end))

(def sql-lex (fn (_ text) (%sql-lexer read-str text)))

; The parser's lexer: the same tokens with the blanks and the comments
; dropped, the form feed the end text is among the blanks
(def %sql-parse-lexer
  (Lexer make
    (list (Lexer skip (pair 12 %sql-blanks))
          (Lexer until () "--" "\n" (lit to-end))
          (Lexer until () "/*" "*/")
          (Lexer quoted (lit str) 39 39 39)
          (Lexer quoted (lit qid) 34 34 34)
          (Lexer run (lit id) %sql-name-start %sql-name-rest)
          (Lexer number (lit num) ())
          (Lexer table (lit op) sql-ops)
          (Lexer any (lit bad)))
    %sql-end))

; A quoted literal without its two quotes, each quote written twice inside
; it written once
(def %sql-unquote
  (fn (_ text quote)
    (let ((inner (Str8 sub 1 (- (Str8 length text) 2) text))
          (twice (Str8 append quote quote)))
      (if (Str8 includes? twice inner)
        (Str8 join quote (Str8 split twice inner))
        inner))))

; A word as written to its token, each distinct spelling worked out once
(def %sql-words (Dict make))

(def %sql-word
  (fn (_ text)
    (unless (%sql-words has? text)
      (%sql-words set! text
        (let ((up (sql-upper text)))
          (if (List includes? up sql-reserved)
            (list (lit kw) up)
            (list (lit id) text)))))
    (%sql-words get text)))

; One raw token to the parser's
(def %sql-cook
  (fn (_ tok)
    (let ((tag (first tok)) (text (List second tok)))
      (match
        ((eq? tag (lit id)) (%sql-word text))
        ((eq? tag (lit str)) (list tag (%sql-unquote text "'")))
        ((eq? tag (lit qid)) (list tag (%sql-unquote text "\"")))
        ((eq? tag (lit bad))
          (error
            (match
              ((str=? text "'") "Parser Error: unterminated string literal")
              ((str=? text "\"") "Parser Error: unterminated quoted identifier")
              (#t (Str8 str "Parser Error: syntax error at or near \"" text "\"")))))
        (#t tok)))))

(def sql-tokenize
  (fn (_ text) (List map %sql-cook (%sql-parse-lexer read-str text))))

(provide sql/lex sql-lexer-rules sql-lex sql-tokenize)

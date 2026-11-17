; # x-sql -- SQL on x-lang
;
; ## sql/lex.x -- statement text to tokens
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Two readings of one text.  sql-lex is every byte of it as a token, blanks
; and comments included, which is what a painter colours.  sql-tokenize is
; what the parser reads:
;
;   (kw "SELECT")   a reserved word, upper case
;   (id "name")     an identifier as written
;   (qid "Name")    an identifier written in double quotes, the quotes gone
;   (str "text")    a string constant, the quotes gone
;   (num "42" 1)    a number as written; 1 an integer, 2 a fraction or an
;                   exponent, 3 hexadecimal
;   (op "<=")       an operator or a punctuation mark
;
; A quote inside a quoted literal is written twice.  The Lexer reads
; 'it''s' as two literals with nothing between them, and sql-tokenize joins
; them with one quote: a blank or a comment between two literals keeps them
; apart.  A literal left open is not a token, and its quote is the error.

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
          (Lexer quoted (lit str) 39 39 ())
          (Lexer quoted (lit qid) 34 34 ())
          (Lexer run (lit id) %sql-name-start %sql-name-rest)
          (Lexer number (lit num) ())
          (Lexer table (lit op) sql-ops)
          (Lexer any (lit bad)))))

(def %sql-lexer (Lexer make (sql-lexer-rules) %sql-end))

(def sql-lex (fn (_ text) (%sql-lexer read-str text)))

; A quoted literal without its two quotes
(def %sql-unquote
  (fn (_ text) (Str8 sub 1 (- (Str8 length text) 2) text)))

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

; RAW to the parser's tokens, newest first in ACC.  GLUE is the tag of the
; quoted literal the last raw token was, nil when anything else was.
(def %sql-cook
  (fn (self raw acc glue)
    (if (null? raw) (List reverse acc)
      (let ((tok (first raw)))
        (let ((tag (first tok)) (text (List second tok)))
          (match
            ((eq? tag (lit blank)) (self (rest raw) acc ()))
            ((eq? tag (lit comment)) (self (rest raw) acc ()))
            ((or (eq? tag (lit str)) (eq? tag (lit qid)))
              (if (eq? glue tag)
                (self (rest raw)
                      (pair (list tag
                              (Str8 append (List second (first acc))
                                           (if (eq? tag (lit str)) "'" "\"")
                                           (%sql-unquote text)))
                            (rest acc))
                      tag)
                (self (rest raw) (pair (list tag (%sql-unquote text)) acc) tag)))
            ((eq? tag (lit id)) (self (rest raw) (pair (%sql-word text) acc) ()))
            ((eq? tag (lit bad))
              (error
                (match
                  ((str=? text "'") "Parser Error: unterminated string literal")
                  ((str=? text "\"") "Parser Error: unterminated quoted identifier")
                  (#t (Str8 str "Parser Error: syntax error at or near \"" text "\"")))))
            (#t (self (rest raw) (pair tok acc) ()))))))))

(def sql-tokenize (fn (_ text) (%sql-cook (sql-lex text) () ())))

(provide sql/lex sql-lexer-rules sql-lex sql-tokenize)

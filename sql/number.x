; # x-sql -- SQL on x-lang
;
; ## sql/number.x -- doubles and decimals, exactly
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A DOUBLE is the platform's float.  What is here is what must be exact
; about one: the integer and the power of two it is, the fewest digits
; that read back as it, which is how DuckDB shows it, and its rounding to
; an integer or to a decimal.
;
; A DECIMAL is an integer and a scale: 1.50 is 150 at scale 2.

(module sql/number)
(import x/type/list)
(import x/type/str)
(import x/num/tower)
(import x/num/float)

; --- powers ------------------------------------------------------------------

; BASE to the N, an exact integer, by squaring
(def %sql-power
  (fn (self base n)
    (match
      ((<= n 0) 1)
      ((= (Num remainder n 2) 0)
        (let ((half (self base (Num quotient n 2)))) (* half half)))
      (#t (* base (self base (- n 1)))))))

(def sql-pow10 (fn (_ n) (%sql-power 10 n)))
(def %sql-pow2 (fn (_ n) (%sql-power 2 n)))

; --- a double, exactly -------------------------------------------------------

(def %sql-two (Float from 2))

; The most a double is scaled by in one step: 2^500 leaves any double
; finite
(def %sql-step 500)

; X times 2^K, in steps a double can hold
(def %sql-scale2
  (fn (self x k)
    (match
      ((> k %sql-step)
        (self (* x (Float pow %sql-two (Float from %sql-step))) (- k %sql-step)))
      ((< k (- 0 %sql-step))
        (self (/ x (Float pow %sql-two (Float from %sql-step))) (+ k %sql-step)))
      ((>= k 0) (* x (Float pow %sql-two (Float from k))))
      (#t (/ x (Float pow %sql-two (Float from (- 0 k))))))))

; M and Q with every factor of two moved from M to Q
(def %sql-odd
  (fn (self m q)
    (if (and (> m 0) (= (Num remainder m 2) 0))
      (self (Num quotient m 2) (+ q 1))
      (pair m q))))

; A double's mantissa has 53 bits.  Scaling by one more than that past the
; exponent log2 answers leaves an integer though log2 be one off.
(def %sql-headroom 54)

; A positive finite double as (M . Q): it is M * 2^Q, M odd
(def %sql-split
  (fn (_ x)
    (let ((e (Float ->int (Float floor (Float log2 x)))))
      (%sql-odd (Float ->int (%sql-scale2 x (- %sql-headroom e)))
                (- e %sql-headroom)))))

(def %sql-bits
  (fn (self m n) (if (= m 0) n (self (Num quotient m 2) (+ n 1)))))

; --- the fewest digits -------------------------------------------------------

; What sets a binary float's digits: how far below its exponent a quarter
; of the gap to the next float lies, its least exponent that is not
; subnormal, and the most digits it needs to read back as itself.  A
; double has 53 bits of mantissa and a REAL 24.
(def %sql-double-form (list 54 -1022 17))
(def %sql-real-form (list 25 -126 9))

; The sign of R * 10^P - Y * 2^S, all integers
(def %sql-compare
  (fn (_ r p y s)
    (let ((left (* r (sql-pow10 p) (%sql-pow2 (- 0 s))))
          (right (* y (%sql-pow2 s) (sql-pow10 (- 0 p)))))
      (if (< left right) -1 (if (= left right) 0 1)))))

; X * 2^S over 10^P, rounded to the nearest integer
(def %sql-rounded
  (fn (_ x s p)
    (let ((a (* x (%sql-pow2 s) (sql-pow10 (- 0 p))))
          (b (* (%sql-pow2 (- 0 s)) (sql-pow10 p))))
      (Num quotient (+ (* 2 a) b) (* 2 b)))))

; K with 10^K <= X * 2^S < 10^(K+1), from a guess
(def %sql-exponent10
  (fn (self x s k)
    (match
      ((< (%sql-compare 1 k x s) 0)
        (if (<= (%sql-compare 1 (+ k 1) x s) 0) (self x s (+ k 1)) k))
      ((= (%sql-compare 1 k x s) 0) k)
      (#t (self x s (- k 1))))))

; R and P with R's trailing zeros moved into P
(def %sql-trimmed
  (fn (self r p)
    (if (and (> r 0) (= (Num remainder r 10) 0))
      (self (Num quotient r 10) (+ p 1))
      (pair r p))))

; A positive finite float of FORM as (R . P): R * 10^P is the number of fewest
; digits that reads back as it, the nearest to it of that many digits.
;
; The double is X units of a quarter of the gap to the next double, 2^S.
; A number reads back as it when it is within half a gap: between LOW and
; HIGH, the ends included when the mantissa is even.  Below a power of two
; the gap is half as wide.  Fewer digits read back only if more do, so the
; count is found by halving.
(def %sql-float-digits
  (fn (_ x form)
    (let ((split (%sql-split x)) (lowest (List second form)))
      (let ((m (first split)) (q (rest split)))
        (let ((e (- (+ (%sql-bits m 0) q) 1)))
          (let ((s (- (if (< e lowest) lowest e)
                      (first form))))
            (let ((units (* m (%sql-pow2 (- q s)))))
              (let ((low (- units (if (and (= m 1) (> e lowest)) 1 2)))
                    (high (+ units 2))
                    (closed (= (Num remainder (Num quotient units 4) 2) 0))
                    (k (%sql-exponent10 units s
                         (Float ->int (Float floor (Float log10 x))))))
                (let ((reads-back
                        (fn (_ n)
                          (let ((p (+ (- k n) 1)))
                            (let ((r (%sql-rounded units s p)))
                              (let ((below (%sql-compare r p low s))
                                    (above (%sql-compare r p high s)))
                                (if closed (and (>= below 0) (<= above 0))
                                  (and (> below 0) (< above 0)))))))))
                  (let ((n ((fn (self least most)
                              (if (>= least most) least
                                (let ((mid (Num quotient (+ least most) 2)))
                                  (if (reads-back mid) (self least mid)
                                    (self (+ mid 1) most)))))
                            1 (List third form))))
                    (let ((p (+ (- k n) 1)))
                      (%sql-trimmed (%sql-rounded units s p) p))))))))))))

(def sql-double-digits (fn (_ x) (%sql-float-digits x %sql-double-form)))

; --- a double as text --------------------------------------------------------

; DuckDB writes a double out in full when its first digit is at 10^-4 to
; 10^15, and with an exponent outside that
(def %sql-fixed-least -4)
(def %sql-fixed-most 15)

(def %sql-zeros (fn (_ n) (Str8 repeat n "0")))

; DIGITS * 10^P written out in full, K the exponent of its first digit
(def %sql-fixed
  (fn (_ digits p k)
    (match
      ((>= p 0) (Str8 append digits (%sql-zeros p) ".0"))
      ((>= k 0)
        (Str8 append (Str8 sub 0 (+ k 1) digits) "."
                     (Str8 sub (+ k 1) (Str8 length digits) digits)))
      (#t (Str8 append "0." (%sql-zeros (- (- 0 k) 1)) digits)))))

; The same with an exponent: one digit, the rest after a point, and the
; exponent signed, of two digits at least
(def %sql-scientific
  (fn (_ digits k)
    (let ((e (Str8 str (if (< k 0) (- 0 k) k))))
      (Str8 append (Str8 sub 0 1 digits)
                   (if (> (Str8 length digits) 1)
                     (Str8 append "." (Str8 sub 1 (Str8 length digits) digits))
                     "")
                   "e" (if (< k 0) "-" "+")
                   (if (< (Str8 length e) 2) (Str8 append "0" e) e)))))

(def %sql-positive-text
  (fn (_ x form)
    (let ((rp (%sql-float-digits x form)))
      (let ((digits (Str8 str (first rp))))
        (let ((k (- (+ (Str8 length digits) (rest rp)) 1)))
          (if (and (>= k %sql-fixed-least) (<= k %sql-fixed-most))
            (%sql-fixed digits (rest rp) k)
            (%sql-scientific digits k)))))))

(def %sql-zero (Float from 0))

; A float of FORM as DuckDB shows it
(def %sql-float-shown
  (fn (_ x form)
    (match
      ((Float nan? x) "nan")
      ((Float inf? x) (if (< x %sql-zero) "-inf" "inf"))
      ((= x %sql-zero) "0.0")
      ((< x %sql-zero) (Str8 append "-" (%sql-positive-text (- %sql-zero x) form)))
      (#t (%sql-positive-text x form)))))

(def sql-double-text (fn (_ x) (%sql-float-shown x %sql-double-form)))

; A REAL is held as the double it is equal to, and shown in the fewest
; digits that read back as it among REALs
(def sql-real-text (fn (_ x) (%sql-float-shown x %sql-real-form)))

; --- a REAL ------------------------------------------------------------------

; The bits of a REAL's mantissa
(def %sql-real-bits 24)

; The power of two no REAL reaches
(def %sql-real-limit 128)

; A positive finite double as the REAL nearest it, a tie going to the even
; mantissa.  One too great for a REAL is an infinity.  A REAL below the
; least normal one keeps more bits than it has.
(def %sql-real-positive
  (fn (_ x)
    (let ((split (%sql-split x)))
      (let ((shift (- (%sql-bits (first split) 0) %sql-real-bits)))
        (let ((r (if (<= shift 0) x
                   (let ((unit (%sql-pow2 shift)))
                     (let ((q (Num quotient (first split) unit))
                           (twice (* 2 (Num remainder (first split) unit))))
                       (%sql-scale2
                         (Float from
                           (if (or (> twice unit) (and (= twice unit) (= (Num remainder q 2) 1)))
                             (+ q 1) q))
                         (+ (rest split) shift)))))))
          (if (< r (%sql-scale2 (Float from 1) %sql-real-limit)) r
            (/ (Float from 1) %sql-zero)))))))

; A double as the REAL nearest it
(def sql-real-of
  (fn (_ x)
    (match
      ((or (Float nan? x) (Float inf? x) (= x %sql-zero)) x)
      ((< x %sql-zero) (- %sql-zero (%sql-real-positive (- %sql-zero x))))
      (#t (%sql-real-positive x)))))

; --- a double as other numbers -----------------------------------------------

; A number as the platform's float reader takes one: digits on both sides
; of a point, and then an exponent.  A whole number is left as it is, for
; the platform to read as an integer; a number written with an exponent
; and no point, with nothing before its point or with nothing after it is
; given what it lacks.  A plus before it goes.
(def %sql-float-text
  (fn (_ text)
    (let ((body (if (Str8 starts? "+" text) (Str8 sub 1 (Str8 length text) text) text)))
      (let ((at (if (null? (Str8 index-of "e" body)) (Str8 index-of "E" body)
                  (Str8 index-of "e" body))))
        (let ((mantissa (if (null? at) body (Str8 sub 0 at body)))
              (exponent (if (null? at) ""
                          (Str8 append "e" (Str8 sub (+ at 1) (Str8 length body) body)))))
          (let ((negative (Str8 starts? "-" mantissa)))
            (let ((digits (if negative (Str8 sub 1 (Str8 length mantissa) mantissa) mantissa)))
              (let ((point (Str8 index-of "." digits)))
                (if (and (null? point) (null? at)) body
                  (Str8 append
                    (if negative "-" "")
                    (match
                      ((null? point) (Str8 append digits ".0"))
                      ((= point 0) (Str8 append "0" digits))
                      (#t digits))
                    (if (and (not (null? point)) (= point (- (Str8 length digits) 1))) "0" "")
                    exponent))))))))))

; The double nearest an integer or a number written out in TEXT.  The
; platform's reader does the rounding.
(def sql-double-of (fn (_ text) (Float from (%sql-float-text text))))

; A finite double times 10^SCALE as an integer, a half rounded away from
; zero
(def sql-double-scaled
  (fn (_ x scale)
    (if (= x %sql-zero) 0
      (let ((split (%sql-split (if (< x %sql-zero) (- %sql-zero x) x))))
        (let ((a (* (first split) (sql-pow10 scale) (%sql-pow2 (rest split))))
              (b (%sql-pow2 (- 0 (rest split)))))
          (let ((r (Num quotient (+ (* 2 a) b) (* 2 b))))
            (if (< x %sql-zero) (- 0 r) r)))))))

; A finite double as the integer nearest it, a half going to the even one
(def sql-double-integer
  (fn (_ x) (sql-double-scaled (Float rint x) 0)))

(def sql-double-finite?
  (fn (_ x) (not (or (Float nan? x) (Float inf? x)))))

; --- decimals ----------------------------------------------------------------

; The digits of TEXT as an integer
(def %sql-digits
  (fn (self text i n acc)
    (if (>= i n) acc
      (self text (+ i 1) n
            (+ (* acc 10) (- (Char ->int (Str8 ref i text)) 48))))))

; A number written with digits and at most one point as
; (SCALED WIDTH SCALE): SCALED the digits as one integer, WIDTH how many
; there are, SCALE how many after the point
(def sql-decimal-read
  (fn (_ text)
    (let ((at (Str8 index-of "." text)))
      (let ((digits (if (null? at) text
                      (Str8 append (Str8 sub 0 at text)
                                   (Str8 sub (+ at 1) (Str8 length text) text)))))
        (list (%sql-digits digits 0 (Str8 length digits) 0)
              (Str8 length digits)
              (if (null? at) 0 (- (- (Str8 length text) at) 1)))))))

; SCALED at FROM digits after the point as it is at TO, a half rounded away
; from zero when digits go
(def sql-rescale
  (fn (_ scaled from to)
    (if (>= to from) (* scaled (sql-pow10 (- to from)))
      (let ((b (sql-pow10 (- from to))) (a (if (< scaled 0) (- 0 scaled) scaled)))
        (let ((r (Num quotient (+ (* 2 a) b) (* 2 b))))
          (if (< scaled 0) (- 0 r) r))))))

; A decimal as DuckDB shows it: every digit of its scale, and no 0 before
; the point when the width leaves no room for one
(def sql-decimal-text
  (fn (_ scaled width scale)
    (let ((a (if (< scaled 0) (- 0 scaled) scaled)) (unit (sql-pow10 scale)))
      (let ((whole (Str8 str (Num quotient a unit)))
            (part (Str8 str (Num remainder a unit))))
        (Str8 append
          (if (< scaled 0) "-" "")
          (if (and (= width scale) (> scale 0)) "" whole)
          (if (= scale 0) ""
            (Str8 append "." (%sql-zeros (- scale (Str8 length part))) part)))))))

(provide sql/number
  sql-pow10 sql-double-digits sql-double-text sql-double-of sql-real-text
  sql-real-of
  sql-double-scaled sql-double-integer sql-double-finite?
  sql-decimal-read sql-rescale sql-decimal-text)

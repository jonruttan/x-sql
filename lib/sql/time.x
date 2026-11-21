; # x-sql -- SQL on x-lang
;
; ## lib/sql/time.x -- dates, times and intervals
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A DATE is days since 1970-01-01, a TIMESTAMP microseconds since its
; midnight, a TIME microseconds since midnight, and an INTERVAL three
; counts kept apart, (MONTHS DAYS MICROSECONDS), since a month is no fixed
; number of days nor a day, where clocks change, of hours.  All are
; integers; there is no time zone.
;
; The calendar is the platform's (x/sys/date): proleptic Gregorian.  Text
; is read with the bundle's own lexer, so a date is three numbers with
; minus signs between them and a time two or three with colons.

(module sql/time)
(import x/type/list)
(import x/type/str)
(import x/type/assoc)
(import x/num/tower)
(import x/sys/date)
(import sql/words sql-lower)
(import sql/lex sql-lex)
(import sql/number sql-pow10 sql-decimal-read)

; --- counts ------------------------------------------------------------------

(def sql-micros-second 1000000)
(def sql-micros-minute (* 60 sql-micros-second))
(def sql-micros-hour (* 60 sql-micros-minute))
(def sql-micros-day (* 24 sql-micros-hour))
(def %sql-seconds-day 86400)

; N over D, rounded toward the least: a quotient that is right for a time
; before 1970
(def sql-floor-div
  (fn (_ n d)
    (let ((q (Num quotient n d)))
      (if (and (< n 0) (not (= (* q d) n))) (- q 1) q))))

(def sql-floor-mod (fn (_ n d) (- n (* (sql-floor-div n d) d))))

; --- the calendar ------------------------------------------------------------

; A day as (YEAR MONTH DAY WEEKDAY), the weekday 0 for Sunday
(def sql-civil
  (fn (_ days)
    (let ((fields (Date from-unix (* days %sql-seconds-day))))
      (list (Assoc get (lit year) fields) (Assoc get (lit month) fields)
            (Assoc get (lit day) fields) (Assoc get (lit wday) fields)))))

(def %sql-month-lengths (list 31 28 31 30 31 30 31 31 30 31 30 31))

(def sql-month-days
  (fn (_ year month)
    (if (and (= month 2) (Date leap-year? year)) 29
      (List ref (- month 1) %sql-month-lengths))))

; The day a year, a month and a day name, or nil when there is no such day
(def sql-days
  (fn (_ year month day)
    (if (and (>= month 1) (<= month 12) (>= day 1) (<= day (sql-month-days year month)))
      (Num quotient
        (Date to-unix (list (pair (lit year) year) (pair (lit month) month)
                            (pair (lit day) day) (pair (lit hour) 0)
                            (pair (lit minute) 0) (pair (lit second) 0)))
        %sql-seconds-day)
      ())))

; The day MONTHS months after a day, the day of the month kept, or the
; month's last when it has no such day
(def sql-add-months
  (fn (_ days months)
    (let ((civil (sql-civil days)))
      (let ((index (+ (* (first civil) 12) (- (List second civil) 1) months)))
        (let ((year (sql-floor-div index 12)) (month (+ (sql-floor-mod index 12) 1)))
          (sql-days year month
                    (let ((last (sql-month-days year month)))
                      (if (> (List third civil) last) last (List third civil)))))))))

; --- text out ----------------------------------------------------------------

(def %sql-padded
  (fn (_ n width) (Str8 pad-left width #\0 (Str8 str n))))

(def sql-date-text
  (fn (_ days)
    (let ((civil (sql-civil days)))
      (Str8 append (%sql-padded (first civil) 4) "-" (%sql-padded (List second civil) 2)
                   "-" (%sql-padded (List third civil) 2)))))

; A fraction of a second as its digits, with no zeros at the end; nothing
; for none
(def %sql-fraction
  (fn (_ micros)
    (if (= micros 0) ""
      (Str8 append "."
        ((fn (self digits)
           (if (Str8 ends? "0" digits) (self (Str8 sub 0 (- (Str8 length digits) 1) digits))
             digits))
         (%sql-padded micros 6))))))

; Microseconds as HH:MM:SS and a fraction.  The hours are not held to a
; day, for an interval's sake.
(def sql-clock-text
  (fn (_ micros)
    (let ((seconds (Num quotient micros sql-micros-second)))
      (Str8 append (%sql-padded (Num quotient seconds 3600) 2) ":"
                   (%sql-padded (Num remainder (Num quotient seconds 60) 60) 2) ":"
                   (%sql-padded (Num remainder seconds 60) 2)
                   (%sql-fraction (Num remainder micros sql-micros-second))))))

(def sql-timestamp-text
  (fn (_ micros)
    (Str8 append (sql-date-text (sql-floor-div micros sql-micros-day)) " "
                 (sql-clock-text (sql-floor-mod micros sql-micros-day)))))

(def %sql-counted
  (fn (_ n word)
    (if (= n 0) ()
      (list (Str8 str n " " word (if (or (= n 1) (= n -1)) "" "s"))))))

; An interval as DuckDB shows one: years and months, days, then the time
; when there is any or nothing else
(def sql-interval-text
  (fn (_ interval)
    (let ((months (first interval)) (days (List second interval))
          (micros (List third interval)))
      (let ((parts (List append
                     (%sql-counted (Num quotient months 12) "year")
                     (%sql-counted (Num remainder months 12) "month")
                     (%sql-counted days "day"))))
        (Str8 join " "
          (if (or (not (= micros 0)) (null? parts))
            (List append parts
              (list (if (< micros 0) (Str8 append "-" (sql-clock-text (- 0 micros)))
                      (sql-clock-text micros))))
            parts))))))

; --- text in -----------------------------------------------------------------

; TEXT's tokens with the blanks gone
(def %sql-tokens
  (fn (_ text)
    (List reject (fn (_ tok) (eq? (first tok) (lit blank))) (sql-lex (Str8 trim text)))))

(def %sql-number?
  (fn (_ tok) (and (eq? (first tok) (lit num)) (< (List third tok) 3))))

(def %sql-whole?
  (fn (_ tok) (and (eq? (first tok) (lit num)) (= (List third tok) 1))))

(def %sql-mark?
  (fn (_ tok mark) (and (eq? (first tok) (lit op)) (str=? (List second tok) mark))))

(def %sql-int (fn (_ tok) (first (sql-decimal-read (List second tok)))))

; A date at the start of TOKENS, number - number - number: (DAYS . REST),
; DAYS nil for a day there is not; nil when the tokens are no date
(def %sql-date-tokens
  (fn (_ tokens)
    (if (and (>= (List length tokens) 5)
             (%sql-whole? (first tokens)) (%sql-mark? (List second tokens) "-")
             (%sql-whole? (List third tokens)) (%sql-mark? (List ref 3 tokens) "-")
             (%sql-whole? (List ref 4 tokens)))
      (pair (sql-days (%sql-int (first tokens)) (%sql-int (List third tokens))
                      (%sql-int (List ref 4 tokens)))
            (List drop 5 tokens))
      ())))

; Seconds written with or without a fraction, as microseconds
(def %sql-seconds
  (fn (_ tok)
    (let ((read (sql-decimal-read (List second tok))))
      (if (> (List third read) 6)
        (Num quotient (first read) (sql-pow10 (- (List third read) 6)))
        (* (first read) (sql-pow10 (- 6 (List third read))))))))

; A time of day at the start of TOKENS, number : number and maybe
; : number: (MICROS HOURS . REST), nil when the tokens are no time
(def %sql-clock-tokens
  (fn (_ tokens)
    (if (and (>= (List length tokens) 3)
             (%sql-whole? (first tokens)) (%sql-mark? (List second tokens) ":")
             (%sql-whole? (List third tokens)))
      (let ((base (+ (* (%sql-int (first tokens)) sql-micros-hour)
                     (* (%sql-int (List third tokens)) sql-micros-minute)))
            (after (List drop 3 tokens)))
        (if (and (>= (List length after) 2) (%sql-mark? (first after) ":")
                 (%sql-number? (List second after)))
          (pair (+ base (%sql-seconds (List second after)))
                (pair (%sql-int (first tokens)) (List drop 2 after)))
          (pair base (pair (%sql-int (first tokens)) after))))
      ())))

; Whether a time read from tokens is one of a day: minutes and seconds
; under 60 are what its sum cannot show, so the sum is held under a day
; and the hours under 24
(def %sql-clock-of-day?
  (fn (_ clock)
    (and (< (first clock) sql-micros-day) (< (List second clock) 24))))

; The day TEXT names, nil when it is no date, and the name out-of-range
; when it is one there is not
(def sql-date-read
  (fn (_ text)
    (let ((date (%sql-date-tokens (%sql-tokens text))))
      (match
        ((or (null? date) (not (null? (rest date)))) ())
        ((null? (first date)) (lit out-of-range))
        (#t (first date))))))

; The time of day TEXT names, as microseconds, or nil, or out-of-range
(def sql-clock-read
  (fn (_ text)
    (let ((clock (%sql-clock-tokens (%sql-tokens text))))
      (match
        ((or (null? clock) (not (null? (rest (rest clock))))) ())
        ((not (%sql-clock-of-day? clock)) (lit out-of-range))
        (#t (first clock))))))

; The moment TEXT names, a date and maybe a time, as microseconds, or nil,
; or out-of-range
(def sql-timestamp-read
  (fn (_ text)
    (let ((date (%sql-date-tokens (%sql-tokens text))))
      (match
        ((null? date) ())
        ((null? (first date)) (lit out-of-range))
        ((null? (rest date)) (* (first date) sql-micros-day))
        (#t
          (let ((clock (%sql-clock-tokens (rest date))))
            (match
              ((or (null? clock) (not (null? (rest (rest clock))))) ())
              ((not (%sql-clock-of-day? clock)) (lit out-of-range))
              (#t (+ (* (first date) sql-micros-day) (first clock))))))))))

; A unit of an interval, which of the three counts it is of, and how many
; of that count it is.  A unit is named in the singular or the plural.
(def sql-interval-units
  (list (list "year" 0 12) (list "month" 0 1)
        (list "week" 1 7) (list "day" 1 1)
        (list "hour" 2 sql-micros-hour) (list "minute" 2 sql-micros-minute)
        (list "second" 2 sql-micros-second) (list "millisecond" 2 1000)
        (list "microsecond" 2 1)))

(def %sql-unit
  (fn (_ word)
    (let ((lower (sql-lower word)))
      (let ((row (List find
                   (fn (_ r) (or (str=? (first r) lower) (str=? (Str8 append (first r) "s") lower)))
                   sql-interval-units)))
        (when (null? row)
          (error (Str8 append "Conversion Error: extract specifier \"" word "\" not recognized")))
        row))))

; N of the unit WORD names, as an interval
(def sql-interval-of
  (fn (_ n word)
    (let ((row (%sql-unit word)))
      (List map (fn (_ i) (if (= i (List second row)) (* n (List third row)) 0))
                (list 0 1 2)))))

(def sql-interval-add
  (fn (_ a b) (List map (fn (_ x y) (+ x y)) a b)))

(def sql-interval-times
  (fn (_ a n) (List map (fn (_ x) (* x n)) a)))

; The interval TEXT names: counts each with its unit, a minus before any,
; and a time; nil when it is none
(def sql-interval-read
  (fn (_ text)
    ((fn (self tokens sum seen)
       (match
         ((null? tokens) (if seen sum ()))
         ((and (%sql-mark? (first tokens) "-") (not (null? (rest tokens)))
               (not (null? (rest (rest tokens))))
               (%sql-whole? (List second tokens)) (eq? (first (List third tokens)) (lit id)))
           (self (List drop 3 tokens)
                 (sql-interval-add sum
                   (sql-interval-of (- 0 (%sql-int (List second tokens)))
                                    (List second (List third tokens))))
                 #t))
         ((and (not (null? (rest tokens))) (%sql-whole? (first tokens))
               (eq? (first (List second tokens)) (lit id)))
           (self (List drop 2 tokens)
                 (sql-interval-add sum
                   (sql-interval-of (%sql-int (first tokens)) (List second (List second tokens))))
                 #t))
         (#t
           (let ((clock (%sql-clock-tokens tokens)))
             (if (null? clock) ()
               (self (rest (rest clock))
                     (sql-interval-add sum (list 0 0 (first clock)))
                     #t))))))
     (%sql-tokens text) (list 0 0 0) #f)))

; --- arithmetic --------------------------------------------------------------

; The moment an interval after a moment: the months first, on the
; calendar, then the days and the time
(def sql-timestamp-plus
  (fn (_ micros interval)
    (let ((days (sql-floor-div micros sql-micros-day))
          (clock (sql-floor-mod micros sql-micros-day)))
      (+ (* (+ (sql-add-months days (first interval)) (List second interval)) sql-micros-day)
         clock (List third interval)))))

(def sql-interval-negated
  (fn (_ interval) (sql-interval-times interval -1)))

; The time between two moments as an interval: whole days, and the rest
(def sql-micros-interval
  (fn (_ micros)
    (list 0 (Num quotient micros sql-micros-day) (Num remainder micros sql-micros-day))))

; An interval as microseconds, for comparing: a month is thirty days, as
; DuckDB takes it
(def sql-interval-micros
  (fn (_ interval)
    (+ (* (+ (* (first interval) 30) (List second interval)) sql-micros-day)
       (List third interval))))

; --- parts, and whole units --------------------------------------------------

(def sql-day-names
  (list "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"))
(def sql-month-names
  (list "January" "February" "March" "April" "May" "June" "July" "August"
        "September" "October" "November" "December"))

; The day of the year, from 1
(def sql-day-of-year
  (fn (_ days) (+ (- days (sql-days (first (sql-civil days)) 1 1)) 1)))

; A unit moments are counted in whole: its name, whether it is counted in
; months or in microseconds, and how many of those it is
(def %sql-whole-units
  (list (list "year" (lit months) 12) (list "quarter" (lit months) 3)
        (list "month" (lit months) 1)
        (list "day" (lit micros) sql-micros-day)
        (list "hour" (lit micros) sql-micros-hour)
        (list "minute" (lit micros) sql-micros-minute)
        (list "second" (lit micros) sql-micros-second)))

(def %sql-whole-unit
  (fn (_ word)
    (let ((lower (sql-lower word)))
      (let ((row (List find
                   (fn (_ r) (or (str=? (first r) lower) (str=? (Str8 append (first r) "s") lower)))
                   %sql-whole-units)))
        (when (null? row)
          (error (Str8 append "Conversion Error: extract specifier \"" word "\" not recognized")))
        row))))

; Which of its unit's whole ones a moment is in: the years, quarters or
; months since year 0, or the days, hours, minutes or seconds since 1970
(def %sql-unit-index
  (fn (_ unit micros)
    (if (eq? (List second unit) (lit months))
      (let ((civil (sql-civil (sql-floor-div micros sql-micros-day))))
        (sql-floor-div (+ (* (first civil) 12) (- (List second civil) 1)) (List third unit)))
      (sql-floor-div micros (List third unit)))))

; How many of the unit WORD names begin between two moments
(def sql-moment-diff
  (fn (_ word from to)
    (let ((unit (%sql-whole-unit word)))
      (- (%sql-unit-index unit to) (%sql-unit-index unit from)))))

; The moment its unit's whole one begins that a moment is in
(def sql-moment-trunc
  (fn (_ word micros)
    (let ((unit (%sql-whole-unit word)))
      (let ((index (%sql-unit-index unit micros)))
        (if (eq? (List second unit) (lit months))
          (let ((months (* index (List third unit))))
            (* (sql-days (sql-floor-div months 12) (+ (sql-floor-mod months 12) 1) 1)
               sql-micros-day))
          (* index (List third unit)))))))

(provide sql/time
  sql-micros-second sql-micros-minute sql-micros-hour sql-micros-day
  sql-floor-div sql-floor-mod sql-civil sql-days sql-month-days sql-add-months
  sql-date-text sql-clock-text sql-timestamp-text sql-interval-text
  sql-date-read sql-clock-read sql-timestamp-read sql-interval-read
  sql-interval-units sql-interval-of sql-interval-add sql-interval-times
  sql-interval-negated sql-timestamp-plus sql-micros-interval
  sql-interval-micros sql-day-names sql-month-names sql-day-of-year
  sql-moment-diff sql-moment-trunc)

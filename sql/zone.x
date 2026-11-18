; # x-sql -- SQL on x-lang
;
; ## sql/zone.x -- time zones
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A zone is read from the system's zone database, a file a zone under
; /usr/share/zoneinfo in the TZif format of RFC 8536: the moments its
; offset from UTC changed, and after them a rule in the form of POSIX's TZ
; that says how it changes each year from then on.
;
; A zone is (NAME CHANGES FIRST RULE).  CHANGES is a list of
; (SECONDS . OFFSET), the unix second a change came and the offset from
; then, in seconds east of UTC, the latest first.  FIRST is the offset
; before any of them.  RULE is nil, or (STANDARD) for an offset that does
; not change, or (STANDARD DAYLIGHT START END) with START and END each
; (MONTH WEEK WEEKDAY SECONDS): the week of the month, 5 for its last,
; the weekday 0 for Sunday, and the seconds into the day on the clock in
; force before the change.
;
; The session has one zone, the system's until SET TimeZone names another.

(module sql/zone)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/type/assoc)
(import x/num/tower)
(import x/codec/bytes)
(import x/sys/file)
(import sql/time sql-floor-div sql-floor-mod sql-civil sql-days sql-month-days)

(def %zone-directory "/usr/share/zoneinfo/")

(def %zone-seconds-day 86400)
(def %zone-seconds-hour 3600)

; --- a zone's file -----------------------------------------------------------

; The big-endian integer of N bytes of REGION from AT, unsigned
(def %zone-unsigned
  (fn (_ region at n)
    ((fn (self i acc)
       (if (>= i n) acc
         (self (+ i 1) (+ (* acc 256) (Bytes ref region (+ at i))))))
     0 0)))

; The same, read as two's complement
(def %zone-signed
  (fn (_ region at n)
    (let ((u (%zone-unsigned region at n))
          (half ((fn (self i acc) (if (>= i n) acc (self (+ i 1) (* acc 256)))) 1 128)))
      (if (>= u half) (- u (* 2 half)) u))))

; A file's bytes, as a region
(def %zone-file-bytes
  (fn (_ path)
    (let ((size (Assoc get (lit size) (File stat path))))
      (let ((region (Bytes of-list (List repeat size 0)))
            (fd (File open path (lit rdonly))))
        (let ((n (File read fd (first region) size)))
          (File close fd)
          (if (= n size) region ()))))))

; A TZif header is 44 bytes: the magic, a version, and after 15 unused
; bytes six counts of four bytes each.
(def %zone-header 44)
(def %zone-counts 20)
(def %zone-magic (Bytes of-list (list 84 90 105 102)))

; The count at the place I of the six in the header at BASE: 0 and 1 the
; indicators, 2 the leap seconds, 3 the changes, 4 the kinds of time, and
; 5 the bytes of their names
(def %zone-count
  (fn (_ region base i) (%zone-unsigned region (+ base %zone-counts (* i 4)) 4)))

; How many bytes the data after the header at BASE takes, its times of
; WIDTH bytes
(def %zone-data-size
  (fn (_ region base width)
    (+ (* (%zone-count region base 3) (+ width 1))
       (* (%zone-count region base 4) 6)
       (%zone-count region base 5)
       (* (%zone-count region base 2) (+ width 4))
       (%zone-count region base 1)
       (%zone-count region base 0))))

; The changes and the first offset in the block whose header is at BASE:
; (CHANGES . FIRST)
(def %zone-block
  (fn (_ region base width)
    (let ((times (%zone-count region base 3)) (kinds (%zone-count region base 4))
          (data (+ base %zone-header)))
      (let ((kinds-at (+ data (* times (+ width 1)))))
        (let ((offsets (List map (fn (_ j) (%zone-signed region (+ kinds-at (* j 6)) 4))
                                 (List range 0 kinds))))
          (pair
            (List fold
              (fn (_ changes i)
                (pair (pair (%zone-signed region (+ data (* i width)) width)
                            (List ref (Bytes ref region (+ data (* times width) i)) offsets))
                      changes))
              () (List range 0 times))
            (if (null? offsets) 0 (first offsets))))))))

(def %zone-newline (Bytes of-list (list 10)))

; The text between the two newlines that follow the data whose end is AT,
; or nil
(def %zone-footer
  (fn (_ region at)
    (if (>= (+ at 1) (Bytes length region)) ()
      (let ((after (Bytes sub region (+ at 1) (- (Bytes length region) at 1))))
        (let ((n (Bytes find after %zone-newline)))
          (if (null? n) () (first (Bytes copy (Bytes sub after 0 n)))))))))

; A zone's CHANGES, FIRST and RULE from a file's bytes, or nil when they
; are not a zone's.  A file of version 2 or later has its times twice, of
; four bytes and then of eight; the second is read.
(def %zone-read
  (fn (_ region)
    (if (or (< (Bytes length region) %zone-header)
            (not (Bytes same? (Bytes sub region 0 4) %zone-magic)))
      ()
      (if (= (Bytes ref region 4) 0)
        (let ((block (%zone-block region 0 4)))
          (list (first block) (rest block) ()))
        (let ((base (+ %zone-header (%zone-data-size region 0 4))))
          (let ((block (%zone-block region base 8))
                (footer (%zone-footer region (+ base %zone-header (%zone-data-size region base 8)))))
            (list (first block) (rest block)
                  (if (or (null? footer) (str=? footer "")) () (%zone-rule footer)))))))))

; --- a rule ------------------------------------------------------------------

(def %zone-code (fn (_ text i) (Char ->int (Str8 ref i text))))

(def %zone-digit?
  (fn (_ text i)
    (and (< i (Str8 length text)) (>= (%zone-code text i) 48) (<= (%zone-code text i) 57))))

(def %zone-at?
  (fn (_ text i c) (and (< i (Str8 length text)) (= (%zone-code text i) c))))

; The number at I: (N . NEXT)
(def %zone-number
  (fn (_ text i)
    ((fn (self i n)
       (if (%zone-digit? text i) (self (+ i 1) (+ (* n 10) (- (%zone-code text i) 48)))
         (pair n i)))
     i 0)))

(def %zone-colon 58)

; Hours, and minutes and seconds after colons, at I, with a sign before
; them or none, as seconds: (SECONDS . NEXT)
(def %zone-clock
  (fn (_ text i)
    (let ((negative (%zone-at? text i 45)))
      (let ((h (%zone-number text (if (or negative (%zone-at? text i 43)) (+ i 1) i))))
        (let ((m (if (%zone-at? text (rest h) %zone-colon) (%zone-number text (+ (rest h) 1))
                   (pair 0 (rest h)))))
          (let ((s (if (%zone-at? text (rest m) %zone-colon) (%zone-number text (+ (rest m) 1))
                     (pair 0 (rest m)))))
            (let ((total (+ (* (first h) %zone-seconds-hour) (* (first m) 60) (first s))))
              (pair (if negative (- 0 total) total) (rest s)))))))))

; Where a zone's abbreviation at I ends: letters, or anything between
; angle brackets
(def %zone-name-end
  (fn (_ text i)
    (if (%zone-at? text i 60)
      ((fn (self j) (if (or (>= j (Str8 length text)) (%zone-at? text j 62)) (+ j 1) (self (+ j 1))))
       i)
      ((fn (self j)
         (if (and (< j (Str8 length text))
                  (let ((c (%zone-code text j))) (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)))))
           (self (+ j 1))
           j))
       i))))

; The clock's time a change comes at when the rule gives none: 02:00
(def %zone-change-default (* 2 %zone-seconds-hour))

; One end of the daylight time at I, Mmonth.week.weekday and a time after
; a slash: ((MONTH WEEK WEEKDAY SECONDS) . NEXT), or nil for a form that is
; not read
(def %zone-rule-end
  (fn (_ text i)
    (if (not (%zone-at? text i 77)) ()
      (let ((month (%zone-number text (+ i 1))))
        (let ((week (%zone-number text (+ (rest month) 1))))
          (let ((weekday (%zone-number text (+ (rest week) 1))))
            (let ((at (if (%zone-at? text (rest weekday) 47) (%zone-clock text (+ (rest weekday) 1))
                        (pair %zone-change-default (rest weekday)))))
              (pair (list (first month) (first week) (first weekday) (first at)) (rest at)))))))))

; A rule from its text, as EST5EDT,M3.2.0,M11.1.0.  An offset in it is
; hours west of UTC.  Daylight time is an hour on unless it says.  Ends
; in a form other than M are not read, and the zone then has standard
; time alone.
(def %zone-rule
  (fn (_ text)
    (let ((std (%zone-clock text (%zone-name-end text 0))))
      (let ((standard (- 0 (first std))) (dst-name (%zone-name-end text (rest std))))
        (if (= dst-name (rest std)) (list standard)
          (let ((dst (if (or (%zone-at? text dst-name 44) (>= dst-name (Str8 length text)))
                       (pair (- 0 (+ standard %zone-seconds-hour)) dst-name)
                       (%zone-clock text dst-name))))
            (let ((start (if (%zone-at? text (rest dst) 44) (%zone-rule-end text (+ (rest dst) 1)) ())))
              (let ((end (if (and (not (null? start)) (%zone-at? text (rest start) 44))
                           (%zone-rule-end text (+ (rest start) 1))
                           ())))
                (if (or (null? start) (null? end)) (list standard)
                  (list standard (- 0 (first dst)) (first start) (first end)))))))))))

; The second on the clock that END falls at in YEAR, counted as if the
; clock were UTC
(def %zone-rule-moment
  (fn (_ end year)
    (let ((month (first end)) (week (List second end)) (weekday (List third end)))
      (let ((first-day (sql-days year month 1)))
        (let ((day (+ first-day
                      (sql-floor-mod (- weekday (List ref 3 (sql-civil first-day))) 7)
                      (* (- week 1) 7))))
          (+ (* (if (>= day (+ first-day (sql-month-days year month))) (- day 7) day)
                %zone-seconds-day)
             (List ref 3 end)))))))

; The offset RULE gives at the unix second SECS
(def %zone-rule-offset
  (fn (_ rule secs)
    (if (null? (rest rule)) (first rule)
      (let ((standard (first rule)) (daylight (List second rule)))
        (let ((year (first (sql-civil (sql-floor-div (+ secs standard) %zone-seconds-day)))))
          (let ((start (- (%zone-rule-moment (List third rule) year) standard))
                (end (- (%zone-rule-moment (List ref 3 rule) year) daylight)))
            (if (if (< start end) (and (>= secs start) (< secs end))
                  (or (>= secs start) (< secs end)))
              daylight standard)))))))

; --- a zone ------------------------------------------------------------------

(def %zone-utc (list "UTC" () 0 (list 0)))

; A name that may be a file's under the directory: no dot in it, so no way
; out of the directory, and not a path from the root
(def %zone-name?
  (fn (_ name)
    (not (or (str=? name "") (Str8 includes? "." name) (Str8 starts? "/" name)))))

(def %zone-loaded (Dict make))

; The zone of a name, or nil when the system has none of it
(def %zone-load
  (fn (_ name)
    (let ((path (Str8 append %zone-directory name)))
      (if (not (and (%zone-name? name) (eq? (File type path) (lit file)))) ()
        (let ((region (%zone-file-bytes path)))
          (let ((read (if (null? region) () (%zone-read region))))
            (if (null? read) () (pair name read))))))))

(def sql-zone-find
  (fn (_ name)
    (if (str=? (Str8 upcase name) "UTC") %zone-utc
      (do (unless (%zone-loaded has? name) (%zone-loaded set! name (%zone-load name)))
          (%zone-loaded get name)))))

; ZONE's offset at the unix second SECS, in seconds east of UTC: the
; rule's past the last change, else that of the latest change not after
; it, else the first
(def sql-zone-offset
  (fn (_ zone secs)
    (let ((changes (List second zone)) (rule (List ref 3 zone)))
      (if (and (not (null? rule)) (or (null? changes) (>= secs (first (first changes)))))
        (%zone-rule-offset rule secs)
        (let ((change (List find (fn (_ c) (<= (first c) secs)) changes)))
          (if (null? change) (List third zone) (rest change)))))))

; The unix second at which ZONE's clock shows LOCAL, a second counted as
; if the clock were UTC.  Where the clock shows a time twice, the second
; of the two; where it skips one, the time that much after the skip.
; That is how DuckDB reads them.
(def sql-zone-utc
  (fn (_ zone local)
    (let ((before (sql-zone-offset zone (- local %zone-seconds-day)))
          (after (sql-zone-offset zone (+ local %zone-seconds-day))))
      (if (= (sql-zone-offset zone (- local after)) after)
        (- local after)
        (- local before)))))

(def sql-zone-name (fn (_ zone) (first zone)))

; --- the session's zone ------------------------------------------------------

(def %zone-session (Dict make))

; The system's zone: the one TZ names, else the one /etc/localtime is a
; link to, else UTC
(def %zone-system
  (fn (_)
    (let ((tz (Sys getenv "TZ")))
      (let ((linked (guard (_ ()) (File readlink "/etc/localtime"))))
        (let ((at (if (null? linked) () (Str8 index-of "zoneinfo/" linked))))
          (let ((name (match
                        ((not (null? tz)) tz)
                        ((null? at) "UTC")
                        (#t (Str8 sub (+ at 9) (Str8 length linked) linked)))))
            (if (null? (sql-zone-find name)) %zone-utc (sql-zone-find name))))))))

(def sql-zone-session
  (fn (_)
    (unless (%zone-session has? (lit zone)) (%zone-session set! (lit zone) (%zone-system)))
    (%zone-session get (lit zone))))

; The session's zone made the one NAME names, or the system's again when
; NAME is nil; nil when there is no such zone
(def sql-zone-session!
  (fn (_ name)
    (if (null? name) (do (%zone-session del! (lit zone)) #t)
      (let ((zone (sql-zone-find name)))
        (if (null? zone) () (do (%zone-session set! (lit zone) zone) #t))))))

(provide sql/zone
  sql-zone-find sql-zone-offset sql-zone-utc sql-zone-name sql-zone-session
  sql-zone-session!)

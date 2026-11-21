; # x-sql -- SQL on x-lang
;
; ## lib/sql/zone.x -- the session's time zone
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A zone is the platform's Zone (x/sys/zone), read from the system's zone
; database.  This module keeps the zones it has read, so a name met again
; reads no file, and the session's zone: the system's until SET TimeZone
; names another.

(module sql/zone)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/sys/date)
(import x/sys/zone)

(def %zone-read (Dict make))

; The zone of a name, or nil when the system has none of it
(def sql-zone-find
  (fn (_ name)
    (unless (%zone-read has? name) (%zone-read set! name (Zone named name)))
    (%zone-read get name)))

; ZONE's offset at the unix second SECS, in seconds east of UTC
(def sql-zone-offset (fn (_ zone secs) (zone offset secs)))

; The unix second at which ZONE's clock shows LOCAL, a second counted as
; if the clock were UTC
(def sql-zone-utc (fn (_ zone local) (zone local->unix (Date from-unix local))))

(def sql-zone-name (fn (_ zone) (zone name)))

; --- the session's zone ------------------------------------------------------

(def %zone-session (Dict make))

(def sql-zone-session
  (fn (_)
    (unless (%zone-session has? (lit zone)) (%zone-session set! (lit zone) (Zone system)))
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

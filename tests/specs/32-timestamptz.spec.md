TIMESTAMP WITH TIME ZONE: a moment, and the session's time zone that shows
it.  Each case sets the zone it is read in.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## zoned text

### a TIMESTAMPTZ is a moment, shown on the session's clock with its offset

```x
(sql "SET TimeZone = 'UTC'; SELECT TIMESTAMPTZ '2026-01-15 12:00:00+00' a, TIMESTAMP WITH TIME ZONE '2026-01-15 12:00:00+00' b, typeof(TIMESTAMPTZ '2026-01-15 12:00:00+00'), '2026-01-15 12:00:00+00'::TIMESTAMPTZ c")
```
---
```output
┌──────────────────────────┬──────────────────────────┬───────────────────────────────────────────────────────┬──────────────────────────┐
│            a             │            b             │ typeof(CAST('2026-01-15 12:00:00+00' AS TIMESTAMPTZ)) │            c             │
│ timestamp with time zone │ timestamp with time zone │                        varchar                        │ timestamp with time zone │
├──────────────────────────┼──────────────────────────┼───────────────────────────────────────────────────────┼──────────────────────────┤
│ 2026-01-15 12:00:00+00   │ 2026-01-15 12:00:00+00   │ TIMESTAMP WITH TIME ZONE                              │ 2026-01-15 12:00:00+00   │
└──────────────────────────┴──────────────────────────┴───────────────────────────────────────────────────────┴──────────────────────────┘
```

### text may end in an offset, in Z, or in a zone's name

```x
(sql "SET TimeZone = 'UTC'; SELECT TIMESTAMPTZ '2026-01-15 12:00:00+02' a, TIMESTAMPTZ '2026-01-15 12:00:00-05:30' b, TIMESTAMPTZ '2026-01-15T12:00:00Z' c, TIMESTAMPTZ '2026-01-15 12:00:00.5 America/New_York' d, TIMESTAMPTZ '2026-07-15 12:00:00 Asia/Tokyo' e, TIMESTAMPTZ '1969-12-31 23:59:59-12:30' f")
```
---
```output
┌──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┐
│            a             │            b             │            c             │            d             │            e             │            f             │
│ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │
├──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ 2026-01-15 10:00:00+00   │ 2026-01-15 17:30:00+00   │ 2026-01-15 12:00:00+00   │ 2026-01-15 17:00:00.5+00 │ 2026-07-15 03:00:00+00   │ 1970-01-01 12:29:59+00   │
└──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┘
```

### with none it is on the session's clock, and a date alone is its midnight

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMPTZ '2026-01-15 12:00:00' a, TIMESTAMPTZ '2026-07-15 12:00:00' b, TIMESTAMPTZ '2026-01-15' c, TIMESTAMPTZ '2026-07-15 12:00:00.123456' d")
```
---
```output
┌──────────────────────────┬──────────────────────────┬──────────────────────────┬───────────────────────────────┐
│            a             │            b             │            c             │               d               │
│ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │   timestamp with time zone    │
├──────────────────────────┼──────────────────────────┼──────────────────────────┼───────────────────────────────┤
│ 2026-01-15 12:00:00-05   │ 2026-07-15 12:00:00-04   │ 2026-01-15 00:00:00-05   │ 2026-07-15 12:00:00.123456-04 │
└──────────────────────────┴──────────────────────────┴──────────────────────────┴───────────────────────────────┘
```

### the same moment on other clocks

```x
(sql "SET TimeZone = 'Asia/Kolkata'; SELECT TIMESTAMPTZ '2026-01-15 12:00:00+00'; SET TimeZone = 'Australia/Lord_Howe'; SELECT TIMESTAMPTZ '2026-01-15 12:00:00+00', TIMESTAMPTZ '2026-07-15 12:00:00+00'; SET TimeZone = 'America/St_Johns'; SELECT TIMESTAMPTZ '2026-01-15 12:00:00+00'; SET TimeZone = 'Europe/Paris'; SELECT TIMESTAMPTZ '2026-07-15 12:00:00+00', TIMESTAMPTZ '2026-12-15 12:00:00+00'")
```
---
```output
┌───────────────────────────────────────────────┐
│ CAST('2026-01-15 12:00:00+00' AS TIMESTAMPTZ) │
│           timestamp with time zone            │
├───────────────────────────────────────────────┤
│ 2026-01-15 17:30:00+05:30                     │
└───────────────────────────────────────────────┘
┌───────────────────────────────────────────────┬───────────────────────────────────────────────┐
│ CAST('2026-01-15 12:00:00+00' AS TIMESTAMPTZ) │ CAST('2026-07-15 12:00:00+00' AS TIMESTAMPTZ) │
│           timestamp with time zone            │           timestamp with time zone            │
├───────────────────────────────────────────────┼───────────────────────────────────────────────┤
│ 2026-01-15 23:00:00+11                        │ 2026-07-15 22:30:00+10:30                     │
└───────────────────────────────────────────────┴───────────────────────────────────────────────┘
┌───────────────────────────────────────────────┐
│ CAST('2026-01-15 12:00:00+00' AS TIMESTAMPTZ) │
│           timestamp with time zone            │
├───────────────────────────────────────────────┤
│ 2026-01-15 08:30:00-03:30                     │
└───────────────────────────────────────────────┘
┌───────────────────────────────────────────────┬───────────────────────────────────────────────┐
│ CAST('2026-07-15 12:00:00+00' AS TIMESTAMPTZ) │ CAST('2026-12-15 12:00:00+00' AS TIMESTAMPTZ) │
│           timestamp with time zone            │           timestamp with time zone            │
├───────────────────────────────────────────────┼───────────────────────────────────────────────┤
│ 2026-07-15 14:00:00+02                        │ 2026-12-15 13:00:00+01                        │
└───────────────────────────────────────────────┴───────────────────────────────────────────────┘
```

### a clock changes at its zone's moments, in years the zone's file has and in years after it

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMPTZ '2026-03-08 06:59:59+00' a, TIMESTAMPTZ '2026-03-08 07:00:00+00' b, TIMESTAMPTZ '2026-11-01 05:59:59+00' c, TIMESTAMPTZ '2026-11-01 06:00:00+00' d, TIMESTAMPTZ '1995-07-01 12:00:00+00' e, TIMESTAMPTZ '2090-07-01 12:00:00+00' f, TIMESTAMPTZ '2090-12-01 12:00:00+00' g")
```
---
```output
┌──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┐
│            a             │            b             │            c             │            d             │            e             │            f             │            g             │
│ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │
├──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ 2026-03-08 01:59:59-05   │ 2026-03-08 03:00:00-04   │ 2026-11-01 01:59:59-04   │ 2026-11-01 01:00:00-05   │ 1995-07-01 08:00:00-04   │ 2090-07-01 08:00:00-04   │ 2090-12-01 07:00:00-05   │
└──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┘
```

### a time the clock skips is the time that much after, and one it shows twice is the second

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMPTZ '2026-03-08 02:30:00' a, TIMESTAMPTZ '2026-11-01 01:30:00' b; SET TimeZone = 'Europe/Paris'; SELECT TIMESTAMPTZ '2026-03-29 02:30:00' a, TIMESTAMPTZ '2026-10-25 02:30:00' b")
```
---
```output
┌──────────────────────────┬──────────────────────────┐
│            a             │            b             │
│ timestamp with time zone │ timestamp with time zone │
├──────────────────────────┼──────────────────────────┤
│ 2026-03-08 03:30:00-04   │ 2026-11-01 01:30:00-05   │
└──────────────────────────┴──────────────────────────┘
┌──────────────────────────┬──────────────────────────┐
│            a             │            b             │
│ timestamp with time zone │ timestamp with time zone │
├──────────────────────────┼──────────────────────────┤
│ 2026-03-29 03:30:00+02   │ 2026-10-25 02:30:00+01   │
└──────────────────────────┴──────────────────────────┘
```

### before a zone kept standard time its offset was the sun's

```x
(sql "SET TimeZone = 'Asia/Kolkata'; SELECT TIMESTAMPTZ '1900-01-01 00:00:00+00'")
```
---
```output
┌───────────────────────────────────────────────┐
│ CAST('1900-01-01 00:00:00+00' AS TIMESTAMPTZ) │
│           timestamp with time zone            │
├───────────────────────────────────────────────┤
│ 1900-01-01 05:21:10+05:21                     │
└───────────────────────────────────────────────┘
```

## zoned settings

### SET TimeZone, in its several spellings, and current_setting

```x
(sql "SET TimeZone = 'Asia/Tokyo'; SELECT current_setting('TimeZone'); SET TIME ZONE 'UTC'; SELECT current_setting('timezone'); SET timezone TO 'Europe/Paris'; SELECT current_setting('TimeZone'), TIMESTAMPTZ '2026-07-15 12:00:00+00'")
```
---
```output
┌─────────────────────────────┐
│ current_setting('TimeZone') │
│           varchar           │
├─────────────────────────────┤
│ Asia/Tokyo                  │
└─────────────────────────────┘
┌─────────────────────────────┐
│ current_setting('timezone') │
│           varchar           │
├─────────────────────────────┤
│ UTC                         │
└─────────────────────────────┘
┌─────────────────────────────┬───────────────────────────────────────────────┐
│ current_setting('TimeZone') │ CAST('2026-07-15 12:00:00+00' AS TIMESTAMPTZ) │
│           varchar           │           timestamp with time zone            │
├─────────────────────────────┼───────────────────────────────────────────────┤
│ Europe/Paris                │ 2026-07-15 14:00:00+02                        │
└─────────────────────────────┴───────────────────────────────────────────────┘
```

## zoned casts

### a timestamp is the moment the session's clock shows it, and a moment the timestamp it shows

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMP '2026-07-15 12:00:00'::TIMESTAMPTZ a, DATE '2026-07-15'::TIMESTAMPTZ b, (TIMESTAMPTZ '2026-07-15 12:00:00+00')::TIMESTAMP c, (TIMESTAMPTZ '2026-07-15 03:00:00+00')::DATE d, (TIMESTAMPTZ '2026-07-15 12:00:00+00')::VARCHAR e, typeof((TIMESTAMPTZ '2026-07-15 12:00:00+00')::TIMESTAMP)")
```
---
```output
┌──────────────────────────┬──────────────────────────┬─────────────────────┬────────────┬────────────────────────┬──────────────────────────────────────────────────────────────────────────┐
│            a             │            b             │          c          │     d      │           e            │ typeof(CAST(CAST('2026-07-15 12:00:00+00' AS TIMESTAMPTZ) AS TIMESTAMP)) │
│ timestamp with time zone │ timestamp with time zone │      timestamp      │    date    │        varchar         │                                 varchar                                  │
├──────────────────────────┼──────────────────────────┼─────────────────────┼────────────┼────────────────────────┼──────────────────────────────────────────────────────────────────────────┤
│ 2026-07-15 12:00:00-04   │ 2026-07-15 00:00:00-04   │ 2026-07-15 08:00:00 │ 2026-07-14 │ 2026-07-15 08:00:00-04 │ TIMESTAMP                                                                │
└──────────────────────────┴──────────────────────────┴─────────────────────┴────────────┴────────────────────────┴──────────────────────────────────────────────────────────────────────────┘
```

### AT TIME ZONE reads a timestamp on a zone's clock, and shows a moment on one

```x
(sql "SET TimeZone = 'UTC'; SELECT TIMESTAMP '2026-07-15 12:00:00' AT TIME ZONE 'America/New_York' a, TIMESTAMPTZ '2026-07-15 12:00:00+00' AT TIME ZONE 'America/New_York' b, typeof(TIMESTAMP '2026-07-15 12:00:00' AT TIME ZONE 'UTC'), typeof(TIMESTAMPTZ '2026-07-15 12:00:00+00' AT TIME ZONE 'UTC'), timezone('Asia/Tokyo', TIMESTAMP '2026-07-15 12:00:00') c")
```
---
```output
┌──────────────────────────┬─────────────────────┬───────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────┬──────────────────────────┐
│            a             │          b          │ typeof(timezone('UTC', CAST('2026-07-15 12:00:00' AS TIMESTAMP))) │ typeof(timezone('UTC', CAST('2026-07-15 12:00:00+00' AS TIMESTAMPTZ))) │            c             │
│ timestamp with time zone │      timestamp      │                              varchar                              │                                varchar                                 │ timestamp with time zone │
├──────────────────────────┼─────────────────────┼───────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────┼──────────────────────────┤
│ 2026-07-15 16:00:00+00   │ 2026-07-15 08:00:00 │ TIMESTAMP WITH TIME ZONE                                          │ TIMESTAMP                                                              │ 2026-07-15 03:00:00+00   │
└──────────────────────────┴─────────────────────┴───────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────┴──────────────────────────┘
```

### twice over: a moment as another zone's clock would read it

```x
(sql "SET TimeZone = 'UTC'; SELECT TIMESTAMPTZ '2026-07-15 12:00:00+00' AT TIME ZONE 'Asia/Tokyo' AT TIME ZONE 'UTC' a, (TIMESTAMP '2026-07-15 12:00:00' AT TIME ZONE 'Asia/Tokyo')::TIMESTAMP b")
```
---
```output
┌──────────────────────────┬─────────────────────┐
│            a             │          b          │
│ timestamp with time zone │      timestamp      │
├──────────────────────────┼─────────────────────┤
│ 2026-07-15 21:00:00+00   │ 2026-07-15 03:00:00 │
└──────────────────────────┴─────────────────────┘
```

## zoned arithmetic

### a day on is the same time on the clock the next day, whatever the clock did; hours are time gone by

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMPTZ '2026-07-15 12:00:00+00' + INTERVAL 1 DAY a, TIMESTAMPTZ '2026-03-07 12:00:00-05' + INTERVAL 1 DAY b, TIMESTAMPTZ '2026-03-07 12:00:00-05' + INTERVAL 24 HOUR c, TIMESTAMPTZ '2026-01-31 12:00:00-05' + INTERVAL 1 MONTH d, TIMESTAMPTZ '2026-11-01 12:00:00-05' - INTERVAL 1 DAY e, INTERVAL 1 HOUR + TIMESTAMPTZ '2026-07-15 12:00:00+00' f")
```
---
```output
┌──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┬──────────────────────────┐
│            a             │            b             │            c             │            d             │            e             │            f             │
│ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │ timestamp with time zone │
├──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ 2026-07-16 08:00:00-04   │ 2026-03-08 12:00:00-04   │ 2026-03-08 13:00:00-04   │ 2026-02-28 12:00:00-05   │ 2026-10-31 12:00:00-04   │ 2026-07-15 09:00:00-04   │
└──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┴──────────────────────────┘
```

### two moments apart are an interval

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMPTZ '2026-07-15 12:00:00+00' - TIMESTAMPTZ '2026-07-14 00:00:00+00' a, TIMESTAMPTZ '2026-03-08 12:00:00-04' - TIMESTAMPTZ '2026-03-07 12:00:00-05' b, typeof(TIMESTAMPTZ '2026-07-15 12:00:00+00' - INTERVAL 1 HOUR)")
```
---
```output
┌────────────────┬──────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│       a        │    b     │ typeof((CAST('2026-07-15 12:00:00+00' AS TIMESTAMPTZ) - to_hours(CAST(trunc(CAST(1 AS DOUBLE)) AS BIGINT)))) │
│    interval    │ interval │                                                   varchar                                                    │
├────────────────┼──────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 1 day 12:00:00 │ 1 day    │ TIMESTAMP WITH TIME ZONE                                                                                     │
└────────────────┴──────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### compared as moments; a timestamp, a date and text beside one are read on the session's clock

```x
(sql "SET TimeZone = 'America/New_York'; SELECT TIMESTAMPTZ '2026-07-15 12:00:00+00' = TIMESTAMP '2026-07-15 08:00:00' a, TIMESTAMPTZ '2026-07-15 12:00:00+00' > DATE '2026-07-15' b, TIMESTAMPTZ '2026-07-15 12:00:00+00' = '2026-07-15 12:00:00+00' c, TIMESTAMPTZ '2026-07-15 12:00:00+00' < TIMESTAMPTZ '2026-07-15 08:00:01-04' d, TIMESTAMPTZ '2026-07-15 12:00:00+00' = TIMESTAMPTZ '2026-07-15 21:00:00+09' e, typeof(coalesce(TIMESTAMPTZ '2026-07-15 12:00:00+00', TIMESTAMP '2026-01-01 00:00:00')) f")
```
---
```output
┌─────────┬─────────┬─────────┬─────────┬─────────┬──────────────────────────┐
│    a    │    b    │    c    │    d    │    e    │            f             │
│ boolean │ boolean │ boolean │ boolean │ boolean │         varchar          │
├─────────┼─────────┼─────────┼─────────┼─────────┼──────────────────────────┤
│ true    │ true    │ true    │ true    │ true    │ TIMESTAMP WITH TIME ZONE │
└─────────┴─────────┴─────────┴─────────┴─────────┴──────────────────────────┘
```

## zoned functions

### the parts of a moment are its parts on the session's clock

```x
(sql "SET TimeZone = 'America/New_York'; SELECT year(t), month(t), day(t), hour(t), minute(t), dayofweek(t), dayname(t), date_part('hour', t), EXTRACT(hour FROM t), last_day(t), strftime(t, '%Y-%m-%d %H:%M') FROM (SELECT TIMESTAMPTZ '2026-07-15 03:30:00+00' AS t)")
```
---
```output
┌───────────┬────────────┬──────────┬───────────┬─────────────┬──────────────┬────────────┬──────────────────────┬──────────────────────┬─────────────┬───────────────────────────────┐
│ "year"(t) │ "month"(t) │ "day"(t) │ "hour"(t) │ "minute"(t) │ dayofweek(t) │ dayname(t) │ date_part('hour', t) │ date_part('HOUR', t) │ last_day(t) │ strftime(t, '%Y-%m-%d %H:%M') │
│   int64   │   int64    │  int64   │   int64   │    int64    │    int64     │  varchar   │        int64         │        int64         │    date     │            varchar            │
├───────────┼────────────┼──────────┼───────────┼─────────────┼──────────────┼────────────┼──────────────────────┼──────────────────────┼─────────────┼───────────────────────────────┤
│      2026 │          7 │       14 │        23 │          30 │            2 │ Tuesday    │                   23 │                   23 │ 2026-07-31  │ 2026-07-14 23:30              │
└───────────┴────────────┴──────────┴───────────┴─────────────┴──────────────┴────────────┴──────────────────────┴──────────────────────┴─────────────┴───────────────────────────────┘
```

### date_trunc cuts on that clock and answers a moment

```x
(sql "SET TimeZone = 'America/New_York'; SELECT date_trunc('day', t), typeof(date_trunc('day', t)), date_trunc('hour', t), date_trunc('month', t) FROM (SELECT TIMESTAMPTZ '2026-07-15 03:30:00+00' AS t)")
```
---
```output
┌──────────────────────────┬──────────────────────────────┬──────────────────────────┬──────────────────────────┐
│   date_trunc('day', t)   │ typeof(date_trunc('day', t)) │  date_trunc('hour', t)   │  date_trunc('month', t)  │
│ timestamp with time zone │           varchar            │ timestamp with time zone │ timestamp with time zone │
├──────────────────────────┼──────────────────────────────┼──────────────────────────┼──────────────────────────┤
│ 2026-07-14 00:00:00-04   │ TIMESTAMP WITH TIME ZONE     │ 2026-07-14 23:00:00-04   │ 2026-07-01 00:00:00-04   │
└──────────────────────────┴──────────────────────────────┴──────────────────────────┴──────────────────────────┘
```

### now is a moment and today a date

```x
(sql "SELECT typeof(now()), typeof(today()), now() > TIMESTAMPTZ '2026-01-01 00:00:00+00', now() - INTERVAL 1 DAY < now()")
```
---
```output
┌──────────────────────────┬─────────────────┬─────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────┐
│      typeof(now())       │ typeof(today()) │ (now() > CAST('2026-01-01 00:00:00+00' AS TIMESTAMPTZ)) │ ((now() - to_days(CAST(trunc(CAST(1 AS DOUBLE)) AS INTEGER))) < now()) │
│         varchar          │     varchar     │                         boolean                         │                                boolean                                 │
├──────────────────────────┼─────────────────┼─────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ TIMESTAMP WITH TIME ZONE │ DATE            │ true                                                    │ true                                                                   │
└──────────────────────────┴─────────────────┴─────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────┘
```

## zoned columns

### columns: text and timestamps go in as moments

```x
(sql "SET TimeZone = 'America/New_York'; CREATE OR REPLACE TABLE z (id INTEGER, t TIMESTAMPTZ, u TIMESTAMP WITH TIME ZONE); INSERT INTO z VALUES (1, '2026-07-15 12:00:00+00', '2026-01-15 12:00:00'), (2, NULL, TIMESTAMP '2026-01-15 12:00:00'), (3, '2026-03-08 06:59:59+00', '2026-11-01 05:30:00+00'); SELECT * FROM z ORDER BY id; SELECT typeof(t), typeof(u) FROM z LIMIT 1")
```
---
```output
┌───────┬──────────────────────────┬──────────────────────────┐
│  id   │            t             │            u             │
│ int32 │ timestamp with time zone │ timestamp with time zone │
├───────┼──────────────────────────┼──────────────────────────┤
│     1 │ 2026-07-15 08:00:00-04   │ 2026-01-15 12:00:00-05   │
│     2 │ NULL                     │ 2026-01-15 12:00:00-05   │
│     3 │ 2026-03-08 01:59:59-05   │ 2026-11-01 01:30:00-04   │
└───────┴──────────────────────────┴──────────────────────────┘
┌──────────────────────────┬──────────────────────────┐
│        typeof(t)         │        typeof(u)         │
│         varchar          │         varchar          │
├──────────────────────────┼──────────────────────────┤
│ TIMESTAMP WITH TIME ZONE │ TIMESTAMP WITH TIME ZONE │
└──────────────────────────┴──────────────────────────┘
```

### the same rows on another clock

```x
(sql "SET TimeZone = 'America/New_York'; CREATE OR REPLACE TABLE z (id INTEGER, t TIMESTAMPTZ, u TIMESTAMP WITH TIME ZONE); INSERT INTO z VALUES (1, '2026-07-15 12:00:00+00', '2026-01-15 12:00:00'), (2, NULL, TIMESTAMP '2026-01-15 12:00:00'), (3, '2026-03-08 06:59:59+00', '2026-11-01 05:30:00+00'); SET TimeZone = 'UTC'; SELECT * FROM z ORDER BY id")
```
---
```output
┌───────┬──────────────────────────┬──────────────────────────┐
│  id   │            t             │            u             │
│ int32 │ timestamp with time zone │ timestamp with time zone │
├───────┼──────────────────────────┼──────────────────────────┤
│     1 │ 2026-07-15 12:00:00+00   │ 2026-01-15 17:00:00+00   │
│     2 │ NULL                     │ 2026-01-15 17:00:00+00   │
│     3 │ 2026-03-08 06:59:59+00   │ 2026-11-01 05:30:00+00   │
└───────┴──────────────────────────┴──────────────────────────┘
```

### sorted, grouped and aggregated as moments

```x
(sql "SET TimeZone = 'America/New_York'; CREATE OR REPLACE TABLE z (id INTEGER, t TIMESTAMPTZ, u TIMESTAMP WITH TIME ZONE); INSERT INTO z VALUES (1, '2026-07-15 12:00:00+00', '2026-01-15 12:00:00'), (2, NULL, TIMESTAMP '2026-01-15 12:00:00'), (3, '2026-03-08 06:59:59+00', '2026-11-01 05:30:00+00'); SELECT id FROM z ORDER BY t DESC NULLS LAST; SELECT min(t), max(u), count(t), count(DISTINCT u) FROM z; SELECT u, count(*) FROM z GROUP BY u ORDER BY u; SELECT id FROM z WHERE t > '2026-06-01' AND u < TIMESTAMP '2026-06-01 00:00:00'")
```
---
```output
┌───────┐
│  id   │
│ int32 │
├───────┤
│     1 │
│     3 │
│     2 │
└───────┘
┌──────────────────────────┬──────────────────────────┬──────────┬───────────────────┐
│          min(t)          │          max(u)          │ count(t) │ count(DISTINCT u) │
│ timestamp with time zone │ timestamp with time zone │  int64   │       int64       │
├──────────────────────────┼──────────────────────────┼──────────┼───────────────────┤
│ 2026-03-08 01:59:59-05   │ 2026-11-01 01:30:00-04   │        2 │                 2 │
└──────────────────────────┴──────────────────────────┴──────────┴───────────────────┘
┌──────────────────────────┬──────────────┐
│            u             │ count_star() │
│ timestamp with time zone │    int64     │
├──────────────────────────┼──────────────┤
│ 2026-01-15 12:00:00-05   │            2 │
│ 2026-11-01 01:30:00-04   │            1 │
└──────────────────────────┴──────────────┘
┌───────┐
│  id   │
│ int32 │
├───────┤
│     1 │
└───────┘
```

## zoned errors

### text that is no timestamp

```x
(sql "SELECT TIMESTAMPTZ 'abc'")
```
---
```output
Conversion Error: invalid timestamp field format: "abc", expected format is (YYYY-MM-DD HH:MM[:SS[.US]][±HH[:MM[:SS]]| ZONE])
```

### a zone the system has not

```x
(sql "SELECT TIMESTAMPTZ '2026-01-15 12:00:00 Nowhere/Land'")
```
---
```output
Conversion Error: Unknown TimeZone 'Nowhere/Land'!
```

### and one in SET

```x
(sql "SET TimeZone = 'Nowhere/Land'")
```
---
```output
Not implemented Error: Unknown TimeZone 'Nowhere/Land'!
```

### a moment has no time of day of its own

```x
(sql "SET TimeZone = 'America/New_York'; SELECT (TIMESTAMPTZ '2026-07-15 12:00:00+00')::TIME")
```
---
```output
Conversion Error: Unimplemented type for cast (TIMESTAMP WITH TIME ZONE -> TIME)
```

CASE, IN, BETWEEN and LIKE.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## conditions case

### the first WHEN that is true gives the answer, and ELSE the rest

```x
(sql "SELECT CASE WHEN 1 > 2 THEN 'x' WHEN 2 > 1 THEN 'y' ELSE 'z' END, CASE WHEN false THEN 1 ELSE 2 END")
```
---
```output
┌────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────┐
│ CASE  WHEN ((1 > 2)) THEN ('x') WHEN ((2 > 1)) THEN ('y') ELSE 'z' END │ CASE  WHEN (false) THEN (1) ELSE 2 END │
│                                varchar                                 │                 int32                  │
├────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────┤
│ y                                                                      │                                      2 │
└────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────┘
```

### with no ELSE the rest is NULL, of the type of the answers

```x
(sql "SELECT CASE WHEN false THEN 1 END, CASE WHEN false THEN 'x' END")
```
---
```output
┌───────────────────────────────────────────┬─────────────────────────────────────────────┐
│ CASE  WHEN (false) THEN (1) ELSE NULL END │ CASE  WHEN (false) THEN ('x') ELSE NULL END │
│                   int32                   │                   varchar                   │
├───────────────────────────────────────────┼─────────────────────────────────────────────┤
│                                      NULL │ NULL                                        │
└───────────────────────────────────────────┴─────────────────────────────────────────────┘
```

### CASE x WHEN v compares x with each v

```x
(sql "SELECT CASE 2 WHEN 1 THEN 'a' WHEN 2 THEN 'b' END, CASE 'q' WHEN 'p' THEN 1 ELSE 0 END")
```
---
```output
┌─────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────┐
│ CASE  WHEN ((2 = 1)) THEN ('a') WHEN ((2 = 2)) THEN ('b') ELSE NULL END │ CASE  WHEN (('q' = 'p')) THEN (1) ELSE 0 END │
│                                 varchar                                 │                    int32                     │
├─────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────┤
│ b                                                                       │                                            0 │
└─────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────┘
```

### a condition that is NULL is not true

```x
(sql "SELECT CASE WHEN NULL THEN 1 ELSE 2 END, CASE NULL WHEN NULL THEN 1 ELSE 2 END")
```
---
```output
┌───────────────────────────────────────┬────────────────────────────────────────────────┐
│ CASE  WHEN (NULL) THEN (1) ELSE 2 END │ CASE  WHEN ((NULL = NULL)) THEN (1) ELSE 2 END │
│                 int32                 │                     int32                      │
├───────────────────────────────────────┼────────────────────────────────────────────────┤
│                                     2 │                                              2 │
└───────────────────────────────────────┴────────────────────────────────────────────────┘
```

### the answers go into one type: the wider integer, a decimal, a double

```x
(sql "SELECT CASE WHEN true THEN 1 ELSE 2147483648 END, CASE WHEN true THEN 1 ELSE 2.5 END, CASE WHEN true THEN 1 ELSE 1e0 END, CASE WHEN false THEN 1.5 ELSE 2 END")
```
---
```output
┌────────────────────────────────────────────────┬─────────────────────────────────────────┬─────────────────────────────────────────┬──────────────────────────────────────────┐
│ CASE  WHEN (true) THEN (1) ELSE 2147483648 END │ CASE  WHEN (true) THEN (1) ELSE 2.5 END │ CASE  WHEN (true) THEN (1) ELSE 1e0 END │ CASE  WHEN (false) THEN (1.5) ELSE 2 END │
│                     int64                      │              decimal(11,1)              │                 double                  │              decimal(11,1)               │
├────────────────────────────────────────────────┼─────────────────────────────────────────┼─────────────────────────────────────────┼──────────────────────────────────────────┤
│                                              1 │                                     1.0 │                                     1.0 │                                      2.0 │
└────────────────────────────────────────────────┴─────────────────────────────────────────┴─────────────────────────────────────────┴──────────────────────────────────────────┘
```

### over the rows of a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT a, CASE WHEN a IS NULL THEN 'none' WHEN a < 3 THEN 'low' ELSE 'high' END AS size FROM t ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │  size   │
│ int32 │ varchar │
├───────┼─────────┤
│     1 │ low     │
│     2 │ low     │
│     3 │ high    │
│     5 │ high    │
│  NULL │ none    │
└───────┴─────────┘
```

### an answer that is not taken is not computed

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT a, CASE WHEN a = 1 THEN 0 ELSE 10 // (a - 1) END AS q FROM t WHERE a IS NOT NULL ORDER BY a")
```
---
```output
┌───────┬───────┐
│   a   │   q   │
│ int32 │ int32 │
├───────┼───────┤
│     1 │     0 │
│     2 │    10 │
│     3 │     5 │
│     5 │     2 │
└───────┴───────┘
```

### a CASE of aggregates, and a CASE inside one

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT CASE WHEN count(*) > 3 THEN 'many' ELSE 'few' END, sum(CASE WHEN a > 1 THEN 1 ELSE 0 END) FROM t")
```
---
```output
┌──────────────────────────────────────────────────────────────┬───────────────────────────────────────────────┐
│ CASE  WHEN ((count_star() > 3)) THEN ('many') ELSE 'few' END │ sum(CASE  WHEN ((a > 1)) THEN (1) ELSE 0 END) │
│                           varchar                            │                    int128                     │
├──────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┤
│ many                                                         │                                             3 │
└──────────────────────────────────────────────────────────────┴───────────────────────────────────────────────┘
```

### a group by a CASE

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT CASE WHEN a < 3 THEN 'low' ELSE 'other' END AS k, count(*) FROM t GROUP BY ALL ORDER BY k")
```
---
```output
┌─────────┬──────────────┐
│    k    │ count_star() │
│ varchar │    int64     │
├─────────┼──────────────┤
│ low     │            2 │
│ other   │            3 │
└─────────┴──────────────┘
```

### answers of types that do not go together

DuckDB tries the text as a number and says it cannot convert it.

```x
(sql "SELECT CASE WHEN true THEN 1 ELSE 'x' END")
```
---
```output
Binder Error: Cannot mix values of type INTEGER and VARCHAR - an explicit cast is required
```

## conditions in

### IN is true when the value equals one of the list

```x
(sql "SELECT 1 IN (1, 2), 3 IN (1, 2), 'a' IN ('a', 'b'), 1.5 IN (1, 1.5)")
```
---
```output
┌───────────────┬───────────────┬─────────────────────┬───────────────────┐
│ (1 IN (1, 2)) │ (3 IN (1, 2)) │ ('a' IN ('a', 'b')) │ (1.5 IN (1, 1.5)) │
│    boolean    │    boolean    │       boolean       │      boolean      │
├───────────────┼───────────────┼─────────────────────┼───────────────────┤
│ true          │ false         │ true                │ true              │
└───────────────┴───────────────┴─────────────────────┴───────────────────┘
```

### NOT IN

```x
(sql "SELECT 3 NOT IN (1, 2), 1 NOT IN (1, 2)")
```
---
```output
┌─────────────────────┬─────────────────────┐
│ (NOT (3 IN (1, 2))) │ (NOT (1 IN (1, 2))) │
│       boolean       │       boolean       │
├─────────────────────┼─────────────────────┤
│ true                │ false               │
└─────────────────────┴─────────────────────┘
```

### a NULL in the list makes a miss NULL, and a NULL value is NULL

```x
(sql "SELECT 1 IN (2, NULL), 1 IN (1, NULL), 1 NOT IN (2, NULL), NULL IN (1)")
```
---
```output
┌──────────────────┬──────────────────┬────────────────────────┬───────────────┐
│ (1 IN (2, NULL)) │ (1 IN (1, NULL)) │ (NOT (1 IN (2, NULL))) │ (NULL IN (1)) │
│     boolean      │     boolean      │        boolean         │    boolean    │
├──────────────────┼──────────────────┼────────────────────────┼───────────────┤
│ NULL             │ true             │ NULL                   │ NULL          │
└──────────────────┴──────────────────┴────────────────────────┴───────────────┘
```

### over the rows of a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT a FROM t WHERE a IN (1, 3, 5) ORDER BY a; SELECT b FROM t WHERE b NOT IN ('apple', 'date') ORDER BY b")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     1 │
│     3 │
│     5 │
└───────┘
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ banana  │
│ cherry  │
└─────────┘
```

## conditions between

### BETWEEN takes both ends

```x
(sql "SELECT 2 BETWEEN 1 AND 3, 1 BETWEEN 1 AND 3, 3 BETWEEN 1 AND 3, 4 BETWEEN 1 AND 3, 'b' BETWEEN 'a' AND 'c'")
```
---
```output
┌─────────────────────┬─────────────────────┬─────────────────────┬─────────────────────┬───────────────────────────┐
│ (2 BETWEEN 1 AND 3) │ (1 BETWEEN 1 AND 3) │ (3 BETWEEN 1 AND 3) │ (4 BETWEEN 1 AND 3) │ ('b' BETWEEN 'a' AND 'c') │
│       boolean       │       boolean       │       boolean       │       boolean       │          boolean          │
├─────────────────────┼─────────────────────┼─────────────────────┼─────────────────────┼───────────────────────────┤
│ true                │ true                │ true                │ false               │ true                      │
└─────────────────────┴─────────────────────┴─────────────────────┴─────────────────────┴───────────────────────────┘
```

### NOT BETWEEN, and the AND that follows a BETWEEN

```x
(sql "SELECT 2 NOT BETWEEN 1 AND 3, 2 BETWEEN 1 AND 3 AND 5 > 4")
```
---
```output
┌───────────────────────────┬───────────────────────────────────┐
│ (NOT (2 BETWEEN 1 AND 3)) │ ((2 BETWEEN 1 AND 3) AND (5 > 4)) │
│          boolean          │              boolean              │
├───────────────────────────┼───────────────────────────────────┤
│ false                     │ true                              │
└───────────────────────────┴───────────────────────────────────┘
```

### a NULL end is NULL unless the other end already says no

```x
(sql "SELECT 2 BETWEEN NULL AND 3, 5 BETWEEN NULL AND 3, NULL BETWEEN 1 AND 3")
```
---
```output
┌────────────────────────┬────────────────────────┬────────────────────────┐
│ (2 BETWEEN NULL AND 3) │ (5 BETWEEN NULL AND 3) │ (NULL BETWEEN 1 AND 3) │
│        boolean         │        boolean         │        boolean         │
├────────────────────────┼────────────────────────┼────────────────────────┤
│ NULL                   │ false                  │ NULL                   │
└────────────────────────┴────────────────────────┴────────────────────────┘
```

### the ends are expressions

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT a FROM t WHERE a BETWEEN 1 + 1 AND 2 * 2 ORDER BY a")
```
---
```output
┌───────┐
│   a   │
│ int32 │
├───────┤
│     2 │
│     3 │
└───────┘
```

## conditions like

### % is any run of characters and _ any one

```x
(sql "SELECT 'abc' LIKE 'a%', 'abc' LIKE '%c', 'abc' LIKE '%b%', 'abc' LIKE 'a_c', 'abc' LIKE 'a_', 'abc' LIKE 'abc', 'abc' LIKE '%'")
```
---
```output
┌─────────────────┬─────────────────┬──────────────────┬──────────────────┬─────────────────┬──────────────────┬────────────────┐
│ ('abc' ~~ 'a%') │ ('abc' ~~ '%c') │ ('abc' ~~ '%b%') │ ('abc' ~~ 'a_c') │ ('abc' ~~ 'a_') │ ('abc' ~~ 'abc') │ ('abc' ~~ '%') │
│     boolean     │     boolean     │     boolean      │     boolean      │     boolean     │     boolean      │    boolean     │
├─────────────────┼─────────────────┼──────────────────┼──────────────────┼─────────────────┼──────────────────┼────────────────┤
│ true            │ true            │ true             │ true             │ false           │ true             │ true           │
└─────────────────┴─────────────────┴──────────────────┴──────────────────┴─────────────────┴──────────────────┴────────────────┘
```

### NOT LIKE

```x
(sql "SELECT 'abc' NOT LIKE 'a%', 'abc' NOT LIKE 'x%'")
```
---
```output
┌──────────────────┬──────────────────┐
│ ('abc' !~~ 'a%') │ ('abc' !~~ 'x%') │
│     boolean      │     boolean      │
├──────────────────┼──────────────────┤
│ false            │ true             │
└──────────────────┴──────────────────┘
```

### LIKE minds case and ILIKE does not

```x
(sql "SELECT 'ABC' LIKE 'a%', 'ABC' ILIKE 'a%', 'abc' NOT ILIKE 'A%'")
```
---
```output
┌─────────────────┬──────────────────┬───────────────────┐
│ ('ABC' ~~ 'a%') │ ('ABC' ~~* 'a%') │ ('abc' !~~* 'A%') │
│     boolean     │     boolean      │      boolean      │
├─────────────────┼──────────────────┼───────────────────┤
│ false           │ true             │ false             │
└─────────────────┴──────────────────┴───────────────────┘
```

### _ is one character, of however many bytes

```x
(sql "SELECT 'héllo' LIKE 'h_llo', 'héllo' LIKE 'h__llo', 'é' LIKE '_'")
```
---
```output
┌──────────────────────┬───────────────────────┬──────────────┐
│ ('héllo' ~~ 'h_llo') │ ('héllo' ~~ 'h__llo') │ ('é' ~~ '_') │
│       boolean        │        boolean        │   boolean    │
├──────────────────────┼───────────────────────┼──────────────┤
│ true                 │ false                 │ true         │
└──────────────────────┴───────────────────────┴──────────────┘
```

### an empty pattern matches only an empty text, and several % are one

```x
(sql "SELECT '' LIKE '', 'a' LIKE '', '' LIKE '%', 'abc' LIKE 'a%%c'")
```
---
```output
┌────────────┬─────────────┬─────────────┬───────────────────┐
│ ('' ~~ '') │ ('a' ~~ '') │ ('' ~~ '%') │ ('abc' ~~ 'a%%c') │
│  boolean   │   boolean   │   boolean   │      boolean      │
├────────────┼─────────────┼─────────────┼───────────────────┤
│ true       │ false       │ true        │ true              │
└────────────┴─────────────┴─────────────┴───────────────────┘
```

### a NULL on either side is NULL

```x
(sql "SELECT NULL LIKE 'a', 'a' LIKE NULL")
```
---
```output
┌───────────────┬───────────────┐
│ (NULL ~~ 'a') │ ('a' ~~ NULL) │
│    boolean    │    boolean    │
├───────────────┼───────────────┤
│ NULL          │ NULL          │
└───────────────┴───────────────┘
```

### over the rows of a table

```x
(sql "CREATE OR REPLACE TABLE t (a INTEGER, b VARCHAR); INSERT INTO t VALUES (1,'apple'),(2,'banana'),(3,'cherry'),(NULL,'date'),(5,NULL); SELECT b FROM t WHERE b LIKE '%an%' OR b LIKE '_a__' ORDER BY b")
```
---
```output
┌─────────┐
│    b    │
│ varchar │
├─────────┤
│ banana  │
│ date    │
└─────────┘
```

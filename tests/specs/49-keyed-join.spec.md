A join by key (`sql/exec.x`): when its condition has an equality of the
two sides in it, the right's rows are held by that value and each left
row is tried beside the ones of its own.  The answer is the one every
pair tried would give; the cases here are where the two could differ.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## joined by a key

### an equality of the two sides: each left row beside the right rows of its key, in the right's order

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k = r.k ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     2 │   201 │
│     4 │   200 │
│     4 │   201 │
└───────┴───────┘
```

### the same with the sides written the other way round

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON r.k = l.k ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     2 │   201 │
│     4 │   200 │
│     4 │   201 │
└───────┴───────┘
```

### a NULL key equals nothing, on either side

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k = r.k WHERE id = 3 OR rid = 300")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
└───────┴───────┘
     0 rows    
```

### keys of text, which are equal only in the same case

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.t = r.t ORDER BY id")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
└───────┴───────┘
```

### two equalities

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k = r.k AND l.t = r.t ORDER BY id")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
└───────┴───────┘
```

### an equality and another condition, which is still asked of each pair

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k = r.k AND r.rid > 200 ORDER BY id; SELECT id, rid FROM l JOIN r ON l.k = r.k AND l.id + r.rid > 202 ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     2 │   201 │
│     4 │   201 │
└───────┴───────┘
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     2 │   201 │
│     4 │   200 │
│     4 │   201 │
└───────┴───────┘
```

### a key that is an expression of its side

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k + 10 = r.k ORDER BY id, rid; SELECT id, rid FROM l JOIN r ON upper(l.t) = upper(r.t) ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   200 │
│     1 │   201 │
│     2 │   400 │
│     4 │   400 │
└───────┴───────┘
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     4 │   200 │
└───────┴───────┘
```

### LEFT JOIN keeps a left row with no right row of its key

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l LEFT JOIN r ON l.k = r.k ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     2 │   201 │
│     3 │  NULL │
│     4 │   200 │
│     4 │   201 │
│     5 │  NULL │
└───────┴───────┘
```

### RIGHT JOIN keeps a right row no left row took

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l RIGHT JOIN r ON l.k = r.k ORDER BY rid, id")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     4 │   200 │
│     2 │   201 │
│     4 │   201 │
│  NULL │   300 │
│  NULL │   400 │
└───────┴───────┘
```

### FULL JOIN keeps both

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l FULL JOIN r ON l.k = r.k ORDER BY id NULLS LAST, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     2 │   201 │
│     3 │  NULL │
│     4 │   200 │
│     4 │   201 │
│     5 │  NULL │
│  NULL │   300 │
│  NULL │   400 │
└───────┴───────┘
```

### a right row whose key matched but whose pair the rest of the condition refused is still unmatched

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l RIGHT JOIN r ON l.k = r.k AND l.id > 2 ORDER BY rid, id")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│  NULL │   100 │
│     4 │   200 │
│     4 │   201 │
│  NULL │   300 │
│  NULL │   400 │
└───────┴───────┘
```

### USING is joined by its columns

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid, k FROM l JOIN r USING (k) ORDER BY id, rid; SELECT id, rid FROM l LEFT JOIN r USING (k, t) ORDER BY id")
```
---
```output
┌───────┬───────┬───────┐
│  id   │  rid  │   k   │
│ int32 │ int32 │ int32 │
├───────┼───────┼───────┤
│     1 │   100 │    10 │
│     2 │   200 │    20 │
│     2 │   201 │    20 │
│     4 │   200 │    20 │
│     4 │   201 │    20 │
└───────┴───────┴───────┘
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     3 │  NULL │
│     4 │  NULL │
│     5 │  NULL │
└───────┴───────┘
```

## not joined by a key, and answered the same

### a whole number beside a DOUBLE, which are equal though they are not written alike

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.d = r.k / 10 ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     2 │   201 │
└───────┴───────┘
```

### a DOUBLE beside a DECIMAL

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.d = r.n ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     4 │   201 │
└───────┴───────┘
```

### an equality of one side with itself, and of constants

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT count(*) AS n FROM l JOIN r ON l.k = l.id * 10; SELECT count(*) AS m FROM l JOIN r ON 1 = 1")
```
---
```output
┌───────┐
│   n   │
│ int64 │
├───────┤
│    10 │
└───────┘
┌───────┐
│   m   │
│ int64 │
├───────┤
│    25 │
└───────┘
```

### an OR of equalities

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k = r.k OR l.t = r.t ORDER BY id, rid")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     1 │   100 │
│     2 │   200 │
│     2 │   201 │
│     4 │   200 │
│     4 │   201 │
└───────┴───────┘
```

### a subquery beside the equality

```x
(sql "CREATE OR REPLACE TABLE l (id INT, k INT, t VARCHAR, d DOUBLE); INSERT INTO l VALUES (1, 10, 'a', 1.0), (2, 20, 'b', 2.0), (3, NULL, NULL, NULL), (4, 20, 'B', 2.5), (5, 40, 'e', 4.0); CREATE OR REPLACE TABLE r (rid INT, k BIGINT, t VARCHAR, n DECIMAL(4,1)); INSERT INTO r VALUES (100, 10, 'a', 1.0), (200, 20, 'b', 2.0), (201, 20, 'x', 2.5), (300, NULL, NULL, NULL), (400, 30, 'd', 3.0); SELECT id, rid FROM l JOIN r ON l.k = r.k AND r.rid = (SELECT min(rid) FROM r r2 WHERE r2.k = 20) ORDER BY id")
```
---
```output
┌───────┬───────┐
│  id   │  rid  │
│ int32 │ int32 │
├───────┼───────┤
│     2 │   200 │
│     4 │   200 │
└───────┴───────┘
```

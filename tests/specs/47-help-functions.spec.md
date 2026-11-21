`.help NAME` for a function (`lib/sql/help.x`): how it is written, what it
answers, its other names and the topic it is under.  The functions are
rows of `sql-help-functions`, and the first case holds every function
the evaluator has to one.

## help functions

### every function there is to call has a row, by its name or as another name of one

```x
(write (List reject sql-help-function (sql-function-names)))
```
---
    ()

### and so have the functions that are read where a table is

```x
(write (List reject sql-help-function (list "read_csv" "read_csv_auto" "read_json" "read_json_auto" "read_ndjson" "sqlite_scan" "unnest")))
```
---
    ()

### .help NAME says how a function is written and what it answers

```x
(sql-eval-line ".help list_zip")
```
---
```output
list_zip(list, ... [, truth])
  a list of tuples, the lists' first elements and then their second; a true last cuts to the shortest list
  Also array_zip
  See .help lists
```

### in any case

```x
(sql-eval-line ".help COALESCE")
```
---
```output
coalesce(value, ...)
  the first value that is not NULL
  See .help functions
```

### another name of a function says whose it is

```x
(sql-eval-line ".help array_push_back")
```
---
```output
array_push_back is another name of list_append
list_append(list, value)
  the list with the value after its last
  Also array_append, array_push_back
  See .help lists
```

### a topic lists the functions under it

```x
(sql-eval-line ".help group")
```
---
```output
group: A row for a group of rows.
  GROUP BY expression | alias | place in the list, ...
  GROUP BY ALL    every item that holds no aggregate
  HAVING condition    keeps the groups it is true for
  An aggregate takes DISTINCT inside its call: count(DISTINCT x).
Functions, each with .help NAME:
  count sum min max avg list
For example:
  SELECT b, count(*), avg(a) FROM t GROUP BY ALL HAVING count(*) > 1;
```

### a long list of them is on several lines

```x
(sql-eval-line ".help dates")
```
---
      SELECT date_trunc('month', ts), count(*) FROM t GROUP BY ALL;

### a topic's name is the topic, and a name that is neither is said so

```x
(%seq (sql-eval-line ".help nope") (sql-eval-line ".help window"))
```
---
      SELECT * FROM t QUALIFY row_number() OVER (PARTITION BY b ORDER BY a) = 1;

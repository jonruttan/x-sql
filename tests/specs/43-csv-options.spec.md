A CSV's separator and its other options (`sql/files.x`): found when
nothing says, or said to `read_csv` and to `COPY`.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## the separator found

### semicolons

```x
(sql-files "FROM '{F}semi.csv'")
```
---
```output
┌─────────┬───────┬─────────┐
│  name   │  age  │  city   │
│ varchar │ int64 │ varchar │
├─────────┼───────┼─────────┤
│ ida     │     7 │ Oslo    │
│ bo      │  NULL │ Rome    │
└─────────┴───────┴─────────┘
```

### tabs

```x
(sql-files "FROM '{F}tab.tsv'")
```
---
```output
┌─────────┬───────┐
│  name   │  age  │
│ varchar │ int64 │
├─────────┼───────┤
│ ida     │     7 │
│ bo      │     9 │
└─────────┴───────┘
```

### bars, and read_csv finds it as a name does

```x
(sql-files "FROM '{F}bar.csv'; SELECT count(*) AS n FROM read_csv('{F}bar.csv')")
```
---
```output
┌─────────┬───────┐
│  name   │  age  │
│ varchar │ int64 │
├─────────┼───────┤
│ ida     │     7 │
│ bo      │     9 │
└─────────┴───────┘
┌───────┐
│   n   │
│ int64 │
├───────┤
│     2 │
└───────┘
```

### commas still

```x
(sql-files "SELECT name, active FROM '{F}people.csv' ORDER BY name LIMIT 2")
```
---
```output
┌─────────┬─────────┐
│  name   │ active  │
│ varchar │ boolean │
├─────────┼─────────┤
│ Ada     │ true    │
│ Grace   │ false   │
└─────────┴─────────┘
```

## the separator said

### delim says it, and a file of another is one column

```x
(sql-files "FROM read_csv('{F}semi.csv', delim = ',')")
```
---
```output
┌───────────────┐
│ name;age;city │
│    varchar    │
├───────────────┤
│ ida;7;Oslo    │
│ bo;;Rome      │
└───────────────┘
```

### sep and delimiter are the same word, and := gives a value as = does

```x
(sql-files "SELECT name FROM read_csv('{F}semi.csv', sep = ';'); SELECT age FROM read_csv('{F}semi.csv', delimiter := ';')")
```
---
```output
┌─────────┐
│  name   │
│ varchar │
├─────────┤
│ ida     │
│ bo      │
└─────────┘
┌───────┐
│  age  │
│ int64 │
├───────┤
│     7 │
│  NULL │
└───────┘
```

## the first line

### header = false keeps the first line as a row

```x
(sql-files "FROM read_csv('{F}semi.csv', sep = ';', header = false)")
```
---
```output
┌─────────┬─────────┬─────────┐
│ column0 │ column1 │ column2 │
│ varchar │ varchar │ varchar │
├─────────┼─────────┼─────────┤
│ name    │ age     │ city    │
│ ida     │ 7       │ Oslo    │
│ bo      │ NULL    │ Rome    │
└─────────┴─────────┴─────────┘
```

### header = true takes it for names whatever it holds

```x
(sql-files "FROM read_csv('{F}nohead.csv', header = true)")
```
---
```output
┌─────────┬───────┐
│   ida   │   7   │
│ varchar │ int64 │
├─────────┼───────┤
│ bo      │     9 │
└─────────┴───────┘
```

### skip leaves lines out before the first

```x
(sql-files "FROM read_csv('{F}skip.csv', skip = 2)")
```
---
```output
┌─────────┬─────────┐
│  name   │   age   │
│ varchar │ varchar │
├─────────┼─────────┤
│ ida     │ 7       │
│ bo      │ NA      │
└─────────┴─────────┘
```

## NULLs, names and types

### nullstr is a text read as NULL

```x
(sql-files "FROM read_csv('{F}skip.csv', skip = 2, nullstr = 'NA')")
```
---
```output
┌─────────┬───────┐
│  name   │  age  │
│ varchar │ int64 │
├─────────┼───────┤
│ ida     │     7 │
│ bo      │  NULL │
└─────────┴───────┘
```

### names names the columns

```x
(sql-files "FROM read_csv('{F}nohead.csv', names = ['who', 'n'])")
```
---
```output
┌─────────┬───────┐
│   who   │   n   │
│ varchar │ int64 │
├─────────┼───────┤
│ ida     │     7 │
│ bo      │     9 │
└─────────┴───────┘
```

### fewer names than columns

```x
(sql-files "FROM read_csv('{F}nohead.csv', names = ['who'])")
```
---
```output
┌─────────┬─────────┐
│   who   │ column1 │
│ varchar │  int64  │
├─────────┼─────────┤
│ ida     │       7 │
│ bo      │       9 │
└─────────┴─────────┘
```

### columns says every name and type

```x
(sql-files "FROM read_csv('{F}nohead.csv', columns = {'who': 'VARCHAR', 'n': 'DOUBLE'})")
```
---
```output
┌─────────┬────────┐
│   who   │   n    │
│ varchar │ double │
├─────────┼────────┤
│ ida     │    7.0 │
│ bo      │    9.0 │
└─────────┴────────┘
```

### types says some

```x
(sql-files "FROM read_csv('{F}semi.csv', types = {'age': 'DOUBLE'}); SELECT typeof(age) FROM read_csv('{F}semi.csv', dtypes = {'age': 'SMALLINT'}) LIMIT 1")
```
---
```output
┌─────────┬────────┬─────────┐
│  name   │  age   │  city   │
│ varchar │ double │ varchar │
├─────────┼────────┼─────────┤
│ ida     │    7.0 │ Oslo    │
│ bo      │   NULL │ Rome    │
└─────────┴────────┴─────────┘
┌─────────────┐
│ typeof(age) │
│   varchar   │
├─────────────┤
│ SMALLINT    │
└─────────────┘
```

### all_varchar reads every column as text

```x
(sql-files "FROM read_csv('{F}semi.csv', all_varchar = true)")
```
---
```output
┌─────────┬─────────┬─────────┐
│  name   │   age   │  city   │
│ varchar │ varchar │ varchar │
├─────────┼─────────┼─────────┤
│ ida     │ 7       │ Oslo    │
│ bo      │ NULL    │ Rome    │
└─────────┴─────────┴─────────┘
```

### several at once, and queried

```x
(sql-files "SELECT who, n * 2 AS twice FROM read_csv('{F}nohead.csv', names = ['who', 'n'], header = false, delim = ',') WHERE n > 7")
```
---
```output
┌─────────┬───────┐
│   who   │ twice │
│ varchar │ int64 │
├─────────┼───────┤
│ bo      │    18 │
└─────────┴───────┘
```

## written

### COPY with DELIMITER writes that between the fields, and quotes a field that holds it

```x
(%seq (sql-files "COPY (SELECT 1 AS a, 'x;y' AS b, 'z' AS c) TO '{S}semi-out.csv' (DELIMITER ';')") (display (File read-all (Str8 append sql-scratch "semi-out.csv"))))
```
---
```output
a;b;c
1;"x;y";z
```

### SEP is the same, NULLSTR the text a NULL is written as, and HEADER false leaves the names out

```x
(%seq (sql-files "COPY (SELECT 1 AS a, NULL AS b) TO '{S}bar-out.csv' (FORMAT csv, SEP '|', NULLSTR 'NA', HEADER false)") (display (File read-all (Str8 append sql-scratch "bar-out.csv"))))
```
---
```output
1|NA
```

### read back, the separator found

```x
(sql-files "COPY (SELECT 1 AS a, 'x' AS b UNION ALL SELECT 2, 'y') TO '{S}tab-out.csv' (DELIM '	'); FROM '{S}tab-out.csv' ORDER BY a")
```
---
```output
┌───────┬─────────┐
│   a   │    b    │
│ int64 │ varchar │
├───────┼─────────┤
│     1 │ x       │
│     2 │ y       │
└───────┴─────────┘
```

### COPY ... FROM with the separator said

```x
(sql-files "CREATE OR REPLACE TABLE folk (name VARCHAR, age INT, city VARCHAR); COPY folk FROM '{F}semi.csv' (DELIMITER ';'); SELECT name, age FROM folk ORDER BY name")
```
---
```output
┌─────────┬───────┐
│  name   │  age  │
│ varchar │ int32 │
├─────────┼───────┤
│ bo      │  NULL │
│ ida     │     7 │
└─────────┴───────┘
```

## errors

### a name read_csv has not

```x
(sql-files "FROM read_csv('{F}semi.csv', nope = 1)")
```
---
```output
Binder Error: Invalid named parameter "nope" for function read_csv
```

### a name for a JSON file

```x
(sql-files "FROM read_json('{F}people.json', delim = ';')")
```
---
```output
Binder Error: Invalid named parameter "delim" for function read_json
```

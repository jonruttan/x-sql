# x-sql — SQL on x-lang

<p align="center"><img src="docs/bitwise-banner.svg" alt="x-sql, with Bitwise the owl" width="100%"></p>

A database language on [x-lang](https://github.com/jonruttan/x-lang),
loaded as a lang, following [DuckDB](https://duckdb.org/)'s dialect and
its way of showing a result.

    x -l sql                                  # a prompt
    x -l sql -- -c "SELECT 1 + 2 AS three"    # run and exit

    ┌───────┐
    │ three │
    │ int32 │
    ├───────┤
    │     3 │
    └───────┘

## Status

Pre-release: no release has been cut. Paired with x-lang v0.55.0
(`lang.xon` is the checkable row).

What is built:

- **Values.** INTEGER, BIGINT and HUGEINT, each constant the narrowest
  type that holds it; VARCHAR; BOOLEAN; NULL.
- **Operators.** `+ - * // %` on integers, in the wider operand's type,
  an overflow an error; `= == <> != < <= > >=`; `AND OR NOT` in three
  values; `IS [NOT] NULL`; `||`.
- **Tables.** In memory, for the life of the process: `CREATE [OR
  REPLACE] TABLE [IF NOT EXISTS]`, `INSERT INTO ... VALUES` with or
  without a column list, `DROP TABLE [IF EXISTS]`. A value is cast to its
  column's type as it goes in.
- **Queries.** `SELECT [DISTINCT]` with `*` and `t.*`, table aliases,
  `WHERE`, `ORDER BY` with `ASC`, `DESC` and `NULLS FIRST` or `LAST`,
  `LIMIT` and `OFFSET`; and DuckDB's order, `FROM t` alone or
  `FROM t SELECT ...`.
- **Joins.** `JOIN ... ON`, `LEFT`, `RIGHT` and `FULL [OUTER] JOIN`,
  `CROSS JOIN`, and tables listed with commas; a table joined to itself
  under two aliases.
- **Groups.** `count`, `sum`, `min` and `max`, with `DISTINCT` inside a
  call; `GROUP BY` an expression, an alias, a place in the list, or
  `ALL`; `HAVING`.
- **Results.** DuckDB's box, a column as wide as its widest text in
  terminal cells, headed by the alias, the column's name, or the
  expression spelled out.
- **The prompt.** A statement ends at a semicolon and may span lines;
  `.help`, `.tables` and `.quit`.

Anything else is refused by name (`Not implemented Error: UNION`) and not
answered differently.

## Planned

In this order:

1. Subqueries, `UNION`, `JOIN ... USING`, `UPDATE` and `DELETE`.
2. DOUBLE and DECIMAL, `/`, casts, and the scalar functions.
3. DuckDB's friendlier forms: `SELECT * EXCLUDE`, `GROUP BY ALL`, lists
   and structs, reading CSV and JSON files by name.
4. The prompt: statement colouring as it is typed, coloured results,
   completion, a `.help` for every statement and function, paging.
5. Other servers behind the same prompt: PostgreSQL's wire protocol, and
   MySQL's, which MariaDB also speaks.

## Tests

    make test       # the spec suite
    make check      # the suite against tests/contract/known-failures.txt

The specs under `tests/specs/` take their expected output from DuckDB
itself (`duckdb -no-agent -c`), version 2.0.0, except where a case says
it differs and why.

## Differences from DuckDB

- A parser error names the place in one line; DuckDB's second line, the
  statement with a caret under the place, is not built.
- A statement that stops short is `syntax error at end of input`; DuckDB
  names the last token it read.
- Every row of a result is shown; DuckDB cuts a long one to forty rows.
- Groups come in the order their keys first appear; DuckDB promises no
  order.
- A join compares every pair of rows.
- A table lasts as long as the process: there is no database file.
- A division by zero is an error, as in DuckDB 2.0, without its hint
  about `TRY` and `error_on_division_by_zero`.

## Install

    make install    # into <share>/langs/sql, where `x -l sql` looks

<p align="center"><img src="docs/bitwise-mark.svg" alt="Bitwise" width="96"></p>

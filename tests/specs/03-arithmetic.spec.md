Integer arithmetic: + - * // and %, in the wider operand's type, with an
overflow an error and never a wrapped number.

Expected output is DuckDB 2.0.0's own, taken from `duckdb -no-agent -c`, unless a case says otherwise.

## arithmetic integers

### // and % truncate toward zero

```x
(sql "SELECT 7 // 2, -7 // 2, 7 // -2, 7 % 2, -7 % 2")
```
---
```output
┌──────────┬───────────┬───────────┬─────────┬──────────┐
│ (7 // 2) │ (-7 // 2) │ (7 // -2) │ (7 % 2) │ (-7 % 2) │
│  int32   │   int32   │   int32   │  int32  │  int32   │
├──────────┼───────────┼───────────┼─────────┼──────────┤
│        3 │        -3 │        -3 │       1 │       -1 │
└──────────┴───────────┴───────────┴─────────┴──────────┘
```

### * and // bind tighter than + and -

```x
(sql "SELECT 2 + 3 * 4, 20 - 6 // 2, (2 + 3) * 4")
```
---
```output
┌───────────────┬─────────────────┬───────────────┐
│ (2 + (3 * 4)) │ (20 - (6 // 2)) │ ((2 + 3) * 4) │
│     int32     │      int32      │     int32     │
├───────────────┼─────────────────┼───────────────┤
│            14 │              17 │            20 │
└───────────────┴─────────────────┴───────────────┘
```

### the wider operand names the type

```x
(sql "SELECT 2147483648 + 1, 1 + 2147483648, 9223372036854775808 * 2")
```
---
```output
┌──────────────────┬──────────────────┬───────────────────────────┐
│ (2147483648 + 1) │ (1 + 2147483648) │ (9223372036854775808 * 2) │
│      int64       │      int64       │          int128           │
├──────────────────┼──────────────────┼───────────────────────────┤
│       2147483649 │       2147483649 │      18446744073709551616 │
└──────────────────┴──────────────────┴───────────────────────────┘
```

### a NULL operand answers NULL, in the other operand's type

```x
(sql "SELECT 1 + NULL, NULL * 2147483648, NULL // 0")
```
---
```output
┌────────────┬─────────────────────┬─────────────┐
│ (1 + NULL) │ (NULL * 2147483648) │ (NULL // 0) │
│   int32    │        int64        │    int32    │
├────────────┼─────────────────────┼─────────────┤
│       NULL │                NULL │        NULL │
└────────────┴─────────────────────┴─────────────┘
```

### two NULL constants add to a BIGINT NULL

```x
(sql "SELECT NULL + NULL")
```
---
```output
┌───────────────┐
│ (NULL + NULL) │
│     int64     │
├───────────────┤
│          NULL │
└───────────────┘
```

### a minus on an expression

```x
(sql "SELECT -(1 + 2), -(2147483648 * 2)")
```
---
```output
┌──────────────┬───────────────────────┐
│ (-((1 + 2))) │ (-((2147483648 * 2))) │
│    int32     │         int64         │
├──────────────┼───────────────────────┤
│           -3 │           -4294967296 │
└──────────────┴───────────────────────┘
```

## arithmetic overflow

### an INTEGER sum past its range is an error

```x
(sql "SELECT 2147483647 + 1")
```
---
```output
Out of Range Error: Overflow in addition of INT32 (2147483647 + 1)!
```

### and a difference

```x
(sql "SELECT -2147483647 - 2")
```
---
```output
Out of Range Error: Overflow in subtraction of INT32 (-2147483647 - 2)!
```

### and a product

```x
(sql "SELECT 2147483647 * 2")
```
---
```output
Out of Range Error: Overflow in multiplication of INT32 (2147483647 * 2)!
```

### a BIGINT does not widen to HUGEINT

```x
(sql "SELECT 2147483648 * 4294967296")
```
---
```output
Out of Range Error: Overflow in multiplication of INT64 (2147483648 * 4294967296)!
```

## arithmetic refusals

### division by zero

DuckDB's message goes on to name TRY and a setting; neither is built, so the
sentence ends here.

```x
(sql "SELECT 5 // 0")
```
---
```output
Invalid Input Error: Division by zero in expression (5 // 0).
```

### and a remainder by zero

```x
(sql "SELECT 5 % 0")
```
---
```output
Invalid Input Error: Division by zero in expression (5 % 0).
```

### arithmetic on a boolean

DuckDB names a constant's type INTEGER_LITERAL here and lists its candidates.

```x
(sql "SELECT true + 1")
```
---
```output
Binder Error: No function matches the given name and argument types '+(BOOLEAN, INTEGER)'.
```

### // and % are for integers

DuckDB answers the DOUBLE 3.75, the division with nothing dropped.

```x
(sql "SELECT 7.5 // 2")
```
---
```output
Not implemented Error: // on a number that is not an integer
```

# @weight 25
# @timeout-scale 4
<!-- The SCRAM case derives a key in 4096 rounds of HMAC-SHA-256: seconds
     with the compiled digest, and several times that where the assembler
     lane is closed and the digest runs interpreted. -->

PostgreSQL's wire protocol (`sql/pg.x`), with no server: `canned-link` is the
harness's link whose server is the bytes a case spells in hex, and which
shows what is sent to it, a write a line after `sent`.  The bytes on both
sides, and the digests, were worked out apart from this bundle, by a
Python script with `struct` and `hashlib`; the SCRAM exchange is RFC
7677's own example.

## postgres starting

### the startup message names the protocol, the user, the database and the encoding

```x
(%seq (pg-start (canned-link "52000000080000000053000000187365727665725f76657273696f6e0031372e35004b0000000c00000001000000025a0000000549") "u" () "db") (display "ready") (newline))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
ready
```

### a password in the clear is sent when the server asks for one

```x
(%seq (pg-start (canned-link "5200000008000000035200000008000000005a0000000549") "u" "secret" "db") (display "ready") (newline))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
sent 700000000b73656372657400
ready
```

### by MD5 the password is digested with the user, and that with the salt, a NUL in it or not

```x
(%seq (pg-start (canned-link "520000000c00000005010003045200000008000000005a0000000549") "u" "secret" "db") (display "ready") (newline))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
sent 70000000286d6435366665656364653965663465646437376635373932356239326362643365636400
ready
```

### the digest by itself

```x
(%seq (display (pg-md5-password "u" "secret" (Bytes of-hex "01000304"))) (newline))
```
---
    md56feecde9ef4edd77f57925b92cbd3ecd

### a password asked for and not given

```x
(guard (e (%seq (display e) (newline))) (pg-start (canned-link "520000000800000003") "u" () "db"))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
Connection Error: the server asks for a password and none was given
```

### the server refusing is its error, as psql shows one

```x
(guard (e (%seq (display e) (newline))) (pg-start (canned-link "450000002c53464154414c00433238303030004d726f6c652022752220646f6573206e6f742065786973740000") "u" () "db"))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
FATAL:  role "u" does not exist
```

### an authentication that is not built is named by its code

```x
(guard (e (%seq (display e) (newline))) (pg-start (canned-link "520000000800000007") "u" "p" "db"))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
Connection Error: the server asks for an authentication that is not built, 7
```

## postgres scram

### RFC 7677's example: the client's proof and the signature the server must answer with

The key is derived in 4096 rounds, which is most of what this case costs.

```x
(let ((final (pg-scram-final "pencil" "n=user,r=rOprNGfwEbeRWgbNEkqO" "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"))) (%seq (display (first final)) (newline) (display (rest final)) (newline)))
```
---
```output
c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=
6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=
```

### a server's nonce that does not start with the client's is refused

```x
(guard (e (%seq (display e) (newline))) (pg-scram-final "pencil" "n=,r=abc" "r=xyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"))
```
---
    Protocol Error: the server's SCRAM message is not one

### the first message names no user: the startup message did

```x
(%seq (display (pg-scram-bare "abc")) (newline))
```
---
    n=,r=abc

## postgres queries

### rows come back as text, under the names and the types the server gives

```x
(%seq (display (sql-remote-text (sql-pg-results (pg-query (canned-link "5400000032000269640000000000000000000017ffffffffffff00006e616d650000000000000000000019ffffffffffff00004400000010000200000001310000000178440000000f00020000000132ffffffff430000000d53454c4543542032005a0000000549") "SELECT id, name FROM t")))))
```
---
```output
sent 510000001b53454c4543542069642c206e616d652046524f4d207400
┌──────┬──────┐
│  id  │ name │
│ int4 │ text │
├──────┼──────┤
│    1 │ x    │
│    2 │ NULL │
└──────┴──────┘
```

### the cells themselves: each its text and whether it is NULL

```x
(%seq (write (pg-query (canned-link "5400000032000269640000000000000000000017ffffffffffff00006e616d650000000000000000000019ffffffffffff00004400000010000200000001310000000178440000000f00020000000132ffffffff430000000d53454c4543542032005a0000000549") "q")) (newline))
```
---
```output
sent 51000000067100
((("id" "name") (23 25) ((("1" . #f) ("x" . #f)) (("2" . #f) ("NULL" . #t))) "SELECT 2"))
```

### a statement with no rows to show answers the server's word for what it did

```x
(%seq (display (sql-remote-text (sql-pg-results (pg-query (canned-link "4300000011435245415445205441424c45005a0000000549") "CREATE TABLE t (a int)")))))
```
---
```output
sent 510000001b435245415445205441424c45207420286120696e742900
CREATE TABLE
```

### a result with no rows is its heading and a count

```x
(%seq (display (sql-remote-text (sql-pg-results (pg-query (canned-link "540000001a00016e00000000000000000006a4ffffffffffff0000430000000d53454c4543542030005a0000000549") "q")))))
```
---
```output
sent 51000000067100
┌─────────┐
│    n    │
│ numeric │
└─────────┘
  0 rows 
```

### two statements in one text are two results, a notice shown where it came

```x
(%seq (display (sql-remote-text (sql-pg-results (pg-query (canned-link "4e00000031534e4f54494345004d7461626c652022742220646f6573206e6f742065786973742c20736b697070696e670000430000000f44524f50205441424c4500540000002100013f636f6c756d6e3f0000000000000000000017ffffffffffff0000440000000b00010000000131430000000d53454c4543542031005a0000000549") "q")))))
```
---
```output
sent 51000000067100
NOTICE:  table "t" does not exist, skipping
DROP TABLE
┌──────────┐
│ ?column? │
│   int4   │
├──────────┤
│        1 │
└──────────┘
```

### a type that is not listed is shown by its OID, its cells to the left

```x
(%seq (display (sql-remote-text (sql-pg-results (pg-query (canned-link "540000001a0001700000000000000000000258ffffffffffff0000440000000f00010000000528312c3229430000000d53454c4543542031005a0000000549") "q")))))
```
---
```output
sent 51000000067100
┌─────────┐
│    p    │
│ oid 600 │
├─────────┤
│ (1,2)   │
└─────────┘
```

### an error is the server's, with its detail and its hint, once the server is ready again

```x
(guard (e (%seq (display e) (newline))) (pg-query (canned-link "4500000068534552524f5200433432373033004d636f6c756d6e20226e616d2220646f6573206e6f7420657869737400485065726861707320796f75206d65616e7420746f207265666572656e63652074686520636f6c756d6e2022742e6e616d65222e00503800005a0000000549") "q"))
```
---
```output
sent 51000000067100
ERROR:  column "nam" does not exist
HINT:  Perhaps you meant to reference the column "t.name".
```

### a server that closes in the middle of an answer

```x
(guard (e (%seq (display e) (newline))) (pg-query (canned-link "540000001b00016964") "q"))
```
---
```output
sent 51000000067100
Connection Error: the server closed the connection
```

## postgres urls

`sql-url-parse` answers (USER PASSWORD HOST PORT DATABASE SCHEME).

### every part written

```x
(%seq (write (sql-url-parse "postgres://me:pw@db.example:5433/shop")) (newline))
```
---
    ("me" "pw" "db.example" 5433 "shop" "postgres")

### the port is PostgreSQL's and the database the user's name when not written

```x
(%seq (write (List drop 2 (sql-url-parse "postgresql://me@localhost"))) (newline))
```
---
    ("localhost" 5432 "me" "postgresql")

### what follows a question mark is not the database

```x
(%seq (write (List drop 2 (sql-url-parse "postgres://me@h/d?sslmode=disable"))) (newline))
```
---
    ("h" 5432 "d" "postgres")

### another scheme is refused

```x
(guard (e (%seq (display e) (newline))) (sql-url-parse "oracle://me@h/d"))
```
---
    Connection Error: not a postgres://, mysql:// or mariadb:// URL, oracle://me@h/d

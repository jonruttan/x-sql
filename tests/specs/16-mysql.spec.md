MySQL's wire protocol (`sql/my.x`), which MariaDB also speaks, with no
server: `canned-link` is the harness's link whose server is the bytes a
case spells in hex, and which shows what is sent to it, a write a line
after `sent`.  The bytes on both sides, and the digests, were worked out
apart from this bundle, by a Python script with `struct` and `hashlib`.

## mysql signing in

### the handshake is answered with the user, the database, the plugin the server named, and the password scrambled with its nonce

```x
(%seq (my-start (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264000700000200000002000000") "me" "secret" "shop") (display "ready") (newline))
```
---
```output
sent 530000010da20b00000000012d00000000000000000000000000000000000000000000006d650014b32bb3a583e1340c0a1108d58b1be49781ad8c2f73686f70006d7973716c5f6e61746976655f70617373776f726400
ready
```

### with no database none is named, and with no password nothing is sent for one

```x
(%seq (my-start (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264000700000200000002000000") "me" () ()) (display "ready") (newline))
```
---
```output
sent 3a00000105a20b00000000012d00000000000000000000000000000000000000000000006d6500006d7973716c5f6e61746976655f70617373776f726400
ready
```

### mysql_native_password by itself: SHA-1 of the password, and of the nonce with that digested again

```x
(%seq (display (Bytes hex (my-auth "mysql_native_password" "secret" (Bytes of-hex "0102030405060708090a0b0c0d0e0f1011121314")))) (newline))
```
---
    b32bb3a583e1340c0a1108d58b1be49781ad8c2f

### caching_sha2_password by itself: the same with SHA-256, the nonce last

```x
(%seq (display (Bytes hex (my-auth "caching_sha2_password" "secret" (Bytes of-hex "0102030405060708090a0b0c0d0e0f1011121314")))) (newline))
```
---
    746ebe205d56a0707acb3e796e834e0dd7b1d61743b26bd5202c7a623230c7c9

### a server that asks to sign in another way, with a nonce of its own, is answered that way

The 01 03 after it is caching_sha2_password saying the server had the
password cached and is satisfied.

```x
(%seq (my-start (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264002c000002fe63616368696e675f736861325f70617373776f72640065666768696a6b6c6d6e6f707172737475767778000200000401030700000500000002000000") "me" "secret" "shop") (display "ready") (newline))
```
---
```output
sent 530000010da20b00000000012d00000000000000000000000000000000000000000000006d650014b32bb3a583e1340c0a1108d58b1be49781ad8c2f73686f70006d7973716c5f6e61746976655f70617373776f726400
sent 200000032c1a320fc6146cf1498e533518f46a9f768afe92573087f4bbe5d156c9dcfe76
ready
```

### a server that wants the whole password is refused: that goes only over TLS or under its RSA key

```x
(guard (e (%seq (display e) (newline))) (my-start (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f10111213140063616368696e675f736861325f70617373776f726400020000020104") "me" "secret" ()))
```
---
```output
sent 5a00000105a20b00000000012d00000000000000000000000000000000000000000000006d650020746ebe205d56a0707acb3e796e834e0dd7b1d61743b26bd5202c7a623230c7c963616368696e675f736861325f70617373776f726400
Connection Error: the server wants the whole password, which goes only over TLS or under its RSA key, and neither is built
```

### a plugin that is not built is named

```x
(guard (e (%seq (display e) (newline))) (my-start (canned-link "4b0000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f101112131400636c69656e745f6564323535313900") "me" "secret" ()))
```
---
    Connection Error: the server asks for a sign-in that is not built, client_ed25519

### the server refusing is its error, as the mysql client shows one

```x
(guard (e (%seq (display e) (newline))) (my-start (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f72640046000002ff15042332383030304163636573732064656e69656420666f72207573657220276d652740276c6f63616c686f73742720287573696e672070617373776f72643a2059455329") "me" "wrong" ()))
```
---
```output
sent 4e00000105a20b00000000012d00000000000000000000000000000000000000000000006d65001465b3e85b5a5dccba358d2eaa785fee564f1c5e3b6d7973716c5f6e61746976655f70617373776f726400
ERROR 1045 (28000): Access denied for user 'me'@'localhost' (using password: YES)
```

### a server that refuses before its handshake

```x
(guard (e (%seq (display e) (newline))) (my-start (canned-link "43000000ff6a04486f7374202731302e302e302e3927206973206e6f7420616c6c6f77656420746f20636f6e6e65637420746f2074686973204d61726961444220736572766572") "me" () ()))
```
---
    ERROR 1130: Host '10.0.0.9' is not allowed to connect to this MariaDB server

## mysql queries

### rows come back as text, under the names and the types the server gives

```x
(%seq (display (sql-remote-text (my-query (canned-link "010000010320000002036465660473686f70017401740269640269640c3f000b00000003000000000024000003036465660473686f7001740174046e616d65046e616d650c2d000b000000fd000000000026000004036465660473686f70017401740570726963650570726963650c3f000b000000f6000000000005000005fe00000200090000060131017804392e3530040000070132fbfb05000008fe00000200") "SELECT * FROM t"))))
```
---
```output
sent 100000000353454c454354202a2046524f4d2074
┌─────┬─────────┬─────────┐
│ id  │  name   │  price  │
│ int │ varchar │ decimal │
├─────┼─────────┼─────────┤
│   1 │ x       │    9.50 │
│   2 │ NULL    │    NULL │
└─────┴─────────┴─────────┘
```

### the result itself: names, types, which are numbers, and each cell with whether it is NULL

```x
(%seq (write (my-query (canned-link "010000010320000002036465660473686f70017401740269640269640c3f000b00000003000000000024000003036465660473686f7001740174046e616d65046e616d650c2d000b000000fd000000000026000004036465660473686f70017401740570726963650570726963650c3f000b000000f6000000000005000005fe00000200090000060131017804392e3530040000070132fbfb05000008fe00000200") "q")) (newline))
```
---
```output
sent 020000000371
((("id" "name" "price") ("int" "varchar" "decimal") (#t #f #t) ((("1" . #f) ("x" . #f) ("9.50" . #f)) (("2" . #f) ("NULL" . #t) ("NULL" . #t))) ()))
```

### a statement with no rows to show answers what the mysql client says of it

```x
(%seq (display (sql-remote-text (my-query (canned-link "0700000100020002000000") "INSERT INTO t VALUES (1), (2)"))))
```
---
```output
sent 1e00000003494e5345525420494e544f20742056414c554553202831292c20283229
Query OK, 2 rows affected
```

### one row is one row

```x
(%seq (display (sql-remote-text (my-query (canned-link "0700000100010002000000") "q"))))
```
---
```output
sent 020000000371
Query OK, 1 row affected
```

### a result with no rows is its heading and a count

```x
(%seq (display (sql-remote-text (my-query (canned-link "01000001011e000002036465660473686f7001740174016e016e0c3f000b00000008000000000005000003fe0000020005000004fe00000200") "q"))))
```
---
```output
sent 020000000371
┌────────┐
│   n    │
│ bigint │
└────────┘
  0 rows
```

### two statements in one text are two results: the first says another follows

```x
(%seq (display (sql-remote-text (my-query (canned-link "01000001011e000002036465660473686f7001740174016101610c3f000b00000003000000000005000003fe0000020002000004013105000005fe00000a000700000600030002000000") "q"))))
```
---
```output
sent 020000000371
┌─────┐
│  a  │
│ int │
├─────┤
│   1 │
└─────┘
Query OK, 3 rows affected
```

### a text type whose character set is binary is the bytes type, and a type that is not listed is shown by its number

```x
(%seq (display (sql-remote-text (my-query (canned-link "01000001041e000002036465660473686f7001740174016201620c3f000b000000fc00000000001e000003036465660473686f7001740174016301630c2d000b000000fc00000000001e000004036465660473686f7001740174016401640c3f000b000000fe00000000001e000005036465660473686f7001740174016501650c2d000b000000c7000000000005000006fe000002000800000701780179017a017705000008fe00000200") "q"))))
```
---
```output
sent 020000000371
┌──────┬──────┬────────┬──────────┐
│  b   │  c   │   d    │    e     │
│ blob │ text │ binary │ type 199 │
├──────┼──────┼────────┼──────────┤
│ x    │ y    │ z      │ w        │
└──────┴──────┴────────┴──────────┘
```

### a value of more than 250 bytes has its length in two bytes

```x
(%seq (write (Str8 length (first (first (first (List ref 3 (first (my-query (canned-link "01000001011e000002036465660473686f7001740174017301730c2d000b000000fd000000000005000003fe000002002f010004fc2c0178787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787805000005fe00000200") "q")))))))) (newline))
```
---
```output
sent 020000000371
300
```

### an error is the server's, as the mysql client shows one

```x
(guard (e (%seq (display e) (newline))) (my-query (canned-link "28000001ff7a042334325330325461626c65202773686f702e6e6f70652720646f65736e2774206578697374") "q"))
```
---
```output
sent 020000000371
ERROR 1146 (42S02): Table 'shop.nope' doesn't exist
```

### a server that closes in the middle of an answer

```x
(guard (e (%seq (display e) (newline))) (my-query (canned-link "010000010320000002036465660473686f700174") "q"))
```
---
```output
sent 020000000371
Connection Error: the server closed the connection
```

## mysql urls

### mysql:// and mariadb:// name the same protocol: the port is 3306, and there is no database unless one is written

```x
(%seq (write (List drop 2 (sql-url-parse "mysql://me@db.example"))) (newline) (write (List drop 2 (sql-url-parse "mariadb://me:pw@h:3307/shop"))) (newline))
```
---
```output
("db.example" 3306 () "mysql")
("h" 3307 "shop" "mariadb")
```

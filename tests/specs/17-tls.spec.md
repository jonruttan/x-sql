How each protocol asks its server for TLS, with no server: the harness's
`canned-link` shows where TLS begins, with the name and whether the
certificate is to be checked, and what follows in the clear is what would
be inside.  A `/` in a link's hex parts what the server sends at one time
from what it sends at the next.  The bytes were worked out apart, in Python.  The handshake
itself is the platform's (`x/net/tls13`); `tests/oracle/` runs it against
real servers.

## tls postgres

### an SSLRequest goes first, and after the server's S everything is inside TLS

```x
(%seq (pg-start (canned-link "53/5200000008000000005a0000000549") "u" () "db" "require" "db.example") (display "ready") (newline))
```
---
```output
sent 0000000804d2162f
tls db.example unchecked
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
ready
```

### verify-full has the certificate checked for the server's name

```x
(guard (e (%seq (display e) (newline))) (pg-start (canned-link "53") "u" () "db" "verify-full" "db.example"))
```
---
```output
sent 0000000804d2162f
tls db.example checked
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
Connection Error: the server closed the connection
```

### prefer goes on in the clear when the server answers N

```x
(%seq (pg-start (canned-link "4e5200000008000000005a0000000549") "u" () "db" "prefer" "db.example") (display "ready") (newline))
```
---
```output
sent 0000000804d2162f
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
ready
```

### require does not

```x
(guard (e (%seq (display e) (newline))) (pg-start (canned-link "4e") "u" () "db" "require" "db.example"))
```
---
```output
sent 0000000804d2162f
Connection Error: the server does not take TLS, and sslmode asks for it
```

### disable asks nothing

```x
(%seq (pg-start (canned-link "5200000008000000005a0000000549") "u" () "db" "disable" "db.example") (display "ready") (newline))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
ready
```

### bytes sent ahead of the handshake are refused: they would be read as if encrypted

```x
(guard (e (%seq (display e) (newline))) (pg-start (canned-link "53520000000800000000") "u" () "db" "require" "db.example"))
```
---
```output
sent 0000000804d2162f
Connection Error: the server sent bytes before TLS began
```

## tls mysql

### after the handshake a short answer asks for TLS, and the full answer goes inside, one sequence number on

```x
(guard (e (%seq (display e) (newline))) (my-start (canned-link "490000000a382e342e300007000000010203040506070800ffff2d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f726400") "me" "secret" "shop" "require" "db.example"))
```
---
```output
sent 200000010daa0b00000000012d0000000000000000000000000000000000000000000000
tls db.example unchecked
sent 530000020daa0b00000000012d00000000000000000000000000000000000000000000006d650014b32bb3a583e1340c0a1108d58b1be49781ad8c2f73686f70006d7973716c5f6e61746976655f70617373776f726400
Connection Error: the server closed the connection
```

### prefer goes on in the clear when the server's handshake offers no TLS

```x
(%seq (my-start (canned-link "490000000a382e342e300007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264000700000200000002000000") "me" "secret" "shop" "prefer" "db.example") (display "ready") (newline))
```
---
```output
sent 530000010da20b00000000012d00000000000000000000000000000000000000000000006d650014b32bb3a583e1340c0a1108d58b1be49781ad8c2f73686f70006d7973716c5f6e61746976655f70617373776f726400
ready
```

### require does not

```x
(guard (e (%seq (display e) (newline))) (my-start (canned-link "490000000a382e342e300007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f726400") "me" "secret" "shop" "require" "db.example"))
```
---
    Connection Error: the server does not take TLS, and sslmode asks for it

### disable asks nothing though the server offers

```x
(%seq (my-start (canned-link "490000000a382e342e300007000000010203040506070800ffff2d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264000700000200000002000000") "me" "secret" "shop" "disable" "db.example") (display "ready") (newline))
```
---
```output
sent 530000010da20b00000000012d00000000000000000000000000000000000000000000006d650014b32bb3a583e1340c0a1108d58b1be49781ad8c2f73686f70006d7973716c5f6e61746976655f70617373776f726400
ready
```

## tls urls

### sslmode is read from what follows the question mark

```x
(%seq (write (List ref 6 (sql-url-parse "postgres://me@h/d?application_name=x&sslmode=require"))) (newline))
```
---
    "require"

### when nothing is said it is prefer

```x
(%seq (write (list (List ref 6 (sql-url-parse "postgres://me@h")) (List ref 6 (sql-url-parse "mysql://me@h")) (List ref 6 (sql-url-parse "mariadb://me@h")))) (newline))
```
---
    ("prefer" "prefer" "prefer")

### a mode there is not

```x
(guard (e (%seq (display e) (newline))) (sql-url-parse "postgres://me@h/d?sslmode=maybe"))
```
---
    Connection Error: sslmode is disable, prefer, require or verify-full, not maybe

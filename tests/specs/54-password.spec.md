# A password asked for at the terminal
# @weight 2

When the URL and the environment give no password and the server wants
one, `.connect` asks for it at the terminal, without showing it, and signs
in again (`lib/sql/base.x`).  `sql-session!` takes the two things that
needs: a function making a new link, and the asking itself, which is a
function of the address.  Here the links are `canned-link`s and the asking
is a function that says it was asked.  The bytes were worked out apart
from this bundle, by a Python script with `struct`.

psql asks the same way when the server wants a password; the mysql
client asks only when given -p.

## password postgres

### a server that asks for a password when none was given: it is asked for, and the session begins on a new link

```x
(%seq (write (sql-session! "postgres" (canned-link "520000000800000003") (list "u" () "db.example" 5432 "db" "postgres" "disable") (fn (_) (canned-link "5200000008000000035200000008000000005a0000000549")) (fn (_ at) (display (Str8 append "asked for " (first at) "@" (List third at))) (newline) "secret"))) (newline) (sql-disconnect!))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
asked for u@db.example
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
sent 700000000b73656372657400
"db@db.example"
sent 5800000004
```

### nothing typed for it: the server's own refusal

```x
(guard (e (%seq (display e) (newline))) (sql-session! "postgres" (canned-link "520000000800000003") (list "u" () "db.example" 5432 "db" "postgres" "disable") (fn (_) (canned-link "5200000008000000035200000008000000005a0000000549")) (fn (_ at) (display "asked") (newline) ())))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
asked
Connection Error: the server asks for a password and none was given
```

### without the two, nothing is asked

```x
(guard (e (%seq (display e) (newline))) (sql-session! "postgres" (canned-link "520000000800000003") (list "u" () "db.example" 5432 "db" "postgres" "disable")))
```
---
```output
sent 000000310003000075736572007500646174616261736500646200636c69656e745f656e636f64696e6700555446380000
Connection Error: the server asks for a password and none was given
```

## password mysql

### the empty password refused: one is asked for and sent on a new link

```x
(%seq (write (sql-session! "mysql" (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f72640045000002ff15042332383030304163636573732064656e69656420666f72207573657220276d652740276c6f63616c686f73742720287573696e672070617373776f72643a204e4f29") (list "me" () "shop.example" 3306 "shop" "mysql" "disable") (fn (_) (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264000700000200000002000000")) (fn (_ at) (display (Str8 append "asked for " (first at) "@" (List third at))) (newline) "secret"))) (newline) (sql-disconnect!))
```
---
```output
sent 3f0000010da20b00000000012d00000000000000000000000000000000000000000000006d65000073686f70006d7973716c5f6e61746976655f70617373776f726400
asked for me@shop.example
sent 530000010da20b00000000012d00000000000000000000000000000000000000000000006d650014b32bb3a583e1340c0a1108d58b1be49781ad8c2f73686f70006d7973716c5f6e61746976655f70617373776f726400
"shop@shop.example"
sent 0100000001
```

### a password that was given and refused is not asked for again

```x
(guard (e (%seq (display e) (newline))) (sql-session! "mysql" (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f72640045000002ff15042332383030304163636573732064656e69656420666f72207573657220276d652740276c6f63616c686f73742720287573696e672070617373776f72643a204e4f29") (list "me" "wrong" "shop.example" 3306 "shop" "mysql" "disable") (fn (_) (canned-link "520000000a31312e342e322d4d6172696144420007000000010203040506070800fff72d0200ff811500000000000000000000090a0b0c0d0e0f1011121314006d7973716c5f6e61746976655f70617373776f7264000700000200000002000000")) (fn (_ at) (display (Str8 append "asked for " (first at) "@" (List third at))) (newline) "secret")))
```
---
```output
sent 530000010da20b00000000012d00000000000000000000000000000000000000000000006d65001465b3e85b5a5dccba358d2eaa785fee564f1c5e3b73686f70006d7973716c5f6e61746976655f70617373776f726400
ERROR 1045 (28000): Access denied for user 'me'@'localhost' (using password: NO)
```

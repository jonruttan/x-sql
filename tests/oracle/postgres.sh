#!/bin/sh
# # x-sql -- SQL on x-lang
#
# ## tests/oracle/postgres.sh -- the driver against a real PostgreSQL
#
# @description Starts a PostgreSQL of its own in a scratch directory, with a
#   role for each way of signing in, runs `x -l sql` against it, and stops
#   it.  Not part of `make check`: it needs PostgreSQL's programs.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# Usage: X=/path/to/x.sh sh tests/oracle/postgres.sh
#
# PG_BIN names the directory of initdb, pg_ctl and psql when they are not on
# PATH.  The server listens on 127.0.0.1 only, on a port the kernel picked,
# with no unix socket and with TLS on, under a certificate it signs for
# itself; its passwords are made here, at random, and go with the
# directory.
set -e

BUNDLE="$(cd "$(dirname "$0")/../.." && pwd)"
X="${X:-x}"
PG_BIN="${PG_BIN:-$(dirname "$(command -v initdb || echo /nonexistent/initdb)")}"
[ -x "$PG_BIN/initdb" ] || {
	echo "postgres.sh: no initdb -- set PG_BIN to PostgreSQL's bin directory" >&2
	exit 2
}

# A checkout's x.sh finds its tree from the directory it is run in
case "$X" in
*/*) X_HOME="$(cd "$(dirname "$X")" && pwd)" ;;
*) X_HOME="$PWD" ;;
esac
LANGS="${X_LANG_DIR:-$(cd "$BUNDLE/.." && pwd)}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/x-sql-pg.XXXXXX")"
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
SECRET="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
FAILED=0

stop() {
	"$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
	rm -rf "$WORK"
}
trap stop EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' "$SECRET" > "$WORK/pw"
"$PG_BIN/initdb" -D "$WORK/data" -U boss --pwfile="$WORK/pw" --auth=scram-sha-256 >/dev/null
cat > "$WORK/data/pg_hba.conf" <<HBA
host all trusted 127.0.0.1/32 trust
host all clear   127.0.0.1/32 password
host all hashed  127.0.0.1/32 md5
host all all     127.0.0.1/32 scram-sha-256
HBA
# A certificate the server signs for itself: enough for TLS, and what
# verify-full must refuse
openssl req -new -x509 -days 2 -nodes -subj "/CN=localhost" \
	-keyout "$WORK/data/server.key" -out "$WORK/data/server.crt" >/dev/null 2>&1
chmod 600 "$WORK/data/server.key"
"$PG_BIN/pg_ctl" -D "$WORK/data" -l "$WORK/log" -w \
	-o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories='' -c ssl=on" start >/dev/null

PGPASSWORD="$SECRET" "$PG_BIN/psql" -q -h 127.0.0.1 -p "$PORT" -U boss -d postgres <<SQL
CREATE ROLE trusted LOGIN;
CREATE ROLE clear LOGIN PASSWORD '$SECRET';
SET password_encryption = 'md5';
CREATE ROLE hashed LOGIN PASSWORD '$SECRET';
CREATE DATABASE shop;
GRANT ALL ON DATABASE shop TO PUBLIC;
\c shop
GRANT ALL ON SCHEMA public TO PUBLIC;
SQL

# check NAME WANTED URL SQL...: the output of the statements holds WANTED
check() {
	name="$1"; wanted="$2"; url="$3"; shift 3
	set -- "$url" "$@"
	got="$(cd "$X_HOME" && X_LANG_DIR="$LANGS" NO_COLOR=1 "$X" -q -l sql -- "$@" 2>&1 </dev/null)" || true
	case "$got" in
	*"$wanted"*) echo "ok   $name" ;;
	*) echo "FAIL $name"; echo "  wanted: $wanted"; echo "$got" | sed 's/^/  got:    /'; FAILED=1 ;;
	esac
}

AT="127.0.0.1:$PORT/shop"
check "trust"                  "│    1 │" "postgres://trusted@$AT"          -c "SELECT 1 AS one"
check "password in the clear"  "│    1 │" "postgres://clear:$SECRET@$AT"    -c "SELECT 1 AS one"
check "md5"                    "│    1 │" "postgres://hashed:$SECRET@$AT"   -c "SELECT 1 AS one"
check "scram-sha-256"          "│    1 │" "postgres://boss:$SECRET@$AT"     -c "SELECT 1 AS one"
check "a wrong password"       'FATAL:  password authentication failed for user "boss"' \
	"postgres://boss:wrong@$AT" -c "SELECT 1"
check "a role there is not"    "FATAL:" "postgres://nobody:x@$AT" -c "SELECT 1"
check "a database there is not" 'FATAL:  database "nope" does not exist' \
	"postgres://trusted@127.0.0.1:$PORT/nope" -c "SELECT 1"
check "values as the server writes them"       "│    1 │ x    │    1.50 │ t    │    0.1 │" "postgres://trusted@$AT" \
	-c "SELECT 1 AS a, 'x'::text AS b, 1.50::numeric AS c, true AS d, 0.1::float8 AS e"
check "the types' names"       "│ int4 │ text │ numeric │ bool │ float8 │" "postgres://trusted@$AT" \
	-c "SELECT 1 AS a, 'x'::text AS b, 1.50::numeric AS c, true AS d, 0.1::float8 AS e"
check "a NULL"                 "│ NULL │" "postgres://trusted@$AT" -c "SELECT NULL::int AS n"
check "statements keep a session" "│    3 │" "postgres://trusted@$AT" \
	-c "CREATE TEMP TABLE t (a int, b text)" \
	-c "INSERT INTO t VALUES (1, 'one'), (2, 'two'), (3, NULL)" \
	-c "SELECT max(a) AS top FROM t"
check "the server's word"      "INSERT 0 2" "postgres://trusted@$AT" \
	-c "CREATE TEMP TABLE t (a int); INSERT INTO t VALUES (1), (2)"
check "the server's error"     'ERROR:  relation "nope" does not exist' "postgres://trusted@$AT" -c "SELECT * FROM nope"
check "a notice"               'NOTICE:  table "nope" does not exist, skipping' "postgres://trusted@$AT" \
	-c "DROP TABLE IF EXISTS nope"
check "many rows"              "│ 5000 │" "postgres://trusted@$AT" -c "SELECT g FROM generate_series(1, 5000) g"
check "text of more than one byte a letter" "│ héllo │" "postgres://trusted@$AT" -c "SELECT 'héllo' AS s"

SSL="SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()"
check "TLS when the server has it" "│ t    │ TLSv1.3 │" "postgres://trusted@$AT" -c "$SSL"
check "sslmode=require"        "│ t    │ TLSv1.3 │" "postgres://trusted@$AT?sslmode=require" -c "$SSL"
check "sslmode=disable"        "│ f    │ NULL    │" "postgres://trusted@$AT?sslmode=disable" -c "$SSL"
check "scram-sha-256 over TLS" "│ t    │ TLSv1.3 │" "postgres://boss:$SECRET@$AT?sslmode=require" -c "$SSL"
check "many rows over TLS"     "│ 5000 │" "postgres://trusted@$AT?sslmode=require" -c "SELECT g FROM generate_series(1, 5000) g"
check "verify-full refuses a certificate the server signed for itself" "Tls13: X509:" \
	"postgres://trusted@$AT?sslmode=verify-full" -c "$SSL"

exit "$FAILED"

#!/bin/sh
# # x-sql -- SQL on x-lang
#
# ## tests/oracle/mariadb.sh -- the driver against a real MariaDB
#
# @description Starts a MariaDB of its own in a scratch directory, with a
#   user for each way of signing in, runs `x -l sql` against it, and stops
#   it.  Not part of `make check`: it needs MariaDB's programs.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# Usage: X=/path/to/x.sh sh tests/oracle/mariadb.sh
#
# MY_BIN names the directory of mariadb-install-db, mariadbd and mariadb
# when they are not on PATH.  The server listens on 127.0.0.1 only, on a
# port the kernel picked; its password is made here, at random, and goes
# with the directory.  The unix socket the setup uses is in /tmp, where its
# path is short enough to be one.
set -e

BUNDLE="$(cd "$(dirname "$0")/../.." && pwd)"
X="${X:-x}"
MY_BIN="${MY_BIN:-$(dirname "$(command -v mariadbd || echo /nonexistent/mariadbd)")}"
[ -x "$MY_BIN/mariadbd" ] || {
	echo "mariadb.sh: no mariadbd -- set MY_BIN to MariaDB's bin directory" >&2
	exit 2
}

# A checkout's x.sh finds its tree from the directory it is run in
case "$X" in
*/*) X_HOME="$(cd "$(dirname "$X")" && pwd)" ;;
*) X_HOME="$PWD" ;;
esac
LANGS="${X_LANG_DIR:-$(cd "$BUNDLE/.." && pwd)}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/x-sql-my.XXXXXX")"
SOCK="/tmp/x-sql-my.$$.sock"
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
SECRET="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
SERVER=""
FAILED=0

stop() {
	if [ -n "$SERVER" ]; then
		kill "$SERVER" 2>/dev/null || true
		wait "$SERVER" 2>/dev/null || true
	fi
	rm -rf "$WORK" "$SOCK"
}
trap stop EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$MY_BIN/mariadb-install-db" --datadir="$WORK/data" \
	--auth-root-authentication-method=normal >"$WORK/install.log" 2>&1
"$MY_BIN/mariadbd" --no-defaults --datadir="$WORK/data" --port="$PORT" \
	--bind-address=127.0.0.1 --socket="$SOCK" --pid-file="$WORK/pid" \
	--log-error="$WORK/log" &
SERVER=$!

# The server is up when its socket answers
tries=0
until "$MY_BIN/mariadb" --no-defaults --socket="$SOCK" -u root -e "SELECT 1" >/dev/null 2>&1; do
	tries=$((tries + 1))
	[ "$tries" -lt 60 ] || { echo "mariadb.sh: the server did not start" >&2; cat "$WORK/log" >&2; exit 1; }
	sleep 1
done

# The anonymous users a fresh MariaDB has would be signed in to ahead of a
# user named for any host, so they go first
"$MY_BIN/mariadb" --no-defaults --socket="$SOCK" -u root <<SQL
DELETE FROM mysql.global_priv WHERE User = '';
FLUSH PRIVILEGES;
CREATE USER 'open'@'%';
CREATE USER 'hashed'@'%' IDENTIFIED BY '$SECRET';
CREATE DATABASE shop;
GRANT ALL ON shop.* TO 'open'@'%';
GRANT ALL ON shop.* TO 'hashed'@'%';
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
check "no password"            "│   1 │" "mariadb://open@$AT"            -c "SELECT 1 AS one"
check "mysql_native_password"  "│   1 │" "mysql://hashed:$SECRET@$AT"    -c "SELECT 1 AS one"
check "no database"            "│ NULL    │" "mysql://open@127.0.0.1:$PORT"  -c "SELECT database() AS d"
check "a wrong password"       "ERROR 1045 (28000): Access denied for user 'hashed'@" \
	"mysql://hashed:wrong@$AT" -c "SELECT 1"
check "a database there is not" "ERROR 1044 (42000): Access denied for user 'open'@" \
	"mysql://open@127.0.0.1:$PORT/nope" -c "SELECT 1"
check "the types' names"       "│ int │ varchar │ decimal │ double │    date    │" "mysql://open@$AT" \
	-c "SELECT 1 AS a, 'x' AS b, 1.50 AS c, 1e0 AS d, DATE '2026-11-17' AS e"
check "values as the server writes them" "│   1 │ x       │    1.50 │      1 │ 2026-11-17 │" "mysql://open@$AT" \
	-c "SELECT 1 AS a, 'x' AS b, 1.50 AS c, 1e0 AS d, DATE '2026-11-17' AS e"
check "a NULL"                 "│ NULL │" "mysql://open@$AT" -c "SELECT NULL AS n"
check "statements keep a session" "│   3 │" "mysql://open@$AT" \
	-c "CREATE TEMPORARY TABLE t (a INT, b TEXT)" \
	-c "INSERT INTO t VALUES (1, 'one'), (2, 'two'), (3, NULL)" \
	-c "SELECT max(a) AS top FROM t"
check "what the client says"   "Query OK, 2 rows affected" "mysql://open@$AT" \
	-c "CREATE TEMPORARY TABLE t (a INT)" -c "INSERT INTO t VALUES (1), (2)"
check "two statements in one text" "│   2 │" "mysql://open@$AT" -c "SELECT 1 AS a; SELECT 2 AS b"
check "the server's error"     "ERROR 1146 (42S02): Table 'shop.nope' doesn't exist" "mysql://open@$AT" -c "SELECT * FROM nope"
check "many rows"              "│   5000 │" "mysql://open@$AT" -c "SELECT seq FROM seq_1_to_5000"
check "text of more than one byte a letter" "│ héllo   │" "mysql://open@$AT" -c "SELECT 'héllo' AS s"

exit "$FAILED"

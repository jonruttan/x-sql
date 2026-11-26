#!/bin/sh
# tests/card-run.sh FILE -- run one program of docs/card.md, for the bundle
# kit's card check.  X is the x under test.
#
# FILE is run as `x -l sql -f FILE`, from the project's root.  A result's
# box is taken off: each of its rows is one line, the values as the box
# shows them with ` | ` between.  Any other line is printed as it is.
"${X:-x}" -l sql -f "$1" < /dev/null | LC_ALL=C awk '
/^├/ { rows = 1; next }
/^└/ { rows = 0; next }
/^┌/ { next }
/^│/ {
	if (!rows) next
	sub(/^│ */, "")
	sub(/ *│$/, "")
	gsub(/ *│ */, " | ")
	print
	next
}
{ print }'

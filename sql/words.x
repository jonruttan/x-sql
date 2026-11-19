; # x-sql -- SQL on x-lang
;
; ## sql/words.x -- the words the reader and the parser share
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A reserved word is a keyword wherever it stands, in any case, and is an
; identifier only inside double quotes.  Every other word is an identifier
; the parser may read as a keyword where the grammar asks for one.

(module sql/words)
(import x/type/str)
(import x/type/dict)

; A name in one case, each distinct spelling folded once: the platform's
; case conversion costs thousands of objects a word, and a name is
; compared for every column of every row
(def %sql-lowered (Dict make))
(def %sql-uppered (Dict make))

(def sql-lower
  (fn (_ text)
    (unless (%sql-lowered has? text) (%sql-lowered set! text (Str8 downcase text)))
    (%sql-lowered get text)))

(def sql-upper
  (fn (_ text)
    (unless (%sql-uppered has? text) (%sql-uppered set! text (Str8 upcase text)))
    (%sql-uppered get text)))

; Two names are one, whatever their case
(def sql-same-name?
  (fn (_ a b) (str=? (sql-lower a) (sql-lower b))))

(def sql-reserved
  (list "SELECT" "FROM" "WHERE" "AS" "AND" "OR" "NOT" "IS" "NULL" "TRUE"
        "FALSE" "GROUP" "ORDER" "HAVING" "LIMIT" "OFFSET" "UNION" "EXCEPT"
        "INTERSECT" "ON" "USING" "JOIN" "CASE" "WHEN" "THEN" "ELSE" "END"
        "IN" "DISTINCT" "ALL" "CREATE" "TABLE" "INTO" "WITH" "INNER" "LEFT"
        "RIGHT" "FULL" "CROSS" "OUTER" "NATURAL" "BETWEEN" "LIKE" "ILIKE"
        "QUALIFY" "WINDOW"))

; The words the parser reads where the grammar asks for them and that are
; names everywhere else
(def sql-words
  (list "INSERT" "VALUES" "DROP" "BY" "ASC" "DESC" "NULLS" "FIRST" "LAST"
        "CAST" "REPLACE" "IF" "EXISTS" "UPDATE" "SET" "DELETE" "COPY" "TO"
        "FORMAT" "HEADER" "INTERVAL" "EXTRACT" "OVER" "PARTITION" "ROWS"
        "UNBOUNDED" "PRECEDING" "FOLLOWING" "CURRENT" "ROW" "RANGE" "GROUPS"
        "EXCLUDE" "TIES" "RECURSIVE" "RENAME"))

; The functions that answer for a row among its window's rows, and are
; nothing without an OVER
(def sql-window-functions
  (list "row_number" "rank" "dense_rank" "percent_rank" "cume_dist" "ntile"
        "lag" "lead" "first_value" "last_value" "nth_value"))

; The functions that read a file as a table, and the format each reads it
; as: nil for the one its name's ending says
(def sql-file-functions
  (list (list "read_csv" "csv") (list "read_csv_auto" "csv")
        (list "read_json" "json") (list "read_json_auto" "json")
        (list "read_ndjson" "json")))

; The reserved words that are values
(def sql-constants (list "TRUE" "FALSE" "NULL"))

; Longest first where one operator starts another: the Lexer's table takes
; the longest literal present.
(def sql-ops
  (list "(" ")" "," ";" "." "+" "-" "*" "/" "//" "%" "||" "=" "==" "<>"
        "!=" "<" "<=" ">" ">=" "::" "[" "]" "{" "}" ":" "**" "^"))

; A binary operator as written, the name the evaluator knows it by, and how
; a column heading spells it.
(def sql-binary-ops
  (list (list "+" (lit add) "+") (list "-" (lit sub) "-")
        (list "*" (lit mul) "*") (list "/" (lit div) "/")
        (list "//" (lit idiv) "//") (list "%" (lit mod) "%")
        (list "||" (lit concat) "||")
        (list "=" (lit eq) "=") (list "==" (lit eq) "=")
        (list "<>" (lit ne) "!=") (list "!=" (lit ne) "!=")
        (list "<" (lit lt) "<") (list "<=" (lit le) "<=")
        (list ">" (lit gt) ">") (list ">=" (lit ge) ">=")))

; A type as written, upper case, the type it names, and how a heading
; spells it: nil for as it was written, which is how DuckDB heads a name
; its grammar does not know as a keyword.  DECIMAL and NUMERIC name a type
; only with their width and scale, which the parser reads.
(def sql-type-words
  (list (list "INTEGER" (lit integer) "INTEGER") (list "INT" (lit integer) "INTEGER")
        (list "INT4" (lit integer) ()) (list "SIGNED" (lit integer) ())
        (list "BIGINT" (lit bigint) "BIGINT") (list "INT8" (lit bigint) ())
        (list "LONG" (lit bigint) ())
        (list "HUGEINT" (lit hugeint) ())
        (list "UTINYINT" (lit utinyint) ()) (list "UINT8" (lit utinyint) ())
        (list "USMALLINT" (lit usmallint) ()) (list "UINT16" (lit usmallint) ())
        (list "UINTEGER" (lit uinteger) ()) (list "UINT32" (lit uinteger) ())
        (list "UBIGINT" (lit ubigint) ()) (list "UINT64" (lit ubigint) ())
        (list "UHUGEINT" (lit uhugeint) ()) (list "UINT128" (lit uhugeint) ())
        (list "TINYINT" (lit tinyint) "TINYINT") (list "INT1" (lit tinyint) ())
        (list "SMALLINT" (lit smallint) "SMALLINT") (list "INT2" (lit smallint) ())
        (list "SHORT" (lit smallint) ())
        (list "REAL" (lit real) "FLOAT") (list "FLOAT" (lit real) "FLOAT")
        (list "FLOAT4" (lit real) ())
        (list "VARCHAR" (lit varchar) "VARCHAR") (list "CHAR" (lit varchar) "VARCHAR")
        (list "TEXT" (lit varchar) ()) (list "STRING" (lit varchar) ())
        (list "BPCHAR" (lit varchar) ())
        (list "BOOLEAN" (lit boolean) "BOOLEAN") (list "BOOL" (lit boolean) ())
        (list "LOGICAL" (lit boolean) ())
        (list "DOUBLE" (lit double) ()) (list "FLOAT8" (lit double) ())
        (list "DECIMAL" (lit decimal) "DECIMAL") (list "NUMERIC" (lit decimal) "DECIMAL")
        (list "DATE" (lit date) "DATE") (list "TIME" (lit time) "TIME")
        (list "TIMESTAMP" (lit timestamp) "TIMESTAMP") (list "DATETIME" (lit timestamp) ())
        (list "TIMESTAMPTZ" (lit timestamptz) ())
        (list "INTERVAL" (lit interval) "INTERVAL")))

; The functions that answer one value for a group of rows
; DuckDB's keywords, every category of them, as duckdb_keywords() lists
; them in 2.0.0.  A struct's field named by one is in double quotes in the
; struct's type.
(def sql-keywords
  (list "abort" "absolute" "access" "action" "add" "admin" "after" "aggregate" "all"
        "also" "alter" "always" "analyse" "analyze" "and" "anti" "any" "approx"
        "array" "as" "asc" "asof" "assertion" "assignment" "asymmetric" "at"
        "attach" "attribute" "authorization" "backward" "before" "begin" "between"
        "bigint" "binary" "bit" "boolean" "both" "by" "cache" "call" "called"
        "cascade" "cascaded" "case" "cast" "catalog" "centuries" "century" "chain"
        "char" "character" "characteristics" "check" "checkpoint" "class" "close"
        "cluster" "coalesce" "collate" "collation" "column" "columns" "columns"
        "comment" "comments" "commit" "committed" "compression" "concurrently"
        "configuration" "conflict" "connect" "connection" "constraint" "constraints"
        "content" "continue" "conversion" "copy" "cost" "create" "cross" "csv"
        "cube" "current" "cursor" "cycle" "data" "database" "day" "days"
        "deallocate" "dec" "decade" "decades" "decimal" "declare" "default"
        "defaults" "deferrable" "deferred" "definer" "delete" "delimiter"
        "delimiters" "depends" "desc" "describe" "destroy" "detach" "dictionary"
        "disable" "discard" "disconnect" "distance" "distinct" "do" "document"
        "domain" "double" "drop" "each" "else" "enable" "encoding" "encrypted" "end"
        "enum" "error" "escape" "event" "exact" "except" "exclude" "excluding"
        "exclusive" "execute" "exists" "explain" "export" "export_state" "extension"
        "extensions" "external" "extract" "false" "family" "fetch" "filter" "first"
        "float" "following" "for" "force" "foreign" "forward" "freeze" "from" "full"
        "function" "functions" "generated" "generated" "glob" "global" "grant"
        "granted" "group" "grouping" "grouping_id" "groups" "handler" "having"
        "header" "hold" "hour" "hours" "identity" "if" "ignore" "ilike" "immediate"
        "immutable" "implicit" "import" "in" "include" "including" "increment"
        "index" "indexes" "inherit" "inherits" "initially" "inline" "inner" "inout"
        "input" "insensitive" "insert" "install" "instead" "int" "integer"
        "intersect" "interval" "into" "invoker" "is" "isnull" "isolation" "join"
        "json" "key" "label" "lambda" "language" "large" "last" "lateral" "leading"
        "leakproof" "left" "level" "like" "limit" "listen" "load" "local" "location"
        "lock" "locked" "logged" "macro" "map" "map" "mapping" "match" "matched"
        "materialized" "maxvalue" "merge" "method" "microsecond" "microseconds"
        "millennia" "millennium" "millisecond" "milliseconds" "minute" "minutes"
        "minvalue" "mode" "month" "months" "move" "name" "names" "national"
        "natural" "nchar" "nearest" "new" "next" "no" "none" "not" "nothing"
        "notify" "notnull" "nowait" "null" "nullif" "nulls" "numeric" "object" "of"
        "off" "offset" "oids" "old" "on" "only" "operator" "option" "options" "or"
        "order" "ordinality" "others" "out" "outer" "over" "overlaps" "overlay"
        "overriding" "owned" "owner" "parallel" "parser" "partial" "partition"
        "partitioned" "passing" "password" "percent" "persistent" "pivot"
        "pivot_longer" "pivot_wider" "placing" "plans" "policy" "position"
        "positional" "pragma" "preceding" "precision" "prepare" "prepared"
        "preserve" "primary" "prior" "privileges" "procedural" "procedure" "program"
        "publication" "qualify" "quarter" "quarters" "quote" "range" "read" "real"
        "reassign" "recheck" "recursive" "ref" "references" "referencing" "refresh"
        "register" "reindex" "relative" "release" "rename" "repeatable" "replace"
        "replica" "reset" "resource" "resources" "respect" "restart" "restrict"
        "returning" "returns" "revoke" "right" "role" "rollback" "rollup" "row"
        "rows" "rule" "sample" "savepoint" "schema" "schemas" "scope" "scroll"
        "search" "second" "seconds" "secret" "secure" "security" "select" "semi"
        "sequence" "sequences" "serializable" "server" "session" "set" "setof"
        "sets" "share" "show" "similar" "similarity" "simple" "skip" "smallint"
        "snapshot" "some" "sorted" "source" "sql" "stable" "standalone" "start"
        "statement" "statistics" "stdin" "stdout" "storage" "stored" "strict"
        "strip" "struct" "struct" "subscription" "substring" "summarize" "symmetric"
        "sysid" "system" "table" "tables" "tablesample" "tablespace" "target" "temp"
        "template" "temporary" "text" "then" "ties" "time" "timestamp" "to"
        "trailing" "transaction" "transform" "treat" "trigger" "trim" "true"
        "truncate" "trusted" "try_cast" "try_cast" "tuple" "tuple" "type" "types"
        "unbounded" "uncommitted" "unencrypted" "union" "unique" "unknown"
        "unlisten" "unlogged" "unpack" "unpivot" "until" "update" "use" "user"
        "using" "vacuum" "valid" "validate" "validator" "value" "values" "varchar"
        "variable" "variadic" "varying" "verbose" "version" "view" "views" "virtual"
        "volatile" "week" "weeks" "when" "where" "whitespace" "window" "with"
        "within" "without" "work" "wrapper" "write" "xml" "xmlattributes"
        "xmlconcat" "xmlelement" "xmlexists" "xmlforest" "xmlnamespaces" "xmlparse"
        "xmlpi" "xmlroot" "xmlserialize" "xmltable" "year" "years" "yes" "zone"))

(def sql-aggregates (list "count" "sum" "min" "max" "avg" "list" "array_agg"))

(provide sql/words
  sql-lower sql-upper sql-same-name? sql-reserved sql-words sql-constants sql-ops sql-binary-ops sql-type-words
  sql-aggregates sql-window-functions sql-file-functions sql-keywords)

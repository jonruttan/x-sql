#!/bin/sh
# # x-sql -- SQL on x-lang
#
# ## tests/fixtures/make-shop.sh -- the SQLite database the specs read
#
# @description Writes tests/fixtures/shop.sqlite3 with the sqlite3 tool: a
#   small shop of several tables, with what a reader of the file format has
#   to get right in it.  The file is kept in the repository; this is how it
#   was made, and how to make it again when a case needs more in it.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# Usage: sh tests/fixtures/make-shop.sh
#
# What is in it, and why:
#   customers     declared types of every affinity, NULLs, an empty text,
#                 text of more than one byte a letter, a UNIQUE column
#   products      WITHOUT ROWID: its rows are in an index b-tree
#   shelves       WITHOUT ROWID with a key of two columns that are not its
#                 first, and rows enough for an interior page of the index
#   orders        a foreign key, an index on it, timestamps, deleted rows
#   order_lines   a primary key of two columns
#   measurements  four hundred rows: an interior page above the leaves
#   documents     a text too long for its page: overflow pages
#   loose         columns with no declared type, values of every class
#   files         a BLOB column: no bytes, a zero byte, bytes above 127,
#                 a NULL, and a text and a number kept in it
#   big_spenders  a view
#   order_totals  a view that names its columns, over a join and groups
#   shouted       a view of a view
set -e

cd "$(dirname "$0")"
OUT=shop.sqlite3
rm -f "$OUT"

sqlite3 "$OUT" <<'SQL'
PRAGMA page_size = 512;
PRAGMA journal_mode = DELETE;

CREATE TABLE customers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email VARCHAR(80) UNIQUE,
  joined DATE,
  vip BOOLEAN DEFAULT 0,
  balance DECIMAL(8,2)
);
INSERT INTO customers VALUES
  (1, 'Ida', 'ida@example.com', '2024-03-04', 1, 120.50),
  (2, 'Bo', NULL, '2023-11-30', 0, 0),
  (3, 'Zoë', 'zoe@example.com', NULL, 1, -15.25),
  (4, '', 'none@example.com', '2025-01-01', 0, NULL),
  (5, 'Åsa Öberg', 'asa@example.com', '2022-06-15', 1, 99999.99);

CREATE TABLE products (
  sku TEXT PRIMARY KEY,
  title TEXT,
  price REAL,
  stock INT
) WITHOUT ROWID;
INSERT INTO products VALUES
  ('A-1', 'Anvil', 49.5, 3),
  ('B-2', 'Bellows', 12.0, 0),
  ('C-3', 'Chisel', 7.25, 40);

CREATE TABLE shelves (
  note TEXT,
  place INT,
  sku TEXT,
  held INT,
  PRIMARY KEY (sku, place)
) WITHOUT ROWID;
WITH RECURSIVE count(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM count WHERE i < 120)
INSERT INTO shelves
  SELECT 'shelf ' || i || ' of the back room, counted twice',
         i, CASE i % 3 WHEN 0 THEN 'A-1' WHEN 1 THEN 'B-2' ELSE 'C-3' END, i * 2
  FROM count;

CREATE TABLE orders (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER REFERENCES customers (id),
  placed TIMESTAMP,
  note TEXT
);
CREATE INDEX orders_by_customer ON orders (customer_id);
INSERT INTO orders VALUES
  (10, 1, '2025-02-01 09:30:00', 'first'),
  (11, 1, '2025-02-03 17:45:10', NULL),
  (12, 3, '2025-02-04 08:00:00', 'gift'),
  (13, 2, '2025-02-05 12:00:00', 'cancelled'),
  (14, 5, '2025-02-06 23:59:59', 'late'),
  (15, 2, '2025-02-07 00:00:00', 'cancelled too');
DELETE FROM orders WHERE note LIKE 'cancelled%';

CREATE TABLE order_lines (
  order_id INT,
  sku TEXT,
  qty INT,
  PRIMARY KEY (order_id, sku)
);
INSERT INTO order_lines VALUES
  (10, 'A-1', 1), (10, 'C-3', 4), (11, 'B-2', 2), (12, 'C-3', 1), (14, 'A-1', 2);

CREATE TABLE measurements (
  n INTEGER PRIMARY KEY,
  reading REAL,
  label TEXT
);
WITH RECURSIVE count(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM count WHERE i < 400)
INSERT INTO measurements SELECT i, i * 0.5, 'reading ' || i FROM count;

CREATE TABLE documents (
  id INTEGER PRIMARY KEY,
  title TEXT,
  body TEXT
);
INSERT INTO documents VALUES
  (1, 'short', 'a few words'),
  (2, 'long', (SELECT group_concat('line ' || n, char(10)) FROM measurements WHERE n <= 400));

CREATE TABLE loose (a, b);
INSERT INTO loose VALUES
  (1, 'one'), (2.5, 'two and a half'), ('three', 3), (NULL, NULL),
  (0, 1), (-1, 127), (128, 32767), (32768, 8388607), (8388608, 2147483647),
  (2147483648, 140737488355327), (140737488355328, 9223372036854775807);

CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  name TEXT,
  body BLOB
);
INSERT INTO files VALUES
  (1, 'empty', x''),
  (2, 'text', x'68656C6C6F'),
  (3, 'bytes', x'00FF10275C22'),
  (4, 'none', NULL),
  (5, 'kept as text', 'plain'),
  (6, 'kept as a number', 42);

CREATE VIEW big_spenders AS SELECT name FROM customers WHERE balance > 100;
CREATE VIEW order_totals (customer, orders, pieces) AS
  SELECT c.name, count(DISTINCT o.id), sum(l.qty)
  FROM customers c
  JOIN orders o ON o.customer_id = c.id
  JOIN order_lines l ON l.order_id = o.id
  GROUP BY c.name;
CREATE VIEW shouted AS SELECT upper(name) AS loud FROM big_spenders;
SQL

echo "$OUT: $(wc -c < "$OUT") bytes"

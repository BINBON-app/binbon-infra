#!/usr/bin/env python3
"""Split a .sql file into individual statements, stripping -- comments.

Used by apply_clickhouse_migrations.yml so each statement can be POSTed to
ClickHouse's HTTP interface separately (it only executes one query per
request). Prints a JSON array of statements to stdout, in file order, so
CREATE TABLE / CREATE VIEW dependency order is preserved.
"""
import json
import re
import sys


def main(path: str) -> None:
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"--[^\n]*", "", text)
    statements = [s.strip() for s in text.split(";")]
    statements = [s for s in statements if s]
    print(json.dumps(statements))


if __name__ == "__main__":
    main(sys.argv[1])

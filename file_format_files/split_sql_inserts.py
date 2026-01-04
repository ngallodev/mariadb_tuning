#!/usr/bin/env python3
"""
Split a SQL dump into individual INSERT statements.

This reads a dump file containing lines such as:
    INSERT INTO `table` VALUES (...),(...);

Each INSERT statement is extracted and written to its own file inside the
output directory. Files are named <table>_insert_<NNNNN>.sql to make them
easy to feed into downstream converters (e.g. convert_parenthesized_sql_to_tab.py).

Usage:
    python split_sql_inserts.py SOURCE.sql OUTPUT_DIR
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


INSERT_RE = re.compile(r"INSERT\s+INTO\s+`?([^`(\s]+)`?\s+", re.IGNORECASE)


def iter_statements(stream):
    """Yield SQL statements terminated with a semicolon, keeping track of quotes."""
    buffer = []
    in_string = False
    escape = False

    while True:
        chunk = stream.read(8192)
        if not chunk:
            break

        for ch in chunk:
            buffer.append(ch)

            if escape:
                escape = False
                continue

            if ch == "\\":
                escape = True
                continue

            if ch == "'":
                in_string = not in_string
                continue

            if ch == ";" and not in_string:
                stmt = "".join(buffer).strip()
                if stmt:
                    yield stmt
                buffer.clear()

    # Flush any trailing content (in case file lacks final semicolon)
    tail = "".join(buffer).strip()
    if tail:
        yield tail


def split_inserts(source: Path, dest_dir: Path) -> None:
    dest_dir.mkdir(parents=True, exist_ok=True)

    counters = {}

    with source.open("r", encoding="utf-8", errors="ignore") as fh:
        for statement in iter_statements(fh):
            match = INSERT_RE.match(statement)
            if not match:
                continue

            table = match.group(1)
            counters.setdefault(table, 0)
            counters[table] += 1

            filename = f"{table}_insert_{counters[table]:05d}.sql"
            out_path = dest_dir / filename
            out_path.write_text(statement + ";\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Split SQL dump into per-INSERT files.")
    parser.add_argument("source", type=Path, help="Path to the .sql dump")
    parser.add_argument("output_dir", type=Path, help="Directory to store INSERT files")
    args = parser.parse_args()

    if not args.source.is_file():
        raise SystemExit(f"Source file not found: {args.source}")

    split_inserts(args.source, args.output_dir)


if __name__ == "__main__":
    main()

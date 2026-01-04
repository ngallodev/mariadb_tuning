#!/usr/bin/env python3
"""Stage 1: Peel value tuples out of large INSERT statements.

Goal
====
Transform a raw SQL dump file that looks like:

    INSERT INTO `users` VALUES (....),(....),(...);

into a plain text file where each line is the payload from a single tuple:

    1,'user@example.com','2003-04-08 17:49:56',0,...
    2,'user2@example.com','2003-04-08 18:06:13',0,...

Inputs / Outputs
================
* Input:  SQL dump containing one or more multi-row INSERT statements.
* Output: Text file with one comma-delimited tuple payload per line.

Why
===
Downstream cleaning steps operate on individual records.  Breaking the dump into
one tuple per line makes later processing deterministic and avoids having to
re-parse the full INSERT syntax repeatedly.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterator, Optional


def statement_complete(payload: str) -> bool:
    """Return True when a VALUES payload contains a terminating semicolon.

    The function walks the string while honoring single-quoted literals so that
    embedded semicolons inside quotes do not incorrectly terminate the scan.
    """
    in_quote = False
    escape = False
    length = len(payload)
    i = 0

    while i < length:
        ch = payload[i]
        if in_quote:
            if escape:
                escape = False
                i += 1
                continue
            if ch == "\\":
                escape = True
                i += 1
                continue
            if ch == "'" and i + 1 < length and payload[i + 1] == "'":
                i += 2
                continue
            if ch == "'":
                in_quote = False
                i += 1
                continue
            i += 1
            continue

        if ch == "'":
            in_quote = True
            i += 1
            continue
        if ch == ";":
            return True
        i += 1

    return False


def iter_records(payload: str) -> Iterator[str]:
    """Yield individual value tuples as raw strings (without outer parentheses)."""
    in_quote = False
    escape = False
    record_start: Optional[int] = None
    i = 0
    length = len(payload)

    while i < length:
        ch = payload[i]

        if in_quote:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == "'" and i + 1 < length and payload[i + 1] == "'":
                i += 1
            elif ch == "'":
                in_quote = False
        else:
            if ch == "'":
                in_quote = True
            elif ch == "(":
                record_start = i + 1
            elif ch == ")" and record_start is not None:
                record = payload[record_start:i].strip()
                if record:
                    yield record
                record_start = None

        i += 1


def extract_records(src: Path, dst: Path, table: Optional[str]) -> None:
    """Copy tuple payloads from *src* into *dst*.

    Args:
        src:    Path to the SQL dump file.
        dst:    Destination file that will receive one tuple payload per line.
        table:  Optional table name filter; when provided only INSERT statements
                targeting that table are processed.
    """
    insert_pattern: Optional[re.Pattern[str]]
    if table:
        insert_pattern = re.compile(
            rf"^\s*INSERT\s+INTO\s+`?{re.escape(table)}`?\s+VALUES",
            re.IGNORECASE,
        )
    else:
        insert_pattern = re.compile(r"^\s*INSERT\s+INTO\s+.+?\s+VALUES", re.IGNORECASE)

    statements = 0
    records = 0
    collecting = False
    buffer = ""

    with src.open("r", encoding="utf-8", errors="replace") as reader, dst.open(
        "w", encoding="utf-8", newline=""
    ) as writer:
        for raw_line in reader:
            if not collecting:
                if insert_pattern and not insert_pattern.search(raw_line):
                    continue
                upper = raw_line.upper()
                values_idx = upper.find("VALUES")
                if values_idx == -1:
                    continue
                buffer = raw_line[values_idx + len("VALUES") :]
                collecting = True
            else:
                buffer += raw_line

            if collecting and statement_complete(buffer):
                statements += 1
                for record in iter_records(buffer):
                    writer.write(record)
                    writer.write("\n")
                    records += 1
                collecting = False
                buffer = ""

    print(f"Statements processed: {statements}")
    print(f"Records written:     {records}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract value tuples from INSERT statements."
    )
    parser.add_argument("input", type=Path, help="Input SQL dump file.")
    parser.add_argument("output", type=Path, help="Output plaintext file.")
    parser.add_argument(
        "--table",
        type=str,
        default="users",
        help="Restrict processing to this table name (default: users).",
    )
    parser.add_argument(
        "--allow-any-table",
        action="store_true",
        help="Process INSERT statements from any table.",
    )
    args = parser.parse_args()

    if args.output.resolve() == args.input.resolve():
        sys.exit("Input and output paths must be different.")

    table = None if args.allow_any_table else args.table
    extract_records(args.input, args.output, table)


if __name__ == "__main__":
    main()

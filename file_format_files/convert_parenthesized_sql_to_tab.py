#!/usr/bin/env python3
"""
Convert SQL-style value tuples (parentheses, single quotes, NULL literals) to TSV.

Example input line:
    (9,1,'','',0,'Rational',2,0,0,'2013-01-24 20:25:01')

Usage:
    python3 convert_parenthesized_sql_to_tab.py input.sql output.tsv
"""

import argparse
import sys
from pathlib import Path
from typing import Iterator, List
import csv


def normalize_record(line: str) -> str:
    stripped = line.strip()
    if not stripped:
        return ""

    # Remove trailing commas that follow value tuples.
    if stripped.endswith(","):
        stripped = stripped[:-1].rstrip()

    # Trim wrapping quotes first (in case the entire line is quoted).
    if stripped.startswith('"') and stripped.endswith('"'):
        stripped = stripped[1:-1]
        stripped = stripped.strip()

    # Remove leading '(' or trailing ')' as in SQL INSERT statements.
    if stripped.startswith("("):
        stripped = stripped[1:]
    if stripped.endswith(");"):
        stripped = stripped[:-2]
    elif stripped.endswith(")"):
        stripped = stripped[:-1]

    return stripped


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert SQL-style parenthesized rows into TSV."
    )
    parser.add_argument("input", type=Path, help="Input file with SQL-style records.")
    parser.add_argument("output", type=Path, help="Output TSV file.")
    parser.add_argument(
        "--encoding",
        default="utf-8",
        help="Input encoding (default utf-8).",
    )
    parser.add_argument(
        "--encoding-errors",
        default="strict",
        choices=["strict", "ignore", "replace"],
        help="How to handle decoding errors.",
    )
    args = parser.parse_args()

    if args.input.resolve() == args.output.resolve():
        raise SystemExit("Input and output paths must differ.")
    if not args.input.is_file():
        raise SystemExit(f"Input file '{args.input}' not found.")

    try:
        csv.field_size_limit(sys.maxsize)
    except (OverflowError, ValueError):
        csv.field_size_limit(10**9)

    with args.input.open(
        "r", encoding=args.encoding, errors=args.encoding_errors, newline=""
    ) as src, args.output.open("w", encoding="utf-8", newline="") as dst:
        writer = csv.writer(
            dst,
            delimiter="\t",
            lineterminator="\n",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
        )

        for record in iter_records(src):
            normalized = normalize_record(record)
            if not normalized:
                continue

            try:
                row = parse_sql_fields(normalized)
            except ValueError as exc:
                preview = (normalized[:120] + "...") if len(normalized) > 120 else normalized
                raise SystemExit(f"Failed to parse record: {preview} ({exc})") from exc

            transformed = []
            for value in row:
                value = value.replace("\x00", "")
                if value == "NULL":
                    transformed.append(r"\N")
                else:
                    value = value.replace("\r\n", "\n")
                    value = value.replace("\r", "\n")
                    value = value.replace("\t", " ")
                    if "\n" in value:
                        value = value.replace("\n", r"\n")
                    transformed.append(value)

            writer.writerow(transformed)


def iter_records(src) -> Iterator[str]:
    buffer: List[str] = []
    in_string = False
    escape_next = False

    def should_skip(text: str) -> bool:
        stripped = text.lstrip()
        if not stripped:
            return True
        upper = stripped.upper()
        if upper.startswith("--"):
            return True
        if upper.startswith("/*"):
            return True
        if upper.startswith("UNLOCK TABLES"):
            return True
        if upper.startswith("LOCK TABLES"):
            return True
        if upper.startswith("SET "):
            return True
        return False

    def handle_insert_statement(statement: str) -> Iterator[str]:
        stripped = statement.strip()
        upper = stripped.upper()
        values_idx = upper.find("VALUES")
        if values_idx == -1:
            return iter(())

        payload = stripped[values_idx + len("VALUES") :]
        return split_value_tuples(payload)

    def starts_new_record(line: str) -> bool:
        stripped = line.lstrip()
        if not stripped:
            return False
        first = stripped[0]
        return first == "(" or first.isdigit()

    for raw_line in src:
        if buffer and not in_string and starts_new_record(raw_line):
            record = "".join(buffer).strip()
            if record and not should_skip(record):
                if record.lstrip().upper().startswith("INSERT INTO"):
                    for tuple_record in handle_insert_statement(record):
                        yield tuple_record
                else:
                    yield record
            buffer.clear()
            escape_next = False

            if should_skip(raw_line):
                continue

        if not buffer and should_skip(raw_line):
            continue

        buffer.append(raw_line)

        i = 0
        while i < len(raw_line):
            ch = raw_line[i]
            if escape_next:
                escape_next = False
            else:
                if ch == "\\" and in_string:
                    escape_next = True
                elif ch == "'":
                    if in_string:
                        if i + 1 < len(raw_line) and raw_line[i + 1] == "'":
                            i += 1
                        else:
                            in_string = False
                    else:
                        in_string = True
            i += 1

    if buffer:
        record = "".join(buffer).strip()
        if record and not should_skip(record):
            if record.lstrip().upper().startswith("INSERT INTO"):
                for tuple_record in handle_insert_statement(record):
                    yield tuple_record
            else:
                yield record


def parse_sql_fields(record: str) -> List[str]:
    fields: List[str] = []
    field_chars: List[str] = []
    in_string = False
    escape = False
    current_is_string = False
    i = 0
    length = len(record)
    whitespace = {" ", "\t", "\r", "\n"}

    while i < length:
        ch = record[i]
        if in_string:
            if escape:
                if ch == "n":
                    field_chars.append("\n")
                elif ch == "r":
                    field_chars.append("\n")
                elif ch == "t":
                    field_chars.append(" ")
                elif ch == "0":
                    # skip NUL
                    pass
                else:
                    field_chars.append(ch)
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == "'":
                if i + 1 < length and record[i + 1] == "'":
                    field_chars.append("'")
                    i += 1
                else:
                    in_string = False
            else:
                field_chars.append(ch)
        else:
            if ch == "'":
                in_string = True
                current_is_string = True
            elif ch == ",":
                token = "".join(field_chars)
                fields.append(token if current_is_string else token.strip())
                field_chars = []
                current_is_string = False
            elif ch in whitespace:
                # Ignore whitespace between values when not inside a string
                if not field_chars:
                    pass
                elif current_is_string:
                    # Ignore trailing whitespace that follows a quoted value
                    pass
                else:
                    field_chars.append(ch)
            else:
                field_chars.append(ch)
        i += 1

    if in_string:
        raise ValueError("Unterminated string literal")

    token = "".join(field_chars)
    fields.append(token if current_is_string else token.strip())

    return fields


def split_value_tuples(payload: str) -> Iterator[str]:
    chunk: List[str] = []
    in_string = False
    escape_next = False
    depth = 0
    capturing = False

    for ch in payload:
        if capturing:
            chunk.append(ch)

        if escape_next:
            escape_next = False
            continue

        if ch == "\\":
            if capturing:
                chunk.append(ch)
            escape_next = True
            continue

        if ch == "'":
            in_string = not in_string
            continue

        if in_string:
            continue

        if ch == "(":
            if not capturing:
                chunk = ["("]
                capturing = True
            depth += 1
            continue

        if ch == ")":
            if capturing:
                depth -= 1
                if depth == 0:
                    tuple_str = "".join(chunk).strip()
                    if tuple_str.endswith(","):
                        tuple_str = tuple_str[:-1].rstrip()
                    yield tuple_str
                    chunk = []
                    capturing = False
            continue

        if not capturing and ch.strip() == "":
            continue

    if capturing and chunk:
        tuple_str = "".join(chunk).strip()
        if tuple_str.endswith(";"):
            tuple_str = tuple_str[:-1].rstrip()
        if tuple_str.endswith(","):
            tuple_str = tuple_str[:-1].rstrip()
        if tuple_str:
            yield tuple_str


if __name__ == "__main__":
    main()
    WHITESPACE = {" ", "\t", "\r", "\n"}

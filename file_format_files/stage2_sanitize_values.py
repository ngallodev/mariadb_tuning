#!/usr/bin/env python3
"""Stage 2: Remove problematic characters inside tuple payloads.

Goal
====
Normalize text values so they will round-trip cleanly through MariaDB's
`LOAD DATA INFILE`.  We focus on:
* Carriage returns/newlines embedded inside quoted strings.
* Horizontal tabs that would conflict with later tab-delimited exports.
* Non-printable control characters.
* Optionally, commas inside quoted values (swap them with a safer token).

Inputs / Outputs
================
* Input:  Output from Stage 1 (one tuple payload per line).
* Output: Sanitized payload file with the exact same quoting structure but
          cleaned text values.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from sql_value_utils import ParsedValue, parse_sql_row, serialize_sql_row


CONTROL_CHARS_PATTERN = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def sanitize_value(value: str, replace_commas: bool, comma_replacement: str) -> str:
    """Normalize whitespace, remove control characters, and optionally swap commas."""
    if not value:
        return value

    cleaned = value.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
    cleaned = cleaned.replace("\t", " ")
    cleaned = CONTROL_CHARS_PATTERN.sub(" ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()

    if replace_commas:
        cleaned = cleaned.replace(",", comma_replacement)

    return cleaned


def sanitize_file(
    src: Path, dst: Path, replace_commas: bool, comma_replacement: str
) -> None:
    """Clean each row from *src* and write the sanitized version to *dst*."""
    total_rows = 0
    modified_rows = 0
    modified_fields = 0

    with src.open("r", encoding="utf-8", errors="replace") as reader, dst.open(
        "w", encoding="utf-8", newline=""
    ) as writer:
        for raw_line in reader:
            line = raw_line.rstrip("\n")
            if not line.strip():
                continue

            total_rows += 1
            parsed = parse_sql_row(line)
            updated: list[ParsedValue] = []
            row_modified = False

            for value in parsed:
                cleaned = sanitize_value(
                    value.text, replace_commas and value.was_quoted, comma_replacement
                )
                if cleaned != value.text:
                    row_modified = True
                    modified_fields += 1
                updated.append(ParsedValue(cleaned, value.was_quoted))

            if row_modified:
                modified_rows += 1

            writer.write(serialize_sql_row(updated))
            writer.write("\n")

    print(f"Rows processed:       {total_rows}")
    print(f"Rows modified:        {modified_rows}")
    print(f"Fields adjusted:      {modified_fields}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Remove problematic whitespace and control characters inside quoted values."
    )
    parser.add_argument("input", type=Path, help="Stage 1 output file.")
    parser.add_argument("output", type=Path, help="Sanitized output file.")
    parser.add_argument(
        "--keep-commas",
        action="store_true",
        help="Do not replace commas that appear inside quoted values.",
    )
    parser.add_argument(
        "--comma-replacement",
        default=";",
        help="Replacement to use for commas inside quoted values (default: ';').",
    )
    args = parser.parse_args()

    sanitize_file(
        args.input,
        args.output,
        replace_commas=not args.keep_commas,
        comma_replacement=args.comma_replacement,
    )


if __name__ == "__main__":
    main()

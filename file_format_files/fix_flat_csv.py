#!/usr/bin/env python3
"""
Repair comma-delimited export files that were delivered without line endings.

The script consumes the flattened CSV, groups every N fields into a logical row,
and writes a newline-terminated CSV that is ready for LOAD DATA.

Examples:
    python3 fix_flat_csv.py input_flat.csv repaired.csv --columns 27
    python3 fix_flat_csv.py input_flat.csv repaired.csv --columns 27 \
        --record-prefix-regex="\\d+_\\d+," --drop-header
"""

import argparse
import csv
import re
from pathlib import Path
import sys

CHUNK_SIZE = 1024 * 1024


def chunked_rows(
    stream,
    columns,
    delimiter=",",
    quote_char='"',
    skip_partial=False,
    record_prefix_regex=None,
):
    """Dispatch to the appropriate row generator."""
    if record_prefix_regex:
        yield from chunked_rows_with_prefix(
            stream,
            columns,
            delimiter=delimiter,
            quote_char=quote_char,
            skip_partial=skip_partial,
            record_prefix_regex=record_prefix_regex,
        )
    else:
        yield from chunked_rows_fixed(
            stream,
            columns,
            delimiter=delimiter,
            quote_char=quote_char,
            skip_partial=skip_partial,
        )


def chunked_rows_fixed(stream, columns, delimiter=",", quote_char='"', skip_partial=False):
    """
    Yield rows by grouping fields into fixed-size records.

    This mode assumes the source file is a strict concatenation of CSV fields.
    """
    row = []
    field = []
    in_quotes = False
    pending_quote = False

    while True:
        chunk = stream.read(CHUNK_SIZE)
        if not chunk:
            break

        i = 0
        length = len(chunk)
        while i < length:
            ch = chunk[i]

            if pending_quote:
                if ch == quote_char:
                    field.append(quote_char)
                    pending_quote = False
                    i += 1
                    continue
                pending_quote = False
                in_quotes = False
                continue

            if ch == quote_char:
                if in_quotes:
                    pending_quote = True
                else:
                    if field:
                        field.append(ch)
                    else:
                        in_quotes = True
                i += 1
                continue

            if ch == delimiter and not in_quotes:
                row.append("".join(field))
                field = []
                if len(row) == columns:
                    yield row
                    row = []
                i += 1
                continue

            field.append(ch)
            i += 1

    if pending_quote:
        pending_quote = False
        in_quotes = False

    if row or field:
        row.append("".join(field))

        if not any(row):
            return

        if len(row) != columns:
            if skip_partial:
                print(
                    f"Skipping partial trailing row: got {len(row)} fields, expected {columns}",
                    file=sys.stderr,
                )
                return
            raise ValueError(
                f"Final row has {len(row)} fields (expected {columns}). "
                "Check the column count or input formatting."
            )
        yield row


def chunked_rows_with_prefix(
    stream,
    columns,
    delimiter=",",
    quote_char='"',
    skip_partial=False,
    record_prefix_regex=None,
):
    """
    Yield rows by splitting on a known record prefix (e.g., numeric id underscore id).

    The regex should match at the very beginning of each record, for example: r"\\d+_\\d+,"
    """
    pattern = re.compile(record_prefix_regex, re.MULTILINE)
    buffer = ""
    header_emitted = False

    while True:
        chunk = stream.read(CHUNK_SIZE)
        if not chunk:
            break
        buffer += chunk

        matches = list(pattern.finditer(buffer))
        if not matches:
            # Prevent unbounded growth once we have emitted the header.
            if header_emitted and len(buffer) > CHUNK_SIZE * 4:
                buffer = buffer[-CHUNK_SIZE * 2 :]
            continue

        first_start = matches[0].start()
        if not header_emitted and first_start > 0:
            header_section = buffer[:first_start].strip()
            if header_section:
                yield from parse_record(
                    header_section,
                    columns,
                    delimiter,
                    quote_char,
                    skip_partial=False,
                    expect_columns=False,
                )
            header_emitted = True
        elif not header_emitted:
            header_emitted = True

        for idx in range(len(matches) - 1):
            start = matches[idx].start()
            end = matches[idx + 1].start()
            record_str = buffer[start:end].strip()
            if not record_str:
                continue
            yield from parse_record(
                record_str,
                columns,
                delimiter,
                quote_char,
                skip_partial=skip_partial,
            )

        buffer = buffer[matches[-1].start():]
        header_emitted = True

    if buffer.strip():
        yield from parse_record(
            buffer.strip(),
            columns,
            delimiter,
            quote_char,
            skip_partial=skip_partial,
        )


def parse_record(
    record_str,
    columns,
    delimiter,
    quote_char,
    skip_partial=False,
    expect_columns=True,
):
    """Parse a single record string into a row and yield it."""
    normalized = record_str.replace("\r\n", "\n").replace("\r", "")
    reader = csv.reader([normalized], delimiter=delimiter, quotechar=quote_char)
    try:
        row = next(reader)
    except csv.Error as exc:
        raise ValueError(f"Failed to parse record: {record_str[:120]}... ({exc})") from exc

    if not row:
        return

    if expect_columns and len(row) != columns:
        if skip_partial:
            print(
                f"Skipping record with {len(row)} fields (expected {columns}): "
                f"{record_str[:120]}...",
                file=sys.stderr,
            )
            return
        raise ValueError(
            f"Record has {len(row)} fields (expected {columns}). "
            "Check delimiter, column count, or prefix pattern."
        )

    yield row


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize flattened comma-delimited files with missing line endings."
    )
    parser.add_argument("input", type=Path, help="Path to the flattened CSV file.")
    parser.add_argument("output", type=Path, help="Destination path for the repaired CSV.")
    parser.add_argument(
        "--columns",
        type=int,
        required=True,
        help="Number of columns per row (must match the table schema).",
    )
    parser.add_argument(
        "--drop-header",
        action="store_true",
        help="Omit the first logical row (useful if LOAD DATA will IGNORE 1 LINES).",
    )
    parser.add_argument(
        "--delimiter",
        default=",",
        help="Field delimiter, default is ','.",
    )
    parser.add_argument(
        "--encoding",
        default="utf-8",
        help="Source file encoding (default utf-8).",
    )
    parser.add_argument(
        "--encoding-errors",
        default="strict",
        choices=["strict", "ignore", "replace"],
        help="How to handle encoding errors when reading the source.",
    )
    parser.add_argument(
        "--skip-partial",
        action="store_true",
        help="Skip rows that do not have the full column count (use for chunked inputs).",
    )
    parser.add_argument(
        "--record-prefix-regex",
        help=(
            "Regex that marks the beginning of each record (e.g., '^(?:\\r)?\\d+_\\d+,'). "
            "When set, the prefix is used to locate record boundaries. Use '\\r' to match literal ^M."
        ),
    )
    args = parser.parse_args()

    if args.columns <= 0:
        raise SystemExit("Column count must be greater than zero.")

    with args.input.open(
        "r",
        encoding=args.encoding,
        errors=args.encoding_errors,
        newline="",
    ) as src, args.output.open(
        "w", encoding="utf-8", newline=""
    ) as dst:
        writer = csv.writer(dst, delimiter=args.delimiter, lineterminator="\n")

        for index, row in enumerate(
            chunked_rows(
                src,
                args.columns,
                delimiter=args.delimiter,
                skip_partial=args.skip_partial,
                record_prefix_regex=args.record_prefix_regex,
            )
        ):
            if index == 0 and args.drop_header:
                continue
            writer.writerow(row)


if __name__ == "__main__":
    main()

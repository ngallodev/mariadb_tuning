#!/usr/bin/env python3
"""
Convert a standard CSV (double-quoted, comma-delimited) file to TSV.

Unlike convert_singlequote_csv_to_tab.sh, this utility preserves commas that
appear inside quoted fields (e.g., "4,4") and supports very large field sizes.
"""

import argparse
import csv
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a standard CSV file (double-quoted) to TSV."
    )
    parser.add_argument("input", type=Path, help="Path to the input CSV file.")
    parser.add_argument("output", type=Path, help="Destination path for the TSV file.")
    parser.add_argument(
        "--encoding",
        default="latin-1",
        help="Input file encoding (default latin-1, which handles any byte sequence).",
    )
    parser.add_argument(
        "--encoding-errors",
        choices=["strict", "ignore", "replace"],
        default="replace",
        help="Error handling strategy for decoding (default replace).",
    )
    args = parser.parse_args()

    if args.input.resolve() == args.output.resolve():
        raise SystemExit("Input and output paths must differ.")

    if not args.input.is_file():
        raise SystemExit(f"Input file '{args.input}' not found.")

    # Lift CSV's default 128 KiB field size limit.
    try:
        csv.field_size_limit(sys.maxsize)
    except (OverflowError, ValueError):
        csv.field_size_limit(10**9)

    with args.input.open(
        "r", encoding=args.encoding, errors=args.encoding_errors, newline=""
    ) as src, args.output.open("w", encoding="utf-8", newline="") as dst:
        reader = csv.reader(src, delimiter=",", quotechar='"')
        writer = csv.writer(dst, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
        for row in reader:
            writer.writerow(row)


if __name__ == "__main__":
    main()

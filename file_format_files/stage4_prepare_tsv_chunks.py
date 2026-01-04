#!/usr/bin/env python3
"""Stage 4: Convert accepted rows into chunked TSV files ready for loading.

Goal
====
Turn the validated tuple payloads (SQL mode) or tab-delimited rows (TSV mode)
into MariaDB-friendly TSV files and split the result into manageable chunks.
Keeping chunks small makes it easier to resume or parallelise loads and works
well with the updated `bulk_load.sh` glob support.

Inputs / Outputs
================
* Input (sql): Stage 3 "accepted" file containing comma-delimited tuple payloads.
* Input (tsv): Stage 3 "accepted" file containing tab-delimited rows.
* Output:      One or more tab-delimited `.tsv` chunk files on disk.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import List, TextIO

from sql_value_utils import ParsedValue, parse_sql_row


def normalize_for_tsv(value: ParsedValue) -> str:
    """Convert a parsed value into the representation expected by bulk loads.

    Unquoted NULL literals are converted into the `\\N` placeholder that MariaDB
    expects when loading TSV data. Quoted fields are passed through untouched
    because Stage 2 already neutralised problematic characters.
    """
    text = value.text
    if not value.was_quoted and text.upper() == "NULL":
        return r"\N"
    return text


def chunk_rows(
    src: Path,
    out_dir: Path,
    base_name: str,
    rows_per_file: int,
    input_format: str,
    delimiter: str,
) -> None:
    """Convert *src* into chunked TSV files stored under *out_dir*."""

    out_dir.mkdir(parents=True, exist_ok=True)

    current_writer: csv.writer | None = None
    current_handle: TextIO | None = None
    rows_in_chunk = 0
    chunk_index = 0
    total_rows = 0
    chunk_paths: List[Path] = []

    def open_chunk_sql() -> tuple[csv.writer, TextIO, Path]:
        """Create a new chunk file and return the writer, handle, and path."""
        nonlocal chunk_index
        chunk_index += 1
        chunk_name = f"{base_name}_chunk_{chunk_index:04d}.tsv"
        chunk_path = out_dir / chunk_name
        handle = chunk_path.open("w", encoding="utf-8", newline="")
        writer = csv.writer(
            handle,
            delimiter="\t",
            lineterminator="\n",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
        )
        chunk_paths.append(chunk_path)
        return writer, handle, chunk_path

    def open_chunk_tsv() -> tuple[csv.writer, TextIO, Path]:
        nonlocal chunk_index
        chunk_index += 1
        chunk_name = f"{base_name}_chunk_{chunk_index:04d}.tsv"
        chunk_path = out_dir / chunk_name
        handle = chunk_path.open("w", encoding="utf-8", newline="")
        writer = csv.writer(
            handle,
            delimiter=delimiter,
            lineterminator="\n",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
        )
        chunk_paths.append(chunk_path)
        return writer, handle, chunk_path

    if input_format == "sql":
        with src.open("r", encoding="utf-8", errors="replace") as reader:
            for raw_line in reader:
                line = raw_line.rstrip("\n")
                if not line.strip():
                    continue

                if current_writer is None or rows_in_chunk >= rows_per_file:
                    if current_handle:
                        current_handle.close()
                    current_writer, current_handle, _ = open_chunk_sql()
                    rows_in_chunk = 0

                values = parse_sql_row(line)
                current_writer.writerow(normalize_for_tsv(v) for v in values)
                rows_in_chunk += 1
                total_rows += 1
    else:
        reader = src.open("r", encoding="utf-8", errors="replace", newline="")
        try:
            csv_reader = csv.reader(
                reader,
                delimiter=delimiter,
                quoting=csv.QUOTE_NONE,
                escapechar="\\",
            )
            for row in csv_reader:
                if not row:
                    continue

                if current_writer is None or rows_in_chunk >= rows_per_file:
                    if current_handle:
                        current_handle.close()
                    current_writer, current_handle, _ = open_chunk_tsv()
                    rows_in_chunk = 0

                current_writer.writerow(row)
                rows_in_chunk += 1
                total_rows += 1
        finally:
            reader.close()

    if current_handle:
        current_handle.close()

    print(f"Chunks created: {chunk_index}")
    print(f"Total rows written: {total_rows}")
    if chunk_paths:
        print("Chunk files:")
        for path in chunk_paths:
            print(f"  {path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert validated CSV data to TSV chunks for bulk loading."
    )
    parser.add_argument("input", type=Path, help="Stage 3 validated file.")
    parser.add_argument("output_dir", type=Path, help="Directory for TSV chunks.")
    parser.add_argument(
        "--base-name",
        help="Base name for chunk files (default: derived from input filename).",
    )
    parser.add_argument(
        "--rows-per-file",
        type=int,
        default=200_000,
        help="Maximum rows per chunk file (default: 200000).",
    )
    parser.add_argument(
        "--input-format",
        choices=["sql", "tsv"],
        default="sql",
        help="Input format for chunking.",
    )
    parser.add_argument(
        "--delimiter",
        default="\t",
        help="Delimiter when chunking pre-tabbed data (default: tab).",
    )
    args = parser.parse_args()

    base_name = args.base_name or args.input.stem
    chunk_rows(
        args.input,
        args.output_dir,
        base_name,
        args.rows_per_file,
        args.input_format,
        args.delimiter,
    )


if __name__ == "__main__":
    main()

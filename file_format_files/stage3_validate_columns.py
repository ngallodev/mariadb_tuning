#!/usr/bin/env python3
"""Stage 3: Separate records with unexpected column counts.

Goal
====
Make sure every row has the same number of columns before we invest in TSV
conversion or bulk loading.  Mismatched rows are quarantined for manual review.

Inputs / Outputs
================
* Input:  Stage 2 sanitized tuple payloads (SQL mode) or a tab-delimited file
          (TSV mode).
* Output A: Rows whose column counts match the expected schema.
* Output B: Rows whose column counts differ (these need manual attention).
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from sql_value_utils import count_columns


def validate_columns(
    src: Path,
    ok_path: Path,
    reject_path: Path,
    expected_columns: int | None,
    input_format: str,
    delimiter: str,
    skip_header: bool,
) -> None:
    """Split *src* rows into accepted and rejected files based on column counts.

    If ``expected_columns`` is not provided, the function adopts the first data
    row's column count as the reference value.
    """
    ok_count = 0
    bad_count = 0
    first_bad_line: tuple[int, int] | None = None
    resolved_expected = expected_columns

    # Create rejection log file
    rejection_log_path = reject_path.parent / f"{reject_path.stem}.log"
    rejection_log = rejection_log_path.open("w", encoding="utf-8")

    if input_format == "sql":
        with src.open("r", encoding="utf-8", errors="replace") as reader, ok_path.open(
            "w", encoding="utf-8", newline=""
        ) as ok_writer, reject_path.open(
            "w", encoding="utf-8", newline=""
        ) as reject_writer:
            for idx, raw_line in enumerate(reader, 1):
                line = raw_line.rstrip("\n")
                if not line.strip():
                    continue

                column_count = count_columns(line)
                if resolved_expected is None:
                    resolved_expected = column_count

                if column_count == resolved_expected:
                    ok_writer.write(line)
                    ok_writer.write("\n")
                    ok_count += 1
                else:
                    reject_writer.write(line)
                    reject_writer.write("\n")
                    bad_count += 1
                    if first_bad_line is None:
                        first_bad_line = (idx, column_count)

                    # Log rejection reason
                    preview = line[:100] + "..." if len(line) > 100 else line
                    rejection_log.write(
                        f"Line {idx}: Expected {resolved_expected} columns, found {column_count}\n"
                        f"  Data preview: {preview}\n\n"
                    )
    else:
        reader = src.open("r", encoding="utf-8", errors="replace", newline="")
        ok_handle = ok_path.open("w", encoding="utf-8", newline="")
        reject_handle = reject_path.open("w", encoding="utf-8", newline="")

        try:
            csv_reader = csv.reader(
                reader, delimiter=delimiter, quoting=csv.QUOTE_NONE, escapechar="\\"
            )
            ok_writer = csv.writer(
                ok_handle,
                delimiter=delimiter,
                lineterminator="\n",
                quoting=csv.QUOTE_NONE,
                escapechar="\\",
            )
            reject_writer = csv.writer(
                reject_handle,
                delimiter=delimiter,
                lineterminator="\n",
                quoting=csv.QUOTE_NONE,
                escapechar="\\",
            )

            header_skipped = False

            for idx, row in enumerate(csv_reader, 1):
                if not row:
                    continue

                if skip_header and not header_skipped:
                    header_skipped = True
                    continue

                column_count = len(row)
                if resolved_expected is None:
                    resolved_expected = column_count

                if column_count == resolved_expected:
                    ok_writer.writerow(row)
                    ok_count += 1
                else:
                    reject_writer.writerow(row)
                    bad_count += 1
                    if first_bad_line is None:
                        first_bad_line = (idx, column_count)

                    # Log rejection reason
                    preview = delimiter.join(row[:5]) + "..." if len(row) > 5 else delimiter.join(row)
                    rejection_log.write(
                        f"Line {idx}: Expected {resolved_expected} columns, found {column_count}\n"
                        f"  Data preview: {preview}\n\n"
                    )
        finally:
            reader.close()
            ok_handle.close()
            reject_handle.close()

    rejection_log.close()

    if resolved_expected is None:
        print("No data rows encountered.")
        return

    print(f"Expected columns: {resolved_expected}")
    print(f"Rows accepted:    {ok_count}")
    print(f"Rows rejected:    {bad_count}")
    if first_bad_line:
        line_no, found_cols = first_bad_line
        print(
            f"First mismatch at line {line_no}: found {found_cols} columns (expected {resolved_expected})."
        )
    if bad_count > 0:
        print(f"Rejection log:    {rejection_log_path}")
    else:
        # No rejections, remove empty log file
        rejection_log_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Split rows with unexpected column counts into a separate file."
    )
    parser.add_argument("input", type=Path, help="Input file to validate.")
    parser.add_argument(
        "ok_output", type=Path, help="Destination for rows with expected columns."
    )
    parser.add_argument(
        "reject_output",
        type=Path,
        help="Destination for rows with incorrect column counts.",
    )
    parser.add_argument(
        "--expected-columns",
        type=int,
        help="Expected number of columns. Defaults to the first row's count.",
    )
    parser.add_argument(
        "--input-format",
        choices=["sql", "tsv"],
        default="sql",
        help="Input format: 'sql' for tuple payloads, 'tsv' for tab-delimited data.",
    )
    parser.add_argument(
        "--delimiter",
        default="\t",
        help="Field delimiter when --input-format=tsv (default: tab).",
    )
    parser.add_argument(
        "--skip-header",
        action="store_true",
        help="Skip the first row (header) when validating TSV data.",
    )
    args = parser.parse_args()

    validate_columns(
        args.input,
        args.ok_output,
        args.reject_output,
        args.expected_columns,
        args.input_format,
        args.delimiter,
        args.skip_header,
    )


if __name__ == "__main__":
    main()

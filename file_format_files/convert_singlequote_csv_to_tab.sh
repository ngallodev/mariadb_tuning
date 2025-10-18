#!/bin/bash
#
# Convert single-quoted, comma-delimited data into plain tab-delimited text.
# This prepares legacy extracts for bulk_load.sh, which expects tabs and \N for NULLs.
#
# Usage: ./convert_singlequote_csv_to_tab.sh input.csv output.tsv
#
set -euo pipefail

if [ "$#" -lt 2 ]; then
    cat <<'EOF' >&2
Usage: ./convert_singlequote_csv_to_tab.sh <input.csv> <output.tsv>

Transforms lines such as:
  62,'user','pass','email@example.com',NULL,'N','Y'

Into tab-delimited rows with real NULL markers:
  62	user	pass	email@example.com	\N	N	Y
EOF
    exit 1
fi

INPUT_FILE=$1
OUTPUT_FILE=$2

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found" >&2
    exit 1
fi

if [ "$INPUT_FILE" = "$OUTPUT_FILE" ]; then
    echo "Error: Input and output paths must differ" >&2
    exit 1
fi

if [ -e "$OUTPUT_FILE" ]; then
    echo "Error: Refusing to overwrite existing '$OUTPUT_FILE'" >&2
    exit 1
fi

python3 - "$INPUT_FILE" "$OUTPUT_FILE" <<'PY'
import csv
import sys

input_path, output_path = sys.argv[1], sys.argv[2]

def strip_wrapper(line: str) -> str:
    # Trim whitespace and optional double quotes that wrap the whole record.
    stripped = line.strip()
    if stripped.startswith('"') and stripped.endswith('"'):
        stripped = stripped[1:-1]
    return stripped

def clean_value(value: str) -> str:
    # Replace control characters that would break TSV parsing.
    cleaned = value.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    # Drop any stray NULL bytes just in case.
    cleaned = cleaned.replace("\x00", "")
    return cleaned.strip()

with open(input_path, encoding="utf-8", newline="") as source, \
     open(output_path, "w", encoding="utf-8", newline="") as target:
    reader = csv.reader((strip_wrapper(line) for line in source),
                        delimiter=",",
                        quotechar="'",
                        escapechar="\\")
    writer = csv.writer(target,
                        delimiter="\t",
                        lineterminator="\n",
                        quoting=csv.QUOTE_NONE,
                        escapechar="\\")

    for row in reader:
        transformed = []
        for value in row:
            value = clean_value(value)
            if value == "NULL":
                transformed.append(r"\N")
            else:
                transformed.append(value)
        writer.writerow(transformed)
PY

echo "Wrote transformed data to $OUTPUT_FILE"

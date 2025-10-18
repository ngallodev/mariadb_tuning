#!/bin/bash
#
# Normalize tab-separated extracts that wrap values in single quotes.
# Strips outer single quotes, converts '' and NULL to \N, and fixes 0000-00-00 dates.
#
# Usage: ./normalize_singlequote_tsv.sh input.tsv output.tsv
#
set -euo pipefail

if [ "$#" -lt 2 ]; then
    cat <<'EOF' >&2
Usage: ./normalize_singlequote_tsv.sh <input.tsv> <output.tsv>

* Input must be tab-delimited.
* Fields may be wrapped in single quotes like 'Owner'.
* Empty strings appear as ''.
* NULL values appear as NULL (bare) or ''.

The script outputs a clean TSV compatible with bulk_load.sh defaults.
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
import sys

input_path, output_path = sys.argv[1], sys.argv[2]

def normalize(field: str) -> str:
    value = field.strip()

    # Remove outer single quotes if present.
    if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
        value = value[1:-1]

    if value == "NULL":
        return r"\N"

    # Preserve genuine empty strings.
    if value == "":
        return ""

    # Replace placeholder zero-date with NULL to avoid strict-mode failures.
    if value == "0000-00-00":
        return r"\N"

    return value

with open(input_path, encoding="utf-8", newline="") as source, \
     open(output_path, "w", encoding="utf-8", newline="") as target:
    for raw_line in source:
        raw_line = raw_line.rstrip("\n\r")
        if not raw_line:
            target.write("\n")
            continue

        fields = raw_line.split("\t")
        transformed = [normalize(field) for field in fields]
        target.write("\t".join(transformed) + "\n")
PY

echo "Wrote normalized data to $OUTPUT_FILE"

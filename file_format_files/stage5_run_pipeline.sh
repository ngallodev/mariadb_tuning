#!/usr/bin/env bash
# Stage 5: Run the full INSERT-to-TSV transformation pipeline.
#
# Purpose:
#   Automate the preprocessing steps so users can run a single
#   command to go from the original SQL dump or CSV export to a set of clean TSV
#   chunks.  The script understands both SQL INSERT dumps and standard CSV
#   extracts. Optionally, it can call `bulk_load.sh` after splitting to push the
#   data into MariaDB.
# Inputs:
#   * <input_file>: Path to an INSERT-heavy SQL dump or CSV extract.
#   * <output_dir>: Directory for final TSV chunk files.
# Outputs:
#   * <output_dir>/chunks/*.tsv  (load-ready tab-delimited files)
#   * <output_dir>/work/*        (intermediate artefacts for debugging)
#   * Console logging for each stage, including counts and warnings.
set -euo pipefail

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="/usr/local/lib/mariadb/file_format_files"

usage() {
    cat <<EOF
Usage: $(basename "$0") <input_file> <output_dir> [options]

Description:
  Orchestrates all preprocessing stages (extract, sanitize, validate, chunk)
  and optionally triggers MariaDB bulk loading. Intermediate files remain under
  the work directory for troubleshooting.

Options:
  --table NAME              Table name to match (default: users)
  --keep-commas             Do not replace commas inside quoted values during sanitation
  --comma-replacement STR   Replacement for commas inside quoted values (default: ;)
  --expected-columns N      Override expected column count (default: inferred)
  --rows-per-file N         Rows per TSV chunk (default: 200000)
  --work-dir DIR            Directory for intermediate files (default: <output_dir>/work)
  --input-format FMT        Source format: auto, sql, or csv (default: auto)
  --drop-header             Remove the first row when processing CSV/TSV data
  --bulk-load DB TABLE      Run bulk_load.sh after chunking
  --bulk-load-args ARGS     Extra arguments to pass to bulk_load.sh (repeatable)
  --help                    Show this message
EOF
}

if [[ $# -lt 2 ]]; then
    usage
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_DIR="$2"
shift 2

TABLE_NAME="users"
KEEP_COMMAS=false
COMMA_REPLACEMENT=";"
EXPECTED_COLUMNS=""
ROWS_PER_FILE=200000
WORK_DIR=""
INPUT_FORMAT="auto"
DROP_HEADER=false
RUN_BULK=false
BULK_DB=""
BULK_TABLE=""
declare -a BULK_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --table)
            TABLE_NAME="$2"
            shift 2
            ;;
        --table=*)
            TABLE_NAME="${1#*=}"
            shift
            ;;
        --keep-commas)
            KEEP_COMMAS=true
            shift
            ;;
        --comma-replacement)
            COMMA_REPLACEMENT="$2"
            shift 2
            ;;
        --comma-replacement=*)
            COMMA_REPLACEMENT="${1#*=}"
            shift
            ;;
        --expected-columns)
            EXPECTED_COLUMNS="$2"
            shift 2
            ;;
        --expected-columns=*)
            EXPECTED_COLUMNS="${1#*=}"
            shift
            ;;
        --rows-per-file)
            ROWS_PER_FILE="$2"
            shift 2
            ;;
        --rows-per-file=*)
            ROWS_PER_FILE="${1#*=}"
            shift
            ;;
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --work-dir=*)
            WORK_DIR="${1#*=}"
            shift
            ;;
        --input-format)
            INPUT_FORMAT="$2"
            shift 2
            ;;
        --input-format=*)
            INPUT_FORMAT="${1#*=}"
            shift
            ;;
        --drop-header)
            DROP_HEADER=true
            shift
            ;;
        --bulk-load)
            RUN_BULK=true
            BULK_DB="$2"
            BULK_TABLE="$3"
            shift 3
            ;;
        --bulk-load-args)
            BULK_ARGS+=("$2")
            shift 2
            ;;
        --bulk-load-args=*)
            BULK_ARGS+=("${1#*=}")
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                BULK_ARGS+=("$1")
                shift
            done
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Input file not found: $INPUT_FILE" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR="$OUTPUT_DIR/work"
fi
mkdir -p "$WORK_DIR"

detect_input_format() {
    local file="$1"
    local requested="$2"

    case "$requested" in
        sql|csv)
            echo "$requested"
            return
            ;;
        auto)
            ;;
        *)
            echo "Unknown --input-format value: $requested" >&2
            exit 1
            ;;
    esac

    # Verify file is readable
    if [[ ! -r "$file" ]]; then
        echo "ERROR: Cannot read input file: $file" >&2
        exit 1
    fi

    # Multi-method detection with logging
    echo "Auto-detecting input format..." >&2

    # Method 1: Look for INSERT INTO statements (case-insensitive)
    local insert_count=$(head -200 "$file" | grep -ciE '^\s*INSERT\s+INTO')
    echo "  Detection: Found $insert_count INSERT statements in first 200 lines" >&2

    # Method 2: Check for SQL-specific patterns
    local values_count=$(head -200 "$file" | grep -ciE 'VALUES\s*\(')
    echo "  Detection: Found $values_count VALUES clauses" >&2

    # Method 3: Check first non-empty line
    local first_line=$(head -1 "$file" | tr -d '\r\n')
    if [[ "$first_line" =~ ^[[:space:]]*INSERT[[:space:]]+INTO ]]; then
        echo "  Detection: First line starts with INSERT INTO" >&2
    fi

    # Decision logic: If we find INSERT or VALUES patterns, it's SQL
    if [[ $insert_count -gt 0 ]] || [[ $values_count -gt 0 ]]; then
        echo "  Result: Detected as SQL dump format" >&2
        echo "sql"
    else
        echo "  Result: Detected as CSV/TSV format" >&2
        echo "csv"
    fi
}

SOURCE_FORMAT=$(detect_input_format "$INPUT_FILE" "$INPUT_FORMAT")

# Define the canonical intermediates.  These filenames make it easy to inspect
# any stage output after the fact.
if [[ "$SOURCE_FORMAT" == "sql" ]]; then
    STAGE1_OUT="$WORK_DIR/stage1_values.csv"
    STAGE2_OUT="$WORK_DIR/stage2_sanitized.csv"
    STAGE3_OK="$WORK_DIR/stage3_valid.csv"
    STAGE3_REJECT="$WORK_DIR/stage3_rejects.csv"
else
    STAGE1_OUT="$WORK_DIR/stage1_converted.tsv"
    STAGE3_OK="$WORK_DIR/stage3_valid.tsv"
    STAGE3_REJECT="$WORK_DIR/stage3_rejects.tsv"
fi
CHUNK_DIR="$OUTPUT_DIR/chunks"
TOTAL_STEPS=$([[ "$SOURCE_FORMAT" == "sql" ]] && echo 4 || echo 3)

# Create pipeline log file
PIPELINE_LOG="$OUTPUT_DIR/pipeline.log"
exec > >(tee -a "$PIPELINE_LOG") 2>&1
echo "========================================"
echo "Pipeline started: $(date)"
echo "Input file: $INPUT_FILE"
echo "Output directory: $OUTPUT_DIR"
echo "Source format: $SOURCE_FORMAT"
echo "Table name: $TABLE_NAME"
echo "========================================"
echo ""

if [[ "$SOURCE_FORMAT" == "sql" ]]; then
    echo "========================================"
    # Stage 1: strip INSERT scaffolding and keep tuple payloads only.
    echo "[1/$TOTAL_STEPS] Extracting INSERT tuples"
    python3 "$SCRIPT_DIR/stage1_extract_insert_values.py" \
        "$INPUT_FILE" \
        "$STAGE1_OUT" \
        --table "$TABLE_NAME"

    echo "Output: $STAGE1_OUT"
    echo ""

    echo "========================================"
    echo "[2/$TOTAL_STEPS] Sanitizing values"
    # Stage 2 rewrites problematic characters and optionally swaps commas inside quotes.
    SANITIZE_ARGS=()
    if [[ "$KEEP_COMMAS" == true ]]; then
        SANITIZE_ARGS+=(--keep-commas)
    else
        SANITIZE_ARGS+=(--comma-replacement "$COMMA_REPLACEMENT")
    fi
    python3 "$SCRIPT_DIR/stage2_sanitize_values.py" \
        "$STAGE1_OUT" \
        "$STAGE2_OUT" \
        "${SANITIZE_ARGS[@]}"

    echo "Output: $STAGE2_OUT"
    echo ""

    echo "========================================"
    echo "[3/$TOTAL_STEPS] Validating column counts"
    # Stage 3 splits good vs. bad rows by counting columns.
    VALIDATE_ARGS=(--input-format=sql)
    if [[ -n "$EXPECTED_COLUMNS" ]]; then
        VALIDATE_ARGS+=(--expected-columns "$EXPECTED_COLUMNS")
    fi
    python3 "$SCRIPT_DIR/stage3_validate_columns.py" \
        "$STAGE2_OUT" \
        "$STAGE3_OK" \
        "$STAGE3_REJECT" \
        "${VALIDATE_ARGS[@]}"
else
    echo "========================================"
    echo "[1/$TOTAL_STEPS] Converting CSV to TSV"
    python3 "$SCRIPT_DIR/convert_csv_to_tab.py" \
        "$INPUT_FILE" \
        "$STAGE1_OUT"
    echo "Output: $STAGE1_OUT"
    echo ""

    echo "========================================"
    echo "[2/$TOTAL_STEPS] Validating column counts (TSV)"
    VALIDATE_ARGS=(--input-format=tsv --delimiter=$'\t')
    if [[ -n "$EXPECTED_COLUMNS" ]]; then
        VALIDATE_ARGS+=(--expected-columns "$EXPECTED_COLUMNS")
    fi
    if [[ "$DROP_HEADER" == true ]]; then
        VALIDATE_ARGS+=(--skip-header)
    fi
    python3 "$SCRIPT_DIR/stage3_validate_columns.py" \
        "$STAGE1_OUT" \
        "$STAGE3_OK" \
        "$STAGE3_REJECT" \
        "${VALIDATE_ARGS[@]}"
fi

echo "Accepted rows: $STAGE3_OK"
echo "Rejected rows: $STAGE3_REJECT"
echo ""

echo "========================================"
echo "[${TOTAL_STEPS}/$TOTAL_STEPS] Creating TSV chunks"
# Stage 4 converts accepted rows into tab-delimited chunks sized for fast loads.
CHUNK_ARGS=(--rows-per-file "$ROWS_PER_FILE")
if [[ "$SOURCE_FORMAT" == "sql" ]]; then
    CHUNK_ARGS+=(--input-format=sql)
else
    CHUNK_ARGS+=(--input-format=tsv --delimiter=$'\t')
fi
python3 "$SCRIPT_DIR/stage4_prepare_tsv_chunks.py" \
    "$STAGE3_OK" \
    "$CHUNK_DIR" \
    "${CHUNK_ARGS[@]}"

echo "Chunks directory: $CHUNK_DIR"

if [[ -s "$STAGE3_REJECT" ]]; then
    echo ""
    echo "⚠ Rows requiring manual review were written to: $STAGE3_REJECT"
    REJECT_LOG="${STAGE3_REJECT%.csv}.log"
    REJECT_LOG="${REJECT_LOG%.tsv}.log"
    if [[ -f "$REJECT_LOG" ]]; then
        echo "⚠ Rejection details logged to: $REJECT_LOG"
    fi
fi

echo ""
echo "========================================"
echo "Pipeline completed: $(date)"
echo "Full pipeline log: $PIPELINE_LOG"
echo "========================================"

if [[ "$RUN_BULK" == true ]]; then
    # Optional: feed the generated chunks straight into MariaDB.
    BULK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/bulk_load.sh"
    if [[ ! -x "$BULK_SCRIPT" ]]; then
        echo "bulk_load.sh not found or not executable at $BULK_SCRIPT" >&2
        exit 1
    fi
    # Chunks share the sanitized base name, so glob across all chunk files.
    BASE_NAME="$(basename "$STAGE3_OK")"
    BASE_STEM="${BASE_NAME%.*}"
    PATTERN="$CHUNK_DIR/${BASE_STEM}_chunk_*.tsv"
    echo ""
    echo "========================================"
    echo "[Bulk] Loading data with pattern: $PATTERN"
    "$BULK_SCRIPT" "$BULK_DB" "$BULK_TABLE" "$PATTERN" "${BULK_ARGS[@]}"
fi

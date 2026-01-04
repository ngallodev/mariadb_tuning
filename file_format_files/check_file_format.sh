#!/bin/bash
#
# Text File Format Checker
# Analyzes text file format for bulk loading into MariaDB
#
# Usage: ./check_file_format.sh <filename>
#

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ $# -eq 0 ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

FILE=$1

if [ ! -f "$FILE" ]; then
    echo -e "${RED}Error: File '$FILE' not found${NC}"
    exit 1
fi

SCRIPT_DIR="/usr/local/lib/mariadb/file_format_files"

declare -a SCRIPT_SUGGESTIONS=()

add_suggestion() {
    local suggestion="$1"
    for existing in "${SCRIPT_SUGGESTIONS[@]}"; do
        if [ "$existing" = "$suggestion" ]; then
            return
        fi
    done
    SCRIPT_SUGGESTIONS+=("$suggestion")
}

FILE_DIR=$(dirname "$FILE")
BASE_NAME=$(basename "$FILE")
BASE_WITHOUT_EXT="${BASE_NAME%.*}"
if [ "$BASE_WITHOUT_EXT" = "$BASE_NAME" ]; then
    BASE_WITHOUT_EXT="${BASE_NAME}_converted"
fi
TSV_OUTPUT="$FILE_DIR/${BASE_WITHOUT_EXT}_clean.tsv"
FIXED_OUTPUT="$FILE_DIR/${BASE_WITHOUT_EXT}_fixed.csv"
PIPELINE_OUTPUT_DIR="$FILE_DIR/${BASE_WITHOUT_EXT}_pipeline"
ESTIMATED_COLUMNS=""
HAS_HEADER_ROW=0
TABLE_NAME=""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Text File Format Checker${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "File: ${YELLOW}$FILE${NC}"
echo ""

# Basic file info
echo -e "${GREEN}[1] File Information${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SIZE=$(du -h "$FILE" | cut -f1)
LINES=$(wc -l < "$FILE")
echo "  Size: $SIZE"
echo "  Lines: $LINES"
echo ""

# Encoding check
ENCODING=$(file -b --mime-encoding "$FILE")
echo "  Encoding: $ENCODING"
if [ "$ENCODING" != "utf-8" ] && [ "$ENCODING" != "us-ascii" ]; then
    echo -e "  ${YELLOW}⚠ Warning: Non-UTF-8 encoding detected${NC}"
    echo "  Consider converting: iconv -f $ENCODING -t UTF-8 $FILE > ${FILE}.utf8"
fi
echo ""

# Line ending check
echo -e "${GREEN}[2] Line Endings${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if file "$FILE" | grep -q CRLF; then
    echo -e "  ${YELLOW}⚠ Windows (CRLF - \\r\\n)${NC}"
    echo "  Consider converting: dos2unix $FILE"
elif file "$FILE" | grep -q "CR line"; then
    echo -e "  ${YELLOW}⚠ Mac Classic (CR - \\r)${NC}"
    echo "  Consider converting: mac2unix $FILE"
else
    echo -e "  ${GREEN}✓ Unix (LF - \\n)${NC}"
fi
echo ""

# Delimiter detection
echo -e "${GREEN}[3] Delimiter Detection (first 100 lines)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TABS=$(head -100 "$FILE" | grep -c $'\t' || true)
COMMAS=$(head -100 "$FILE" | grep -c ',' || true)
PIPES=$(head -100 "$FILE" | grep -c '|' || true)
SEMICOLONS=$(head -100 "$FILE" | grep -c ';' || true)

TABS=${TABS:-0}
COMMAS=${COMMAS:-0}
PIPES=${PIPES:-0}
SEMICOLONS=${SEMICOLONS:-0}

SAMPLE_HEAD=$(head -100 "$FILE" 2>/dev/null)

if printf '%s\n' "$SAMPLE_HEAD" | grep -q '"'; then
    HAS_DOUBLE_QUOTES=1
else
    HAS_DOUBLE_QUOTES=0
fi

HAS_SINGLE_QUOTE_WRAPS=0
if printf '%s\n' "$SAMPLE_HEAD" | grep -q "^'"; then
    HAS_SINGLE_QUOTE_WRAPS=1
elif printf '%s\n' "$SAMPLE_HEAD" | grep -q ",\'"; then
    HAS_SINGLE_QUOTE_WRAPS=1
elif printf '%s\n' "$SAMPLE_HEAD" | grep -q $'\t\''; then
    HAS_SINGLE_QUOTE_WRAPS=1
fi

HAS_PAREN_ROWS=0
if printf '%s\n' "$SAMPLE_HEAD" | grep -q '^\s*('; then
    HAS_PAREN_ROWS=1
fi

HAS_INSERT_INTO=0
if printf '%s\n' "$SAMPLE_HEAD" | grep -iq 'insert into'; then
    HAS_INSERT_INTO=1
fi

if [ "$HAS_INSERT_INTO" -eq 1 ]; then
    TABLE_NAME=$(python3 - "$FILE" <<'PY'
import re
import sys

path = sys.argv[1]
pattern = re.compile(
    r"INSERT\s+INTO\s+(?:`([^`]+)`|([A-Za-z0-9_]+))(?:\s*\(|\s+VALUES)",
    re.IGNORECASE,
)
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for _ in range(500):
            line = handle.readline()
            if not line:
                break
            match = pattern.search(line)
            if match:
                value = match.group(1) or match.group(2) or ""
                if "." in value:
                    value = value.split(".")[-1]
                print(value)
                break
except OSError:
    pass
PY
)
    TABLE_NAME=${TABLE_NAME//$'\n'/}
    TABLE_NAME=${TABLE_NAME//$'\r'/}
fi

SOURCE_FORMAT="unknown"
if [ "$HAS_INSERT_INTO" -eq 1 ] || [ "$HAS_PAREN_ROWS" -eq 1 ]; then
    SOURCE_FORMAT="sql"
elif [ "$LIKELY_DELIMITER" = "COMMA" ]; then
    SOURCE_FORMAT="csv"
fi

echo "  Lines with tabs:       $TABS"
echo "  Lines with commas:     $COMMAS"
echo "  Lines with pipes:      $PIPES"
echo "  Lines with semicolons: $SEMICOLONS"
echo ""

# Determine likely delimiter
LIKELY_DELIMITER=""
if [ "${TABS:-0}" -gt 50 ]; then
    LIKELY_DELIMITER="TAB"
    echo -e "  ${GREEN}→ Likely delimiter: TAB (\\t)${NC}"
    echo "  Use default bulk_load.sh without changes"
elif [ "${COMMAS:-0}" -gt 50 ]; then
    LIKELY_DELIMITER="COMMA"
    echo -e "  ${GREEN}→ Likely delimiter: COMMA (,)${NC}"
    echo "  Modify bulk_load.sh: FIELDS TERMINATED BY ','"
    if [ "${HAS_DOUBLE_QUOTES:-0}" -eq 1 ]; then
        add_suggestion "python3 $SCRIPT_DIR/convert_csv_to_tab.py \"$FILE\" \"$TSV_OUTPUT\"  # Convert double-quoted CSV to tab-delimited"
    fi
    if [ "${HAS_SINGLE_QUOTE_WRAPS:-0}" -eq 1 ]; then
        add_suggestion "$SCRIPT_DIR/convert_singlequote_csv_to_tab.sh \"$FILE\" \"$TSV_OUTPUT\"  # Convert single-quoted CSV exports"
    fi
    if [ "${HAS_DOUBLE_QUOTES:-0}" -eq 0 ] && [ "${HAS_SINGLE_QUOTE_WRAPS:-0}" -eq 0 ]; then
        add_suggestion "python3 $SCRIPT_DIR/convert_csv_to_tab.py \"$FILE\" \"$TSV_OUTPUT\"  # Convert comma-delimited data to tab-delimited"
    fi
elif [ "${PIPES:-0}" -gt 50 ]; then
    LIKELY_DELIMITER="PIPE"
    echo -e "  ${GREEN}→ Likely delimiter: PIPE (|)${NC}"
    echo "  Modify bulk_load.sh: FIELDS TERMINATED BY '|'"
elif [ "${SEMICOLONS:-0}" -gt 50 ]; then
    LIKELY_DELIMITER="SEMICOLON"
    echo -e "  ${GREEN}→ Likely delimiter: SEMICOLON (;)${NC}"
    echo "  Modify bulk_load.sh: FIELDS TERMINATED BY ';'"
else
    echo -e "  ${YELLOW}⚠ Could not determine delimiter reliably${NC}"
fi
echo ""

if [ "${LIKELY_DELIMITER:-}" = "TAB" ] && [ "${HAS_SINGLE_QUOTE_WRAPS:-0}" -eq 1 ]; then
    add_suggestion "$SCRIPT_DIR/normalize_singlequote_tsv.sh \"$FILE\" \"$TSV_OUTPUT\"  # Strip single quotes and fix NULL markers in TSV extracts"
fi

if [ "${HAS_PAREN_ROWS:-0}" -eq 1 ]; then
    add_suggestion "python3 $SCRIPT_DIR/convert_parenthesized_sql_to_tab.py \"$FILE\" \"$TSV_OUTPUT\"  # Convert SQL value tuples to tab-delimited text"
fi

if [ "${HAS_INSERT_INTO:-0}" -eq 1 ]; then
    add_suggestion "python3 $SCRIPT_DIR/split_sql_inserts.py \"$FILE\" <output_dir>  # Split large dumps into per-INSERT chunks before conversion"
fi

# First line analysis
echo -e "${GREEN}[4] First Line Analysis${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
FIRST_LINE=$(head -1 "$FILE")
echo "  Raw content:"
echo "    $FIRST_LINE"
echo ""

# Count delimiters in first line
TAB_COUNT=$(echo "$FIRST_LINE" | tr -cd '\t' | wc -c)
COMMA_COUNT=$(echo "$FIRST_LINE" | tr -cd ',' | wc -c)
PIPE_COUNT=$(echo "$FIRST_LINE" | tr -cd '|' | wc -c)
SEMICOLON_COUNT=$(echo "$FIRST_LINE" | tr -cd ';' | wc -c)

echo "  Delimiter counts:"
echo "    Tabs:       $TAB_COUNT"
echo "    Commas:     $COMMA_COUNT"
echo "    Pipes:      $PIPE_COUNT"
echo "    Semicolons: $SEMICOLON_COUNT"
echo ""

# Show with visible delimiters
echo "  With visible tabs [TAB] and special chars:"
echo "    $(echo "$FIRST_LINE" | sed 's/\t/[TAB]/g' | cat -A | head -c 100)"
echo ""

# Estimated columns
# For SQL INSERT dumps, extract a single tuple and use SQL-aware parsing
if [ "$HAS_INSERT_INTO" -eq 1 ]; then
    ESTIMATED_COLUMNS=$(python3 - "$FILE" <<'PY'
import sys
import re
sys.path.insert(0, "/usr/local/lib/mariadb/file_format_files")
from sql_value_utils import count_columns

path = sys.argv[1]
values_pattern = re.compile(r"VALUES\s*\(", re.IGNORECASE)

try:
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            if not line.strip():
                continue
            # Find first VALUES clause
            match = values_pattern.search(line)
            if match:
                # Extract from opening paren to end
                start = match.end() - 1  # Include the opening (
                rest = line[start:]
                # Find the matching closing paren for first tuple
                depth = 0
                end_pos = -1
                for i, ch in enumerate(rest):
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                        if depth == 0:
                            end_pos = i
                            break
                if end_pos > 0:
                    # Extract just the first tuple content (without parens)
                    tuple_content = rest[1:end_pos]
                    col_count = count_columns(tuple_content)
                    print(col_count)
                    sys.exit(0)
except Exception:
    pass
PY
)
    if [ -n "$ESTIMATED_COLUMNS" ] && [ "$ESTIMATED_COLUMNS" -gt 0 ]; then
        echo -e "  ${GREEN}Estimated columns (SQL tuple parsing): $ESTIMATED_COLUMNS${NC}"
    else
        echo -e "  ${YELLOW}⚠ Could not parse SQL tuple for column count${NC}"
    fi
elif [ "${TAB_COUNT:-0}" -gt 0 ]; then
    ESTIMATED_COLUMNS=$((TAB_COUNT + 1))
    echo -e "  ${GREEN}Estimated columns (tab-based): $ESTIMATED_COLUMNS${NC}"
elif [ "${COMMA_COUNT:-0}" -gt 0 ]; then
    ESTIMATED_COLUMNS=$((COMMA_COUNT + 1))
    echo -e "  ${GREEN}Estimated columns (comma-based): $ESTIMATED_COLUMNS${NC}"
elif [ "${PIPE_COUNT:-0}" -gt 0 ]; then
    ESTIMATED_COLUMNS=$((PIPE_COUNT + 1))
    echo -e "  ${GREEN}Estimated columns (pipe-based): $ESTIMATED_COLUMNS${NC}"
fi
echo ""

# Check for header row
echo -e "${GREEN}[5] Header Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if echo "$FIRST_LINE" | grep -q -E '[a-zA-Z_]{3,}'; then
    HAS_NUMBERS=$(echo "$FIRST_LINE" | grep -o '[0-9]' | wc -l)
    if [ "${HAS_NUMBERS:-0}" -lt 2 ]; then
        echo -e "  ${YELLOW}⚠ First line looks like a header row${NC}"
        echo "  Modify bulk_load.sh: IGNORE 1 LINES"
        HAS_HEADER_ROW=1
    else
        echo -e "  ${GREEN}✓ First line looks like data${NC}"
        echo "  Use: IGNORE 0 LINES"
    fi
else
    echo -e "  ${GREEN}✓ First line looks like data${NC}"
    echo "  Use: IGNORE 0 LINES"
fi
echo ""

# Sample data preview
echo -e "${GREEN}[6] Sample Data (first 5 lines)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
head -5 "$FILE" | nl -w2 -s': '
echo ""

# Check for common issues
echo -e "${GREEN}[7] Issue Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ISSUES=0

# Check for inconsistent column counts
if [ -n "$LIKELY_DELIMITER" ] && [ "$LIKELY_DELIMITER" != "SEMICOLON" ]; then
    case $LIKELY_DELIMITER in
        TAB)
            DELIM=$'\t'
            EXPECTED=$((TAB_COUNT + 1))
            ;;
        COMMA)
            DELIM=','
            EXPECTED=$((COMMA_COUNT + 1))
            ;;
        PIPE)
            DELIM='|'
            EXPECTED=$((PIPE_COUNT + 1))
            ;;
    esac
    
    INCONSISTENT=$(awk -F"$DELIM" 'NF!='$EXPECTED' {print NR}' "$FILE" | head -100 | tr '\n' ',' | sed 's/,$//')
    # Escape delimiter for awk if necessary
    ESCAPED_DELIM=$(printf '%s' "$DELIM" | sed 's/[]\/$*.^[]/\\&/g')
    INCONSISTENT=$(awk -F"$ESCAPED_DELIM" 'NF!='$EXPECTED' {print NR}' "$FILE" | head -100 | tr '\n' ',' | sed 's/,$//')
    if [ -n "$INCONSISTENT" ]; then
        echo -e "  ${RED}✗ Inconsistent column counts detected${NC}"
        echo "    Lines with wrong count: $INCONSISTENT"
        if [ "${LIKELY_DELIMITER:-}" = "COMMA" ]; then
            add_suggestion "python3 $SCRIPT_DIR/fix_csv.py \"$FILE\" \"$FIXED_OUTPUT\"  # Recombine rows split by embedded newlines"
        fi
        ISSUES=$((ISSUES + 1))
    else
        echo -e "  ${GREEN}✓ Consistent column counts${NC}"
    fi
fi

# Check for blank lines
BLANK_LINES=$(grep -c '^$' "$FILE" 2>/dev/null || true)
BLANK_LINES=${BLANK_LINES:-0}
if [ "${BLANK_LINES:-0}" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ Found $BLANK_LINES blank lines${NC}"
    echo "    Consider removing: sed -i '/^$/d' $FILE"
    ISSUES=$((ISSUES + 1))
else
    echo -e "  ${GREEN}✓ No blank lines${NC}"
fi

# Check for very long lines
MAX_LINE=$(awk '{print length}' "$FILE" | sort -n | tail -1 || echo 0)
if [ -n "$MAX_LINE" ] && [ "$MAX_LINE" -gt 10000 ]; then
    echo -e "  ${YELLOW}⚠ Very long line detected: $MAX_LINE characters${NC}"
    echo "    May need to increase max_allowed_packet"
    if [ "${LIKELY_DELIMITER:-}" = "COMMA" ] && [ "${LINES:-0}" -le 3 ]; then
        add_suggestion "python3 $SCRIPT_DIR/fix_flat_csv.py \"$FILE\" \"$FIXED_OUTPUT\" --columns <expected-columns>  # Rebuild missing line breaks in flattened CSV exports"
    fi
    ISSUES=$((ISSUES + 1))
else
    echo -e "  ${GREEN}✓ Line lengths reasonable (max: ${MAX_LINE:-0} chars)${NC}"
fi

# Check for NULL indicators
NULL_INDICATORS=$(head -100 "$FILE" | grep -c '\\N' || true)
NULL_INDICATORS=${NULL_INDICATORS:-0}
if [ "${NULL_INDICATORS:-0}" -gt 0 ]; then
    echo -e "  ${GREEN}✓ Found \\N NULL indicators (MariaDB native)${NC}"
fi

echo ""

# Summary and recommendations
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}SUMMARY & RECOMMENDATIONS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "${ISSUES:-0}" -eq 0 ]; then
    echo -e "${GREEN}✓ File looks good for bulk loading!${NC}"
else
    echo -e "${YELLOW}⚠ Found $ISSUES potential issue(s) - review above${NC}"
fi
echo ""

PIPELINE_SCRIPT="$SCRIPT_DIR/stage5_run_pipeline.sh"
declare -a PIPELINE_CMD=()
declare -a PIPELINE_NOTES=()

if [ -x "$PIPELINE_SCRIPT" ]; then
    case "$SOURCE_FORMAT" in
        sql)
            PIPELINE_CMD+=("$PIPELINE_SCRIPT" "$FILE" "$PIPELINE_OUTPUT_DIR" "--input-format=sql" "--keep-commas")
            if [ -n "$TABLE_NAME" ]; then
                PIPELINE_CMD+=("--table" "$TABLE_NAME")
                PIPELINE_NOTES+=("Detected table: $TABLE_NAME")
            fi
            if [ -n "$ESTIMATED_COLUMNS" ]; then
                PIPELINE_CMD+=("--expected-columns" "$ESTIMATED_COLUMNS")
                PIPELINE_NOTES+=("Expecting $ESTIMATED_COLUMNS columns per tuple.")
            fi
            PIPELINE_NOTES+=("Input detected as SQL INSERT dump; pipeline will run Stage 1–4.")
            ;;
        csv)
            PIPELINE_CMD+=("$PIPELINE_SCRIPT" "$FILE" "$PIPELINE_OUTPUT_DIR" "--input-format=csv")
            if [ "$HAS_HEADER_ROW" -eq 1 ]; then
                PIPELINE_CMD+=("--drop-header")
                PIPELINE_NOTES+=("Header row detected; --drop-header will remove it during conversion.")
            fi
            if [ -n "$ESTIMATED_COLUMNS" ]; then
                PIPELINE_CMD+=("--expected-columns" "$ESTIMATED_COLUMNS")
                PIPELINE_NOTES+=("Expecting $ESTIMATED_COLUMNS columns in the CSV.")
            fi
            PIPELINE_NOTES+=("Input detected as CSV; pipeline will convert to TSV before chunking.")
            ;;
        *)
            ;;
    esac

echo -e "${GREEN}[Pipeline] Recommended Transformation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ ${#PIPELINE_CMD[@]} -gt 0 ]; then
    PIPELINE_CMD_STR=$(printf ' %q' "${PIPELINE_CMD[@]}")
    PIPELINE_CMD_STR=${PIPELINE_CMD_STR# }
    echo "  Output directory: $PIPELINE_OUTPUT_DIR"
    echo "  Run:"
    echo "    $PIPELINE_CMD_STR"
    if [ "${#PIPELINE_NOTES[@]}" -gt 0 ]; then
        echo ""
        echo "  Notes:"
        for note in "${PIPELINE_NOTES[@]}"; do
            echo "    - $note"
        done
    fi
    echo ""
    echo "  stage5_run_pipeline.sh internally executes:"
    echo "    stage1 → stage2 → stage3 → stage4"
    echo "  and produces chunked TSV files ready for bulk loading."
else
    echo "  Unable to auto-detect pipeline flags for this file."
    echo "  Run pipeline manually with '--input-format=sql|csv' as appropriate."
fi
echo ""
fi

echo -e "${GREEN}[Pipeline] Stage Reference${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  stage1_extract_insert_values.py  → Pull tuples out of INSERT dumps"
echo "  stage2_sanitize_values.py        → Scrub control chars / commas inside quotes"
echo "  stage3_validate_columns.py       → Separate rows with wrong column counts"
echo "  stage4_prepare_tsv_chunks.py     → Convert to chunked TSV files"
echo "  stage5_run_pipeline.sh           → Wrapper that runs stages 1–4 (SQL or CSV input)"
echo ""

echo -e "${GREEN}[Cleanup Helpers & Alternatives]${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Use these scripts when you want to address specific issues manually"
echo "  (before or instead of running the full stage1–stage5 pipeline). They can"
echo "  also be combined with pipeline stages for advanced workflows."
if [ "${#SCRIPT_SUGGESTIONS[@]}" -gt 0 ]; then
    for suggestion in "${SCRIPT_SUGGESTIONS[@]}"; do
        echo "    • $suggestion"
    done
else
    echo "    • No specific cleanup scripts required based on current checks."
    echo "      Explore $SCRIPT_DIR for conversion helpers such as:"
    echo "        python3 $SCRIPT_DIR/convert_csv_to_tab.py <input.csv> <output.tsv>"
    echo "        $SCRIPT_DIR/convert_singlequote_csv_to_tab.sh <input.csv> <output.tsv>"
    echo "        python3 $SCRIPT_DIR/convert_parenthesized_sql_to_tab.py <input.sql> <output.tsv>"
fi
echo ""

echo "Recommended bulk_load.sh settings:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  The options below apply if you plan to load ${FILE} directly without first"
echo "  running the pipeline or other cleanup steps. After stage5_run_pipeline.sh,"
echo "  the generated TSV chunks already match bulk_load.sh defaults (tab-delimited"
echo "  with Unix newlines), so no additional flags are usually required."

case $LIKELY_DELIMITER in
    TAB)
        echo "  FIELDS TERMINATED BY '\\t'"
        ;;
    COMMA)
        echo "  FIELDS TERMINATED BY ','"
        echo "  ENCLOSED BY '\"'    # If values contain commas"
        ;;
    PIPE)
        echo "  FIELDS TERMINATED BY '|'"
        ;;
    SEMICOLON)
        echo "  FIELDS TERMINATED BY ';'"
        ;;
    *)
        echo "  (Could not determine - review file manually)"
        ;;
esac

if echo "$FIRST_LINE" | grep -q -E '[a-zA-Z_]{3,}'; then
    HAS_NUMBERS=$(echo "$FIRST_LINE" | grep -o '[0-9]' | wc -l)
    if [ $HAS_NUMBERS -lt 2 ]; then
        echo "  IGNORE 1 LINES      # Skip header row"
    else
        echo "  IGNORE 0 LINES      # No header row"
    fi
elif [ $HAS_HEADER_ROW -eq 1 ]; then
    echo "  IGNORE 1 LINES      # Skip header row"
else
    echo "  IGNORE 0 LINES      # No header row"
fi

if file "$FILE" | grep -q CRLF; then
    echo "  LINES TERMINATED BY '\\r\\n'  # Windows line endings"
else
    echo "  LINES TERMINATED BY '\\n'     # Unix line endings"
fi

echo ""
echo "To use with bulk_load.sh:"

# Build suggested command with detected parameters
SUGGESTED_CMD="./bulk_load.sh database table $FILE"

# Add format parameter based on detected delimiter
case $LIKELY_DELIMITER in
    TAB)
        SUGGESTED_CMD="$SUGGESTED_CMD --format=tab"
        ;;
    COMMA)
        SUGGESTED_CMD="$SUGGESTED_CMD --format=csv"
        ;;
    PIPE)
        SUGGESTED_CMD="$SUGGESTED_CMD --delimiter='|'"
        ;;
    SEMICOLON)
        SUGGESTED_CMD="$SUGGESTED_CMD --delimiter=';'"
        ;;
esac

# Add line terminator if Windows
if file "$FILE" | grep -q CRLF; then
    SUGGESTED_CMD="$SUGGESTED_CMD --line-terminator='\\r\\n'"
fi

# Add skip-header if detected
if echo "$FIRST_LINE" | grep -q -E '[a-zA-Z_]{3,}'; then
    HAS_NUMBERS=$(echo "$FIRST_LINE" | grep -o '[0-9]' | wc -l)
    if [ $HAS_NUMBERS -lt 2 ]; then
        SUGGESTED_CMD="$SUGGESTED_CMD --skip-header"
    fi
fi

echo "  $SUGGESTED_CMD"
echo ""
echo "Available options:"
echo "  --format=FORMAT          Format: csv, tsv, tab, custom"
echo "  --delimiter=CHAR         Field delimiter (e.g., '|', ',')"
echo "  --enclosure=CHAR         Field enclosure: \" or '"
echo "  --line-terminator=STR    Line ending: \\n or \\r\\n"
echo "  --skip-header            Skip first line (header row)"
echo "  -u USER -p               MySQL authentication"
echo ""

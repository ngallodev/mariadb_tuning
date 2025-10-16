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
TABS=$(head -100 "$FILE" | grep -c $'\t' || echo 0)
COMMAS=$(head -100 "$FILE" | grep -c ',' || echo 0)
PIPES=$(head -100 "$FILE" | grep -c '|' || echo 0)
SEMICOLONS=$(head -100 "$FILE" | grep -c ';' || echo 0)

echo "  Lines with tabs:       $TABS"
echo "  Lines with commas:     $COMMAS"
echo "  Lines with pipes:      $PIPES"
echo "  Lines with semicolons: $SEMICOLONS"
echo ""

# Determine likely delimiter
LIKELY_DELIMITER=""
if [ $TABS -gt 50 ]; then
    LIKELY_DELIMITER="TAB"
    echo -e "  ${GREEN}→ Likely delimiter: TAB (\\t)${NC}"
    echo "  Use default bulk_load.sh without changes"
elif [ $COMMAS -gt 50 ]; then
    LIKELY_DELIMITER="COMMA"
    echo -e "  ${GREEN}→ Likely delimiter: COMMA (,)${NC}"
    echo "  Modify bulk_load.sh: FIELDS TERMINATED BY ','"
elif [ $PIPES -gt 50 ]; then
    LIKELY_DELIMITER="PIPE"
    echo -e "  ${GREEN}→ Likely delimiter: PIPE (|)${NC}"
    echo "  Modify bulk_load.sh: FIELDS TERMINATED BY '|'"
elif [ $SEMICOLONS -gt 50 ]; then
    LIKELY_DELIMITER="SEMICOLON"
    echo -e "  ${GREEN}→ Likely delimiter: SEMICOLON (;)${NC}"
    echo "  Modify bulk_load.sh: FIELDS TERMINATED BY ';'"
else
    echo -e "  ${YELLOW}⚠ Could not determine delimiter reliably${NC}"
fi
echo ""

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
if [ $TAB_COUNT -gt 0 ]; then
    COLS=$((TAB_COUNT + 1))
    echo -e "  ${GREEN}Estimated columns (tab-based): $COLS${NC}"
elif [ $COMMA_COUNT -gt 0 ]; then
    COLS=$((COMMA_COUNT + 1))
    echo -e "  ${GREEN}Estimated columns (comma-based): $COLS${NC}"
elif [ $PIPE_COUNT -gt 0 ]; then
    COLS=$((PIPE_COUNT + 1))
    echo -e "  ${GREEN}Estimated columns (pipe-based): $COLS${NC}"
fi
echo ""

# Check for header row
echo -e "${GREEN}[5] Header Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if echo "$FIRST_LINE" | grep -q -E '[a-zA-Z_]{3,}'; then
    HAS_NUMBERS=$(echo "$FIRST_LINE" | grep -o '[0-9]' | wc -l)
    if [ $HAS_NUMBERS -lt 2 ]; then
        echo -e "  ${YELLOW}⚠ First line looks like a header row${NC}"
        echo "  Modify bulk_load.sh: IGNORE 1 LINES"
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
if [ ! -z "$LIKELY_DELIMITER" ]; then
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
    
    INCONSISTENT=$(awk -F"$DELIM" 'NF!='$EXPECTED' {print NR}' "$FILE" | head -10 | tr '\n' ',' | sed 's/,$//')
    if [ ! -z "$INCONSISTENT" ]; then
        echo -e "  ${RED}✗ Inconsistent column counts detected${NC}"
        echo "    Lines with wrong count: $INCONSISTENT"
        ISSUES=$((ISSUES + 1))
    else
        echo -e "  ${GREEN}✓ Consistent column counts${NC}"
    fi
fi

# Check for blank lines
BLANK_LINES=$(grep -c '^$' "$FILE" || echo 0)
if [ $BLANK_LINES -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ Found $BLANK_LINES blank lines${NC}"
    echo "    Consider removing: sed -i '/^$/d' $FILE"
    ISSUES=$((ISSUES + 1))
else
    echo -e "  ${GREEN}✓ No blank lines${NC}"
fi

# Check for very long lines
MAX_LINE=$(awk '{print length}' "$FILE" | sort -n | tail -1)
if [ $MAX_LINE -gt 10000 ]; then
    echo -e "  ${YELLOW}⚠ Very long line detected: $MAX_LINE characters${NC}"
    echo "    May need to increase max_allowed_packet"
    ISSUES=$((ISSUES + 1))
else
    echo -e "  ${GREEN}✓ Line lengths reasonable (max: $MAX_LINE chars)${NC}"
fi

# Check for NULL indicators
NULL_INDICATORS=$(head -100 "$FILE" | grep -c '\\N' || echo 0)
if [ $NULL_INDICATORS -gt 0 ]; then
    echo -e "  ${GREEN}✓ Found \\N NULL indicators (MariaDB native)${NC}"
fi

echo ""

# Summary and recommendations
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}SUMMARY & RECOMMENDATIONS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ File looks good for bulk loading!${NC}"
else
    echo -e "${YELLOW}⚠ Found $ISSUES potential issue(s) - review above${NC}"
fi
echo ""

echo "Recommended bulk_load.sh settings:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
echo "  ./bulk_load.sh database table $FILE"
echo ""

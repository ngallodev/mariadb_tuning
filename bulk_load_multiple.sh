#!/bin/bash
#
# MariaDB Multiple File Bulk Load Script
# Enables extreme mode once, loads all files, then restores settings
#
# Usage: ./bulk_load_multiple.sh <database> <table> <file1> [file2] [file3] ...
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$#" -lt 3 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage: $0 <database> <table> <file1> [file2] [file3] ..."
    echo ""
    echo "MySQL Options (optional, must come after files):"
    echo "  -u USER    MySQL username"
    echo "  -p         Prompt for password"
    echo "  -h HOST    MySQL host"
    echo ""
    echo "Example:"
    echo "  $0 mydb mytable chunk1.tsv chunk2.tsv chunk3.tsv"
    echo "  $0 mydb mytable /path/chunks/*.tsv -u root -p"
    exit 1
fi

DATABASE=$1
TABLE=$2
shift 2

# Separate files from MySQL options
declare -a FILES=()
declare -a MYSQL_OPTS=()
PARSING_MYSQL_OPTS=false

for arg in "$@"; do
    if [[ "$arg" =~ ^- ]]; then
        PARSING_MYSQL_OPTS=true
        MYSQL_OPTS+=("$arg")
    elif [ "$PARSING_MYSQL_OPTS" = true ]; then
        MYSQL_OPTS+=("$arg")
    else
        FILES+=("$arg")
    fi
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No files specified${NC}"
    exit 1
fi

# Build mysql command
MYSQL_CMD="mysql"
if [ ${#MYSQL_OPTS[@]} -gt 0 ]; then
    MYSQL_CMD="mysql ${MYSQL_OPTS[@]}"
fi

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}MariaDB Multiple File Bulk Load${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "Database: ${YELLOW}$DATABASE${NC}"
echo -e "Table: ${YELLOW}$TABLE${NC}"
echo -e "Files to load: ${YELLOW}${#FILES[@]}${NC}"
echo ""

# Verify all files exist
echo -e "${GREEN}Verifying files...${NC}"
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File not found: $file${NC}"
        exit 1
    fi
    # Get absolute path
    FILE_ABS=$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")
    echo "  ✓ $(basename "$file") ($(du -h "$FILE_ABS" | cut -f1))"
done
echo ""

# Capture original GLOBAL settings
echo -e "${GREEN}[1/4] Capturing original server settings...${NC}"
ORIG_MAX_PACKET=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.max_allowed_packet;")
ORIG_QUERY_CACHE_TYPE=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.query_cache_type;" 2>/dev/null || echo "0")
ORIG_QUERY_CACHE_SIZE=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.query_cache_size;" 2>/dev/null || echo "0")
ORIG_FLUSH_LOG=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_flush_log_at_trx_commit;")
ORIG_FLUSH_NEIGHBORS=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_flush_neighbors;")
ORIG_ADAPTIVE_HASH=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_adaptive_hash_index;")
ORIG_CHANGE_BUFFER=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_change_buffer_max_size;")
ORIG_IO_CAPACITY=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_io_capacity;")
ORIG_IO_CAPACITY_MAX=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_io_capacity_max;")
echo -e "${GREEN}✓ Original settings captured${NC}"
echo ""

# Cleanup function for trap handler
cleanup() {
    echo ""
    echo -e "${YELLOW}===========================================${NC}"
    echo -e "${YELLOW}⚠ INTERRUPTED - Restoring settings...${NC}"
    echo -e "${YELLOW}===========================================${NC}"

    $MYSQL_CMD <<EOF 2>/dev/null
SET GLOBAL innodb_flush_log_at_trx_commit = $ORIG_FLUSH_LOG;
SET GLOBAL innodb_flush_neighbors = $ORIG_FLUSH_NEIGHBORS;
SET GLOBAL innodb_adaptive_hash_index = $ORIG_ADAPTIVE_HASH;
SET GLOBAL innodb_change_buffer_max_size = $ORIG_CHANGE_BUFFER;
SET GLOBAL innodb_io_capacity = $ORIG_IO_CAPACITY;
SET GLOBAL innodb_io_capacity_max = $ORIG_IO_CAPACITY_MAX;
SET GLOBAL max_allowed_packet = $ORIG_MAX_PACKET;
EOF

    echo -e "${YELLOW}✓ Settings restored${NC}"
    exit 1
}

# Trap interrupts
trap cleanup INT TERM ERR

# Enable extreme mode (GLOBAL settings)
echo -e "${GREEN}[2/4] Enabling EXTREME MODE...${NC}"
$MYSQL_CMD <<EOF
-- GLOBAL optimizations for bulk load
SET GLOBAL max_allowed_packet = 1073741824;
SET GLOBAL query_cache_type = 0;
SET GLOBAL query_cache_size = 0;
SET GLOBAL innodb_flush_log_at_trx_commit = 0;
SET GLOBAL innodb_flush_neighbors = 0;
SET GLOBAL innodb_adaptive_hash_index = OFF;
SET GLOBAL innodb_change_buffer_max_size = 50;
SET GLOBAL innodb_io_capacity = 2000;
SET GLOBAL innodb_io_capacity_max = 4000;
SELECT 'EXTREME MODE ENABLED' AS Status;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Extreme mode enabled${NC}"
else
    echo -e "${RED}✗ Failed to enable extreme mode${NC}"
    exit 1
fi
echo ""

# Load all files
echo -e "${GREEN}[3/4] Loading ${#FILES[@]} files...${NC}"
TOTAL_START=$(date +%s)
FILE_NUM=0
TOTAL_ROWS=0

for file in "${FILES[@]}"; do
    FILE_NUM=$((FILE_NUM + 1))
    FILE_ABS=$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")

    echo -e "${YELLOW}  [$FILE_NUM/${#FILES[@]}] Loading $(basename "$file")...${NC}"
    START_TIME=$(date +%s)

    # Get row count before
    ROWS_BEFORE=$($MYSQL_CMD -sN -e "SELECT COUNT(*) FROM \`$DATABASE\`.\`$TABLE\`;")

    # Load the file
    $MYSQL_CMD <<EOF
USE \`$DATABASE\`;
SET SESSION sql_log_bin = 0;
SET SESSION foreign_key_checks = 0;
SET SESSION unique_checks = 0;
SET SESSION autocommit = 0;
SET SESSION bulk_insert_buffer_size = 512 * 1024 * 1024;
SET SESSION sort_buffer_size = 512 * 1024 * 1024;
SET SESSION read_buffer_size = 16 * 1024 * 1024;
SET SESSION read_rnd_buffer_size = 32 * 1024 * 1024;
SET SESSION join_buffer_size = 32 * 1024 * 1024;
SET SESSION myisam_sort_buffer_size = 1024 * 1024 * 1024;

LOAD DATA LOCAL INFILE '$FILE_ABS'
INTO TABLE \`$TABLE\`
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n';

COMMIT;
EOF

    if [ $? -eq 0 ]; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        # Get row count after
        ROWS_AFTER=$($MYSQL_CMD -sN -e "SELECT COUNT(*) FROM \`$DATABASE\`.\`$TABLE\`;")
        ROWS_LOADED=$((ROWS_AFTER - ROWS_BEFORE))
        TOTAL_ROWS=$((TOTAL_ROWS + ROWS_LOADED))

        if [ $DURATION -gt 0 ]; then
            ROWS_PER_SEC=$((ROWS_LOADED / DURATION))
            echo -e "${GREEN}    ✓ Loaded $ROWS_LOADED rows in ${DURATION}s (${ROWS_PER_SEC} rows/sec)${NC}"
        else
            echo -e "${GREEN}    ✓ Loaded $ROWS_LOADED rows in <1s${NC}"
        fi
    else
        echo -e "${RED}    ✗ Failed to load file${NC}"
        cleanup
        exit 1
    fi
done

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo ""
echo -e "${GREEN}✓ All files loaded successfully${NC}"
echo -e "  Total rows: ${YELLOW}$TOTAL_ROWS${NC}"
echo -e "  Total time: ${YELLOW}${TOTAL_DURATION}s${NC}"
if [ $TOTAL_DURATION -gt 0 ]; then
    AVG_ROWS_PER_SEC=$((TOTAL_ROWS / TOTAL_DURATION))
    echo -e "  Average: ${YELLOW}${AVG_ROWS_PER_SEC} rows/sec${NC}"
fi
echo ""

# Restore settings and analyze table
echo -e "${GREEN}[4/4] Restoring settings and analyzing table...${NC}"
$MYSQL_CMD <<EOF
-- Restore GLOBAL settings
SET GLOBAL innodb_flush_log_at_trx_commit = $ORIG_FLUSH_LOG;
SET GLOBAL innodb_flush_neighbors = $ORIG_FLUSH_NEIGHBORS;
SET GLOBAL innodb_adaptive_hash_index = $ORIG_ADAPTIVE_HASH;
SET GLOBAL innodb_change_buffer_max_size = $ORIG_CHANGE_BUFFER;
SET GLOBAL innodb_io_capacity = $ORIG_IO_CAPACITY;
SET GLOBAL innodb_io_capacity_max = $ORIG_IO_CAPACITY_MAX;
SET GLOBAL max_allowed_packet = $ORIG_MAX_PACKET;

-- Analyze table
USE \`$DATABASE\`;
ANALYZE TABLE \`$TABLE\`;

SELECT 'Settings restored, table analyzed' AS Status;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Settings restored and table optimized${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Failed to restore some settings${NC}"
fi

echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}✓ Bulk load completed successfully!${NC}"
echo -e "${GREEN}===========================================${NC}"

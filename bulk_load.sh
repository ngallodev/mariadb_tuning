#!/bin/bash
#
# MariaDB Bulk Data Load Script
# Usage: ./bulk_load.sh <database> <table> <data_file.txt>
#
# This script optimizes MariaDB for bulk loading, loads data, and restores settings
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ "$#" -lt 3 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage: $0 <database> <table> <data_file> [options]"
    echo ""
    echo "Format Options:"
    echo "  --format=FORMAT        Format type: csv, tsv, tab, custom (default: tab)"
    echo "  --delimiter=CHAR       Field delimiter (default: tab)"
    echo "  --enclosure=CHAR       Field enclosure: \" or ' (for CSV)"
    echo "  --line-terminator=STR  Line ending: \\n or \\r\\n (default: \\n)"
    echo "  --skip-header          Skip first line (header row)"
    echo ""
    echo "Table Options:"
    echo "  --truncate             Delete all records before loading"
    echo ""
    echo "MySQL Options:"
    echo "  -u USER                MySQL username"
    echo "  -p                     Prompt for password"
    echo "  -h HOST                MySQL host"
    echo "  (any other mysql client options)"
    echo ""
    echo "Examples:"
    echo "  $0 mydb mytable data.txt                    # Tab-delimited (default)"
    echo "  $0 mydb mytable data.csv --format=csv       # CSV with auto-detection"
    echo "  $0 mydb mytable data.csv --format=csv --skip-header"
    echo "  $0 mydb mytable data.txt --delimiter='|'    # Custom pipe delimiter"
    echo "  $0 mydb mytable data.txt --truncate         # Clear table before load"
    echo "  $0 mydb mytable data.txt -u root -p         # With MySQL options"
    exit 1
fi

DATABASE=$1
TABLE=$2
DATAFILE=$3

# Default format settings (tab-delimited for backward compatibility)
FORMAT="tab"
DELIMITER='\t'
ENCLOSURE=""
LINE_TERMINATOR='\n'
IGNORE_LINES=0
TRUNCATE_TABLE=false
MYSQL_OPTS=""  # Default MySQL options

# Parse optional arguments (format options and MySQL options)
shift 3  # Remove first 3 positional args
while [[ $# -gt 0 ]]; do
    case $1 in
        --format=*)
            FORMAT="${1#*=}"
            # Validate format
            if [[ ! "$FORMAT" =~ ^(csv|tsv|tab|custom)$ ]]; then
                echo -e "${RED}Error: Invalid format '$FORMAT'. Must be: csv, tsv, tab, or custom${NC}"
                exit 1
            fi
            # Set defaults based on format
            case $FORMAT in
                csv)
                    DELIMITER=','
                    ENCLOSURE='ENCLOSED BY '"'"'"'"'"''
                    LINE_TERMINATOR='\n'
                    ;;
                tsv|tab)
                    DELIMITER='\t'
                    ENCLOSURE=""
                    LINE_TERMINATOR='\n'
                    ;;
            esac
            ;;
        --delimiter=*)
            DELIM_RAW="${1#*=}"
            # Validate delimiter: single character, no quotes or backslashes
            if [[ ${#DELIM_RAW} -ne 1 ]]; then
                echo -e "${RED}Error: Delimiter must be exactly one character${NC}"
                exit 1
            fi
            if [[ "$DELIM_RAW" =~ [\'\"\\] ]]; then
                echo -e "${RED}Error: Delimiter cannot be quote or backslash${NC}"
                exit 1
            fi
            DELIMITER="$DELIM_RAW"
            FORMAT="custom"
            ;;
        --enclosure=*)
            ENC_RAW="${1#*=}"
            if [[ "$ENC_RAW" =~ ^[\"\']$ ]]; then
                ENCLOSURE="ENCLOSED BY '$ENC_RAW'"
            else
                echo -e "${RED}Error: Enclosure must be \" or '${NC}"
                exit 1
            fi
            ;;
        --line-terminator=*)
            TERM_RAW="${1#*=}"
            case $TERM_RAW in
                '\n'|'\\n')
                    LINE_TERMINATOR='\n'
                    ;;
                '\r\n'|'\\r\\n')
                    LINE_TERMINATOR='\r\n'
                    ;;
                *)
                    echo -e "${RED}Error: Line terminator must be \\n or \\r\\n${NC}"
                    exit 1
                    ;;
            esac
            ;;
        --skip-header)
            IGNORE_LINES=1
            ;;
        --truncate)
            TRUNCATE_TABLE=true
            ;;
        -*)
            # Treat as MySQL option
            MYSQL_OPTS="$MYSQL_OPTS $1"
            ;;
        *)
            # Unknown option
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            exit 1
            ;;
    esac
    shift
done

# Check if data file exists
if [ ! -f "$DATAFILE" ]; then
    echo -e "${RED}Error: Data file '$DATAFILE' not found${NC}"
    exit 1
fi

# Get absolute path of data file (POSIX-compatible, works on macOS/BSD/Linux)
DATAFILE=$(cd "$(dirname "$DATAFILE")" && pwd -P)/$(basename "$DATAFILE")

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}MariaDB Bulk Data Load Script${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "Database: ${YELLOW}$DATABASE${NC}"
echo -e "Table: ${YELLOW}$TABLE${NC}"
echo -e "Data File: ${YELLOW}$DATAFILE${NC}"
echo -e "File Size: ${YELLOW}$(du -h "$DATAFILE" | cut -f1)${NC}"
echo -e "Format: ${YELLOW}$FORMAT${NC}"
OPTIONS=""
if [ "$IGNORE_LINES" -gt 0 ]; then
    OPTIONS="Skip $IGNORE_LINES header line(s)"
fi
if [ "$TRUNCATE_TABLE" = true ]; then
    if [ -n "$OPTIONS" ]; then
        OPTIONS="$OPTIONS, Truncate table"
    else
        OPTIONS="Truncate table"
    fi
fi
if [ -n "$OPTIONS" ]; then
    echo -e "Options: ${YELLOW}$OPTIONS${NC}"
fi
echo ""

# Capture original GLOBAL settings before making changes
echo -e "${GREEN}Capturing original server settings...${NC}"
ORIG_MAX_PACKET=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.max_allowed_packet;")
ORIG_QUERY_CACHE_TYPE=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.query_cache_type;" 2>/dev/null || echo "0")
ORIG_QUERY_CACHE_SIZE=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.query_cache_size;" 2>/dev/null || echo "0")
ORIG_FLUSH_LOG=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_flush_log_at_trx_commit;")
ORIG_FLUSH_NEIGHBORS=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_flush_neighbors;")
# ORIG_LOG_BUFFER=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_log_buffer_size;")
ORIG_ADAPTIVE_HASH=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_adaptive_hash_index;")
ORIG_CHANGE_BUFFER=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_change_buffer_max_size;")
ORIG_IO_CAPACITY=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_io_capacity;")
ORIG_IO_CAPACITY_MAX=$(mysql $MYSQL_OPTS -sN -e "SELECT @@GLOBAL.innodb_io_capacity_max;")
echo -e "${GREEN}✓ Original settings captured${NC}"
echo ""

# Cleanup function for trap handler
cleanup() {
    local exit_code=$?
    echo ""
    echo -e "${YELLOW}===========================================${NC}"
    echo -e "${YELLOW}⚠ INTERRUPTED - Restoring settings...${NC}"
    echo -e "${YELLOW}===========================================${NC}"

    # Restore GLOBAL settings to original values
    mysql $MYSQL_OPTS <<EOF 2>/dev/null
-- Restore GLOBAL settings to original values
SET GLOBAL innodb_flush_log_at_trx_commit = $ORIG_FLUSH_LOG;
SET GLOBAL innodb_flush_neighbors = $ORIG_FLUSH_NEIGHBORS;
SET GLOBAL innodb_adaptive_hash_index = $ORIG_ADAPTIVE_HASH;
SET GLOBAL innodb_change_buffer_max_size = $ORIG_CHANGE_BUFFER;
SET GLOBAL innodb_io_capacity = $ORIG_IO_CAPACITY;
SET GLOBAL innodb_io_capacity_max = $ORIG_IO_CAPACITY_MAX;
SET GLOBAL max_allowed_packet = $ORIG_MAX_PACKET;
EOF

    echo -e "${GREEN}✓ Settings restored to original values${NC}"
    echo -e "${RED}✗ Bulk load interrupted - table may be incomplete${NC}"
    exit 1
}

# Set trap to catch interrupts and errors
trap cleanup INT TERM ERR

# Step 1: Apply pre-load optimizations
echo -e "${GREEN}[1/4] Applying EXTREME pre-load optimizations...${NC}"
mysql $MYSQL_OPTS <<EOF
-- GLOBAL optimizations (affects entire server)
-- NOTE: sql_log_bin is SESSION-only to avoid breaking replication
SET GLOBAL max_allowed_packet = 1073741824;
SET GLOBAL query_cache_type = 0;
SET GLOBAL query_cache_size = 0;
SET GLOBAL innodb_flush_log_at_trx_commit = 0;
SET GLOBAL innodb_flush_neighbors = 0;
-- SET GLOBAL innodb_log_buffer_size = 256 * 1024 * 1024;
SET GLOBAL innodb_adaptive_hash_index = OFF;
SET GLOBAL innodb_change_buffer_max_size = 50;
SET GLOBAL innodb_io_capacity = 2000;
SET GLOBAL innodb_io_capacity_max = 4000;

-- SESSION optimizations (affects this connection)
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

SELECT 'EXTREME MODE: Pre-load optimizations applied' AS Status;
SELECT 'Global flush_log_at_trx_commit set to 0 for maximum speed' AS Info;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Pre-load optimizations applied${NC}"
else
    echo -e "${RED}✗ Failed to apply optimizations${NC}"
    exit 1
fi

echo ""

# Step 2: Disable keys on MyISAM tables (speeds up bulk inserts)
echo -e "${GREEN}[2/4] Checking table engine and preparing...${NC}"
ENGINE=$(mysql $MYSQL_OPTS -sN -e "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DATABASE' AND TABLE_NAME='$TABLE';")

if [ "$ENGINE" == "MyISAM" ]; then
    echo -e "Table engine: ${YELLOW}MyISAM${NC} - Disabling keys..."
    mysql $MYSQL_OPTS -e "USE \`$DATABASE\`; ALTER TABLE \`$TABLE\` DISABLE KEYS;"
    echo -e "${GREEN}✓ Keys disabled${NC}"
elif [ "$ENGINE" == "InnoDB" ]; then
    echo -e "Table engine: ${YELLOW}InnoDB${NC}"
else
    echo -e "Table engine: ${YELLOW}$ENGINE${NC}"
fi

echo ""

# Step 3: Truncate table if requested
if [ "$TRUNCATE_TABLE" = true ]; then
    echo -e "${GREEN}[3/5] Truncating table...${NC}"
    mysql $MYSQL_OPTS -e "USE \`$DATABASE\`; TRUNCATE TABLE \`$TABLE\`;"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Table truncated${NC}"
    else
        echo -e "${RED}✗ Failed to truncate table${NC}"
        exit 1
    fi
    echo ""
    LOAD_STEP="[4/5]"
    RESTORE_STEP="[5/5]"
else
    LOAD_STEP="[3/4]"
    RESTORE_STEP="[4/4]"
fi

# Step 4 (or 3): Load data
echo -e "${GREEN}${LOAD_STEP} Loading data...${NC}"
START_TIME=$(date +%s)

# Build LOAD DATA INFILE command with format-specific options
mysql $MYSQL_OPTS <<EOF
USE \`$DATABASE\`;
SET SESSION sql_log_bin = 0;
SET SESSION foreign_key_checks = 0;
SET SESSION unique_checks = 0;
SET SESSION autocommit = 0;

LOAD DATA LOCAL INFILE '$DATAFILE'
INTO TABLE \`$TABLE\`
FIELDS TERMINATED BY '$DELIMITER' $ENCLOSURE
LINES TERMINATED BY '$LINE_TERMINATOR'
IGNORE $IGNORE_LINES LINES;

COMMIT;
SELECT 'Data loaded successfully' AS Status;
EOF

if [ $? -eq 0 ]; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    echo -e "${GREEN}✓ Data loaded successfully in ${DURATION} seconds${NC}"
else
    echo -e "${RED}✗ Failed to load data${NC}"
    exit 1
fi

echo ""

# Step 5 (or 4): Re-enable keys and restore settings
echo -e "${GREEN}${RESTORE_STEP} Restoring settings to original values and optimizing table...${NC}"

if [ "$ENGINE" == "MyISAM" ]; then
    echo -e "Re-enabling keys for MyISAM table..."
    mysql $MYSQL_OPTS -e "USE \`$DATABASE\`; ALTER TABLE \`$TABLE\` ENABLE KEYS;"
fi

# Restore GLOBAL settings to original values
mysql $MYSQL_OPTS <<EOF
-- Restore GLOBAL settings to original values
SET GLOBAL innodb_flush_log_at_trx_commit = $ORIG_FLUSH_LOG;
SET GLOBAL innodb_flush_neighbors = $ORIG_FLUSH_NEIGHBORS;
-- SET GLOBAL innodb_log_buffer_size = $ORIG_LOG_BUFFER;
SET GLOBAL innodb_adaptive_hash_index = $ORIG_ADAPTIVE_HASH;
SET GLOBAL innodb_change_buffer_max_size = $ORIG_CHANGE_BUFFER;
SET GLOBAL innodb_io_capacity = $ORIG_IO_CAPACITY;
SET GLOBAL innodb_io_capacity_max = $ORIG_IO_CAPACITY_MAX;
SET GLOBAL max_allowed_packet = $ORIG_MAX_PACKET;

-- Restore SESSION settings
USE \`$DATABASE\`;
SET SESSION autocommit = 1;
SET SESSION unique_checks = 1;
SET SESSION foreign_key_checks = 1;
SET SESSION sql_log_bin = 1;

-- Analyze table to update statistics
ANALYZE TABLE \`$TABLE\`;

SELECT 'Settings restored to original values, table analyzed' AS Status;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Settings restored${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Failed to restore some settings${NC}"
fi

echo ""

# Display statistics
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}Load Complete!${NC}"
echo -e "${GREEN}===========================================${NC}"

ROW_COUNT=$(mysql $MYSQL_OPTS -sN -e "SELECT COUNT(*) FROM \`$DATABASE\`.\`$TABLE\`;")
echo -e "Total rows in table: ${YELLOW}$ROW_COUNT${NC}"
echo -e "Load duration: ${YELLOW}${DURATION} seconds${NC}"

if [ $DURATION -gt 0 ]; then
    ROWS_PER_SEC=$((ROW_COUNT / DURATION))
    echo -e "Average speed: ${YELLOW}${ROWS_PER_SEC} rows/second${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"

# Clear trap on successful completion
trap - INT TERM ERR

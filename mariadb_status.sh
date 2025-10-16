#!/bin/bash
#
# MariaDB Mode & Resource Status Monitor
# Shows current mode (Conservative vs Extreme) and resource usage
#
# Usage: ./mariadb_status.sh [mysql_options]
# Example: ./mariadb_status.sh "-u root -p"
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

MYSQL_OPTS=${1:-" -p"}
MYSQL_CMD="sudo mariadb -u root"

echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║         MariaDB Mode & Resource Status Monitor            ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get MariaDB settings
FLUSH_MODE=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_flush_log_at_trx_commit;" 2>/dev/null)
ADAPTIVE_HASH=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_adaptive_hash_index;" 2>/dev/null)
IO_CAPACITY=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_io_capacity;" 2>/dev/null)
IO_CAPACITY_MAX=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_io_capacity_max;" 2>/dev/null)
BUFFER_POOL=$($MYSQL_CMD -sN -e "SELECT @@GLOBAL.innodb_buffer_pool_size/1024/1024/1024;" 2>/dev/null)

if [ -z "$FLUSH_MODE" ]; then
    echo -e "${RED}Error: Could not connect to MariaDB${NC}"
    echo "Check your credentials or use: $0 '-u username -p'"
    exit 1
fi

# Determine mode

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}CURRENT MODE DETECTION${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$FLUSH_MODE" = "0" ] && [ "$IO_CAPACITY" -ge "1000" ]; then
    echo -e "Mode: ${YELLOW}${BOLD}⚡ EXTREME MODE (Bulk Loading Active)${NC}"
    MODE="extreme"
elif [ "$FLUSH_MODE" = "1" ] && [ "$IO_CAPACITY" -lt "500" ]; then
    echo -e "Mode: ${GREEN}${BOLD}✓ CONSERVATIVE MODE (Normal Operations)${NC}"
    MODE="conservative"
else
    echo -e "Mode: ${YELLOW}${BOLD}⚠ MIXED MODE (Partial Settings)${NC}"
    MODE="mixed"
fi
echo ""

# Show key settings
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}KEY MARIADB SETTINGS${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

printf "%-40s" "innodb_flush_log_at_trx_commit:"
if [ "$FLUSH_MODE" = "0" ]; then
    echo -e "${YELLOW}$FLUSH_MODE (EXTREME - every ~1s)${NC}"
elif [ "$FLUSH_MODE" = "1" ]; then
    echo -e "${GREEN}$FLUSH_MODE (CONSERVATIVE - ACID)${NC}"
else
    echo -e "${BLUE}$FLUSH_MODE${NC}"
fi

printf "%-40s" "innodb_adaptive_hash_index:"
if [ "$ADAPTIVE_HASH" = "0" ] || [ "$ADAPTIVE_HASH" = "OFF" ]; then
    echo -e "${YELLOW}OFF (EXTREME)${NC}"
else
    echo -e "${GREEN}ON (CONSERVATIVE)${NC}"
fi

printf "%-40s" "innodb_io_capacity:"
if [ "$IO_CAPACITY" -ge "1000" ]; then
    echo -e "${YELLOW}$IO_CAPACITY (EXTREME)${NC}"
else
    echo -e "${GREEN}$IO_CAPACITY (CONSERVATIVE)${NC}"
fi

printf "%-40s" "innodb_io_capacity_max:"
if [ "$IO_CAPACITY_MAX" -ge "3000" ]; then
    echo -e "${YELLOW}$IO_CAPACITY_MAX (EXTREME)${NC}"
else
    echo -e "${GREEN}$IO_CAPACITY_MAX (CONSERVATIVE)${NC}"
fi

printf "%-40s" "innodb_buffer_pool_size:"
echo -e "${CYAN}${BUFFER_POOL}GB${NC}"

echo ""

# Show resource usage
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}SYSTEM RESOURCE USAGE${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Memory usage
TOTAL_MEM=$(free -g | awk '/^Mem:/ {print $2}')
USED_MEM=$(free -g | awk '/^Mem:/ {print $3}')
AVAIL_MEM=$(free -g | awk '/^Mem:/ {print $7}')
MYSQL_MEM=$(ps aux | grep mysqld | grep -v grep | awk '{sum+=$6} END {print sum/1024/1024}' | xargs printf "%.1f")

echo -e "${BOLD}Memory:${NC}"
echo "  Total:          ${TOTAL_MEM}GB"
echo "  Used:           ${USED_MEM}GB"
echo "  Available:      ${AVAIL_MEM}GB"
echo "  MariaDB:        ${MYSQL_MEM}GB"

if [ "$MODE" = "extreme" ]; then
    echo -e "  Expected:       ${YELLOW}80-100GB during bulk loads${NC}"
elif [ "$MODE" = "conservative" ]; then
    echo -e "  Expected:       ${GREEN}70-80GB during normal ops${NC}"
fi
echo ""

# CPU usage
CPU_COUNT=$(nproc)
MYSQL_CPU=$(ps aux | grep mysqld | grep -v grep | awk '{print $3}' | head -1)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')

echo -e "${BOLD}CPU:${NC}"
echo "  Total cores:    $CPU_COUNT"
echo "  MariaDB usage:  ${MYSQL_CPU}%"
echo "  Load average:  $LOAD_AVG"

if [ "$MODE" = "extreme" ]; then
    echo -e "  Expected:       ${YELLOW}200-800% during bulk loads (2-8 cores)${NC}"
elif [ "$MODE" = "conservative" ]; then
    echo -e "  Expected:       ${GREEN}<100% during normal ops (1-2 cores)${NC}"
fi
echo ""

# Disk I/O (if iostat is available)
if command -v iostat &> /dev/null; then
    echo -e "${BOLD}Disk I/O (Last 5 seconds):${NC}"
    iostat -x 1 2 | grep -A 100 "Device" | tail -n +2 | head -5 | awk '{printf "  %-10s r/s: %-8s w/s: %-8s util: %s%%\n", $1, $4, $5, $NF}'
    echo ""
fi

# Active connections
CONNECTIONS=$($MYSQL_CMD -sN -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
MAX_CONNECTIONS=$($MYSQL_CMD -sN -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')

echo -e "${BOLD}Connections:${NC}"
echo "  Active:         $CONNECTIONS"
echo "  Max allowed:    $MAX_CONNECTIONS"
echo ""

# Buffer pool status
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}INNODB BUFFER POOL STATUS${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

$MYSQL_CMD -e "
SELECT 
    CONCAT(ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2), ' GB') AS 'Total Data Size',
    CONCAT(ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2), ' GB') AS 'Buffer Pool Size',
    CONCAT(ROUND((SELECT SUM(DATA_LENGTH + INDEX_LENGTH) 
                  FROM information_schema.TABLES 
                  WHERE ENGINE='InnoDB') / @@innodb_buffer_pool_size * 100, 1), '%') AS 'Data/Pool Ratio'
FROM information_schema.TABLES 
WHERE ENGINE='InnoDB';
" 2>/dev/null | tail -n +2

echo ""

# Show recommendations based on mode
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}RECOMMENDATIONS${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$MODE" = "extreme" ]; then
    echo -e "${YELLOW}⚡ Extreme mode is active - good for bulk loading!${NC}"
    echo "  • Ensure no other critical operations are running"
    echo "  • Remember to restore to conservative mode after loading"
    echo "  • Run: mysql -u root -p < mariadb_postload.sql"
elif [ "$MODE" = "conservative" ]; then
    echo -e "${GREEN}✓ Conservative mode - optimal for normal operations${NC}"
    echo "  • System ready for regular database queries"
    echo "  • For bulk loads, run: ./bulk_load.sh or mariadb_preload.sql"
else
    echo -e "${YELLOW}⚠ Mixed mode detected - some settings are inconsistent${NC}"
    echo "  • Run mariadb_postload.sql to restore conservative mode"
    echo "  • Or run mariadb_preload.sql to enable extreme mode"
fi

echo ""

# Quick commands
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}QUICK COMMANDS${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Switch to extreme mode:    mysql -u root -p < mariadb_preload.sql"
echo "Restore conservative:      mysql -u root -p < mariadb_postload.sql"
echo "Automated bulk load:       ./bulk_load.sh database table file.txt"
echo "Watch resources:           watch -n 2 './mariadb_status.sh \"$MYSQL_OPTS\"'"
echo ""

#!/bin/bash
#
# Mock MySQL/MariaDB client for testing
# Simulates mysql command responses without requiring actual database
#

MOCK_MODE="${MOCK_MODE:-normal}"
MOCK_FAIL="${MOCK_FAIL:-0}"

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e)
                QUERY="$2"
                shift 2
                ;;
            -sN)
                SILENT_MODE=1
                shift
                ;;
            --database=*)
                DATABASE="${1#*=}"
                shift
                ;;
            -u)
                USER="$2"
                shift 2
                ;;
            -p*)
                # Password flag (ignore for mocking)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

parse_args "$@"

# Mock failure if requested
if [ "$MOCK_FAIL" = "1" ]; then
    echo "ERROR 1045 (28000): Access denied for user" >&2
    exit 1
fi

# Mock responses based on query
if [[ "$QUERY" == *"innodb_flush_log_at_trx_commit"* ]]; then
    if [ "$MOCK_MODE" = "extreme" ]; then
        echo "0"
    else
        echo "1"
    fi
elif [[ "$QUERY" == *"innodb_io_capacity"* ]] && [[ "$QUERY" != *"max"* ]]; then
    if [ "$MOCK_MODE" = "extreme" ]; then
        echo "2000"
    else
        echo "200"
    fi
elif [[ "$QUERY" == *"innodb_adaptive_hash_index"* ]]; then
    if [ "$MOCK_MODE" = "extreme" ]; then
        echo "0"
    else
        echo "1"
    fi
elif [[ "$QUERY" == *"innodb_buffer_pool_size"* ]]; then
    echo "64"  # 64GB
elif [[ "$QUERY" == *"max_connections"* ]]; then
    echo "200"
elif [[ "$QUERY" == *"Threads_connected"* ]]; then
    echo -e "Threads_connected\t25"
elif [[ "$QUERY" == *"ENGINE FROM information_schema.TABLES"* ]]; then
    echo "InnoDB"
elif [[ "$QUERY" == *"COUNT(*)"* ]]; then
    echo "1000000"  # Mock row count
elif [[ "$QUERY" == *"SHOW VARIABLES"* ]]; then
    echo "innodb_flush_log_at_trx_commit	1"
    echo "innodb_adaptive_hash_index	ON"
    echo "innodb_io_capacity	200"
elif [[ "$QUERY" == *"SET GLOBAL"* ]] || [[ "$QUERY" == *"SET SESSION"* ]]; then
    # SET queries succeed silently
    exit 0
elif [[ "$QUERY" == *"ANALYZE TABLE"* ]]; then
    echo "Table	Op	Msg_type	Msg_text"
    echo "test.testtable	analyze	status	OK"
elif [[ "$QUERY" == *"LOAD DATA"* ]]; then
    # Simulate successful load
    echo "Query OK, 50000 rows affected (2.34 sec)"
else
    # Default success response
    echo "Query OK, 0 rows affected"
fi

exit 0

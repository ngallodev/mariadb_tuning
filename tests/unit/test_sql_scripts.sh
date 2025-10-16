#!/bin/bash
#
# Unit tests for SQL scripts (preload/postload)
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

# ===========================
# Test: Preload SQL syntax
# ===========================
test_preload_sql_syntax() {
    test_start "mariadb_preload.sql has valid SQL syntax"

    # Check for basic SQL keywords
    content=$(cat "$PROJECT_ROOT/mariadb_preload.sql")

    assert_contains "$content" "SET GLOBAL" "Should contain SET GLOBAL statements"
    assert_contains "$content" "SET SESSION" "Should contain SET SESSION statements"

    test_pass
}

# ===========================
# Test: Preload sets extreme mode
# ===========================
test_preload_sets_extreme_mode() {
    test_start "mariadb_preload.sql sets extreme mode parameters"

    content=$(cat "$PROJECT_ROOT/mariadb_preload.sql")

    assert_contains "$content" "innodb_flush_log_at_trx_commit = 0" "Should set flush to 0"
    assert_contains "$content" "innodb_io_capacity = 2000" "Should set IO capacity to 2000"
    assert_contains "$content" "innodb_adaptive_hash_index = OFF" "Should disable adaptive hash"

    test_pass
}

# ===========================
# Test: Preload disables safety checks
# ===========================
test_preload_disables_safety_checks() {
    test_start "mariadb_preload.sql disables safety checks"

    content=$(cat "$PROJECT_ROOT/mariadb_preload.sql")

    assert_contains "$content" "foreign_key_checks = 0" "Should disable foreign key checks"
    assert_contains "$content" "unique_checks = 0" "Should disable unique checks"
    assert_contains "$content" "autocommit = 0" "Should disable autocommit"

    test_pass
}

# ===========================
# Test: Preload increases buffer sizes
# ===========================
test_preload_increases_buffers() {
    test_start "mariadb_preload.sql increases buffer sizes"

    content=$(cat "$PROJECT_ROOT/mariadb_preload.sql")

    assert_contains "$content" "bulk_insert_buffer_size" "Should set bulk insert buffer"
    assert_contains "$content" "sort_buffer_size" "Should set sort buffer"
    assert_contains "$content" "read_buffer_size" "Should set read buffer"

    test_pass
}

# ===========================
# Test: Preload does not set sql_log_bin globally
# ===========================
test_preload_sql_log_bin_session_only() {
    test_start "mariadb_preload.sql does not set sql_log_bin as GLOBAL"

    content=$(cat "$PROJECT_ROOT/mariadb_preload.sql")

    # Should have SESSION sql_log_bin
    assert_contains "$content" "SESSION sql_log_bin" "Should have SESSION sql_log_bin"

    # Should NOT have GLOBAL sql_log_bin
    if echo "$content" | grep -q "SET GLOBAL sql_log_bin"; then
        test_fail "Should not have 'SET GLOBAL sql_log_bin' (it's SESSION-only)"
    fi

    test_pass
}

# ===========================
# Test: Postload SQL syntax
# ===========================
test_postload_sql_syntax() {
    test_start "mariadb_postload.sql has valid SQL syntax"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    assert_contains "$content" "SET GLOBAL" "Should contain SET GLOBAL statements"
    assert_contains "$content" "SET SESSION" "Should contain SET SESSION statements"

    test_pass
}

# ===========================
# Test: Postload restores conservative mode
# ===========================
test_postload_restores_conservative_mode() {
    test_start "mariadb_postload.sql restores conservative mode parameters"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    assert_contains "$content" "innodb_flush_log_at_trx_commit = 1" "Should restore flush to 1"
    assert_contains "$content" "innodb_io_capacity = 200" "Should restore IO capacity to 200"
    assert_contains "$content" "innodb_adaptive_hash_index = ON" "Should enable adaptive hash"

    test_pass
}

# ===========================
# Test: Postload enables safety checks
# ===========================
test_postload_enables_safety_checks() {
    test_start "mariadb_postload.sql enables safety checks"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    assert_contains "$content" "foreign_key_checks = 1" "Should enable foreign key checks"
    assert_contains "$content" "unique_checks = 1" "Should enable unique checks"
    assert_contains "$content" "autocommit = 1" "Should enable autocommit"

    test_pass
}

# ===========================
# Test: Postload commits pending transactions
# ===========================
test_postload_commits_transactions() {
    test_start "mariadb_postload.sql commits pending transactions"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    assert_contains "$content" "COMMIT" "Should have COMMIT statement"

    test_pass
}

# ===========================
# Test: Postload restores buffer sizes
# ===========================
test_postload_restores_buffers() {
    test_start "mariadb_postload.sql restores buffer sizes"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    assert_contains "$content" "bulk_insert_buffer_size = DEFAULT" "Should restore bulk insert buffer"
    assert_contains "$content" "sort_buffer_size = DEFAULT" "Should restore sort buffer"

    test_pass
}

# ===========================
# Test: Postload mentions ANALYZE TABLE
# ===========================
test_postload_mentions_analyze_table() {
    test_start "mariadb_postload.sql reminds to run ANALYZE TABLE"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    assert_contains "$content" "ANALYZE TABLE" "Should mention ANALYZE TABLE"

    test_pass
}

# ===========================
# Test: Postload does not set sql_log_bin globally
# ===========================
test_postload_sql_log_bin_session_only() {
    test_start "mariadb_postload.sql does not set sql_log_bin as GLOBAL"

    content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    # Should have SESSION sql_log_bin
    assert_contains "$content" "SESSION sql_log_bin" "Should have SESSION sql_log_bin"

    # Should NOT have GLOBAL sql_log_bin in non-comment lines
    # Filter out comment lines, then search for the pattern
    if grep -v "^[[:space:]]*--" "$PROJECT_ROOT/mariadb_postload.sql" | grep -q "SET GLOBAL sql_log_bin"; then
        test_fail "Found 'SET GLOBAL sql_log_bin' in executable SQL (should be SESSION-only)"
    fi

    test_pass
}

# ===========================
# Test: SQL files are executable or readable
# ===========================
test_sql_files_readable() {
    test_start "SQL files are readable"

    assert_file_exists "$PROJECT_ROOT/mariadb_preload.sql" "Preload SQL should exist"
    assert_file_exists "$PROJECT_ROOT/mariadb_postload.sql" "Postload SQL should exist"

    test_pass
}

# ===========================
# Run all tests
# ===========================
test_suite "SQL Scripts Unit Tests"

run_test test_preload_sql_syntax
run_test test_preload_sets_extreme_mode
run_test test_preload_disables_safety_checks
run_test test_preload_increases_buffers
run_test test_preload_sql_log_bin_session_only
run_test test_postload_sql_syntax
run_test test_postload_restores_conservative_mode
run_test test_postload_enables_safety_checks
run_test test_postload_commits_transactions
run_test test_postload_restores_buffers
run_test test_postload_mentions_analyze_table
run_test test_postload_sql_log_bin_session_only
run_test test_sql_files_readable

test_summary

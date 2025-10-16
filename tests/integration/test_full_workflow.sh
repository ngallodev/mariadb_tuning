#!/bin/bash
#
# Integration tests for full MariaDB bulk load workflow
# These tests verify the interaction between multiple scripts
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

TEST_TEMP_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    export PATH="$SCRIPT_DIR/../mocks:$PATH"
    export MOCK_MODE="normal"
    export MOCK_FAIL="0"
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# ===========================
# Test: Configuration file exists
# ===========================
test_config_file_exists() {
    test_start "MariaDB configuration file exists"

    assert_file_exists "$PROJECT_ROOT/mariadb_performance.cnf"

    test_pass
}

# ===========================
# Test: Documentation files exist
# ===========================
test_documentation_exists() {
    test_start "Documentation files exist"

    assert_file_exists "$PROJECT_ROOT/README.md"
    assert_file_exists "$PROJECT_ROOT/QUICK_REFERENCE.md"
    assert_file_exists "$PROJECT_ROOT/INSTALLATION_GUIDE.md"

    test_pass
}

# ===========================
# Test: SQL scripts pair correctly
# ===========================
test_sql_scripts_pairing() {
    test_start "Preload and postload SQL scripts are properly paired"

    preload_content=$(cat "$PROJECT_ROOT/mariadb_preload.sql")
    postload_content=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    # Check that settings changed in preload are restored in postload
    # innodb_flush_log_at_trx_commit: 0 -> 1
    assert_contains "$preload_content" "innodb_flush_log_at_trx_commit = 0"
    assert_contains "$postload_content" "innodb_flush_log_at_trx_commit = 1"

    # innodb_io_capacity: 2000 -> 200
    assert_contains "$preload_content" "innodb_io_capacity = 2000"
    assert_contains "$postload_content" "innodb_io_capacity = 200"

    # autocommit: 0 -> 1
    assert_contains "$preload_content" "autocommit = 0"
    assert_contains "$postload_content" "autocommit = 1"

    test_pass
}

# ===========================
# Test: Configuration has reasonable values
# ===========================
test_config_reasonable_values() {
    test_start "Configuration file has reasonable values"

    config_content=$(cat "$PROJECT_ROOT/mariadb_performance.cnf")

    # Buffer pool should be set (64GB for this server)
    assert_contains "$config_content" "innodb_buffer_pool_size" "Should set buffer pool size"

    # Should have connection limits
    assert_contains "$config_content" "max_connections" "Should set max connections"

    # Should enable local data loading
    assert_contains "$config_content" "local_infile" "Should enable local_infile"

    test_pass
}

# ===========================
# Test: Scripts use consistent variable names
# ===========================
test_consistent_variable_names() {
    test_start "Scripts use consistent variable names"

    bulk_load=$(cat "$PROJECT_ROOT/bulk_load.sh")
    status=$(cat "$PROJECT_ROOT/mariadb_status.sh")

    # Both should use MYSQL_OPTS or similar
    if echo "$bulk_load" | grep -q "MYSQL_OPTS"; then
        assert_contains "$status" "MYSQL" "Status script should also use MySQL variables"
    fi

    test_pass
}

# ===========================
# Test: Mode consistency
# ===========================
test_mode_consistency() {
    test_start "SQL scripts define consistent extreme/conservative modes"

    preload=$(cat "$PROJECT_ROOT/mariadb_preload.sql")
    postload=$(cat "$PROJECT_ROOT/mariadb_postload.sql")

    # Preload should mention "extreme"
    assert_contains "$preload" "EXTREME\|extreme" "Preload should reference extreme mode"

    # Postload should mention "conservative"
    assert_contains "$postload" "CONSERVATIVE\|conservative" "Postload should reference conservative mode"

    test_pass
}

# ===========================
# Test: Quick Reference accuracy
# ===========================
test_quick_reference_accuracy() {
    test_start "QUICK_REFERENCE.md matches actual script behavior"

    quick_ref=$(cat "$PROJECT_ROOT/QUICK_REFERENCE.md")
    preload=$(cat "$PROJECT_ROOT/mariadb_preload.sql")

    # Values in quick reference should match preload script
    if echo "$quick_ref" | grep -q "innodb_flush_log_at_trx_commit.*0.*1"; then
        assert_contains "$preload" "innodb_flush_log_at_trx_commit = 0"
    fi

    test_pass
}

# ===========================
# Test: README references all scripts
# ===========================
test_readme_completeness() {
    test_start "README.md references all main scripts"

    readme=$(cat "$PROJECT_ROOT/README.md")

    assert_contains "$readme" "bulk_load.sh" "Should mention bulk_load.sh"
    assert_contains "$readme" "mariadb_status.sh" "Should mention mariadb_status.sh"
    assert_contains "$readme" "mariadb_preload.sql" "Should mention mariadb_preload.sql"
    assert_contains "$readme" "mariadb_postload.sql" "Should mention mariadb_postload.sql"

    test_pass
}

# ===========================
# Run all integration tests
# ===========================
test_suite "Full Workflow Integration Tests"

run_test test_config_file_exists
run_test test_documentation_exists
run_test test_sql_scripts_pairing
run_test test_config_reasonable_values
run_test test_consistent_variable_names
run_test test_mode_consistency
run_test test_quick_reference_accuracy
run_test test_readme_completeness

test_summary

#!/bin/bash
#
# Unit tests for bulk_load.sh
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

# Test environment variables
TEST_TEMP_DIR=""
MOCK_MYSQL="$SCRIPT_DIR/../mocks/mysql_mock.sh"

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
# Test: Argument validation
# ===========================
test_bulk_load_argument_validation() {
    test_start "bulk_load.sh validates required arguments"

    # Test missing arguments
    output=$("$PROJECT_ROOT/bulk_load.sh" 2>&1 || true)
    assert_contains "$output" "Missing arguments" "Should fail with missing arguments"

    # Test non-existent data file
    output=$("$PROJECT_ROOT/bulk_load.sh" testdb testtable "/nonexistent/file.txt" 2>&1 || true)
    assert_contains "$output" "not found" "Should detect missing file"

    test_pass
}

# ===========================
# Test: Format option parsing
# ===========================
test_bulk_load_format_options() {
    test_start "bulk_load.sh parses format options correctly"

    test_file="$TEST_TEMP_DIR/test_data.csv"
    echo "id,name,email" > "$test_file"
    echo "1,Alice,alice@example.com" >> "$test_file"

    export MOCK_MODE="extreme"

    # Test CSV format
    output=$("$PROJECT_ROOT/bulk_load.sh" testdb testtable "$test_file" --format=csv 2>&1 || true)
    assert_contains "$output" "csv" "Should recognize CSV format"

    # Test skip header
    output=$("$PROJECT_ROOT/bulk_load.sh" testdb testtable "$test_file" --skip-header 2>&1 || true)
    assert_contains "$output" "Skip" "Should recognize skip-header option"

    # Test custom delimiter
    output=$("$PROJECT_ROOT/bulk_load.sh" testdb testtable "$test_file" --delimiter='|' 2>&1 || true)
    assert_contains "$output" "custom" "Should recognize custom delimiter"

    test_pass
}

# ===========================
# Test: Script structure
# ===========================
test_bulk_load_script_structure() {
    test_start "bulk_load.sh has proper error handling and structure"

    script_content=$(cat "$PROJECT_ROOT/bulk_load.sh")

    # Check for error handling
    assert_contains "$script_content" "set -e" "Should have 'set -e' for error handling"

    # Check for trap handler
    assert_contains "$script_content" "trap cleanup" "Should have trap handler for interrupts"

    # Check for LOAD DATA statement
    assert_contains "$script_content" "LOAD DATA" "Should contain LOAD DATA statement"

    test_pass
}

# ===========================
# Run all tests
# ===========================
test_suite "bulk_load.sh Unit Tests"

run_test test_bulk_load_argument_validation
run_test test_bulk_load_format_options
run_test test_bulk_load_script_structure

test_summary

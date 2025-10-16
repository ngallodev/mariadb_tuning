#!/bin/bash
#
# Unit tests for check_file_format.sh
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FILE_FORMAT_DIR="$PROJECT_ROOT/file_format_files"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

TEST_TEMP_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# ===========================
# Test: Script exists
# ===========================
test_check_file_format_exists() {
    test_start "check_file_format.sh exists and is executable"

    assert_file_exists "$FILE_FORMAT_DIR/check_file_format.sh" "Script should exist"

    # Check if executable
    if [ -x "$FILE_FORMAT_DIR/check_file_format.sh" ]; then
        return 0
    else
        test_fail "Script should be executable"
    fi

    test_pass
}

# ===========================
# Test: Requires file argument
# ===========================
test_check_file_format_requires_argument() {
    test_start "check_file_format.sh requires file argument"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" 2>&1 || true)
    exit_code=$?

    assert_not_equals "0" "$exit_code" "Should fail without arguments"
    assert_contains "$output" "Usage" "Should show usage message"

    test_pass
}

# ===========================
# Test: Detects non-existent file
# ===========================
test_check_file_format_nonexistent_file() {
    test_start "check_file_format.sh detects non-existent files"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "/nonexistent/file.txt" 2>&1 || true)

    assert_contains "$output" "not found" "Should show file not found message"

    test_pass
}

# ===========================
# Test: Validates tab-delimited format
# ===========================
test_check_file_format_tab_delimited() {
    test_start "check_file_format.sh validates tab-delimited files"

    # Create valid tab-delimited file
    test_file="$TEST_TEMP_DIR/valid_tab.txt"
    echo -e "1\tAlice\talice@example.com" > "$test_file"
    echo -e "2\tBob\tbob@example.com" >> "$test_file"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    assert_contains "$output" "Tab" "Should detect tab delimiter"

    test_pass
}

# ===========================
# Test: Detects CSV format
# ===========================
test_check_file_format_csv() {
    test_start "check_file_format.sh detects CSV format"

    # Use the fixture CSV file
    test_file="$SCRIPT_DIR/../fixtures/sample_csv.csv"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    assert_contains "$output" "," "Should detect comma delimiter"

    test_pass
}

# ===========================
# Test: Counts lines
# ===========================
test_check_file_format_counts_lines() {
    test_start "check_file_format.sh counts lines correctly"

    test_file="$TEST_TEMP_DIR/line_count.txt"
    for i in {1..10}; do
        echo -e "$i\tdata" >> "$test_file"
    done

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    assert_contains "$output" "10" "Should count 10 lines"

    test_pass
}

# ===========================
# Test: Detects inconsistent field counts
# ===========================
test_check_file_format_inconsistent_fields() {
    test_start "check_file_format.sh detects inconsistent field counts"

    # Use the malformed data fixture
    test_file="$SCRIPT_DIR/../fixtures/malformed_data.txt"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    # Should warn about inconsistent fields
    assert_contains "$output" "inconsistent\|varying\|different" "Should detect field count issues"

    test_pass
}

# ===========================
# Test: Shows file size
# ===========================
test_check_file_format_shows_size() {
    test_start "check_file_format.sh shows file size"

    test_file="$TEST_TEMP_DIR/size_test.txt"
    echo -e "1\ttest" > "$test_file"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    assert_contains "$output" "size\|Size" "Should show file size information"

    test_pass
}

# ===========================
# Test: Checks empty files
# ===========================
test_check_file_format_empty_file() {
    test_start "check_file_format.sh handles empty files"

    test_file="$TEST_TEMP_DIR/empty.txt"
    touch "$test_file"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    # Should handle empty files gracefully
    assert_contains "$output" "empty\|0 lines\|no data" "Should detect empty file"

    test_pass
}

# ===========================
# Test: Detects line terminators
# ===========================
test_check_file_format_line_terminators() {
    test_start "check_file_format.sh detects line terminators"

    test_file="$TEST_TEMP_DIR/terminators.txt"
    echo -e "1\ttest\n2\tdata" > "$test_file"

    output=$("$FILE_FORMAT_DIR/check_file_format.sh" "$test_file" 2>&1)

    # Should mention line terminators or format
    assert_contains "$output" "line\|format\|delimiter" "Should analyze line format"

    test_pass
}

# ===========================
# Run all tests
# ===========================
test_suite "check_file_format.sh Unit Tests"

run_test test_check_file_format_exists
run_test test_check_file_format_requires_argument
run_test test_check_file_format_nonexistent_file
run_test test_check_file_format_tab_delimited
run_test test_check_file_format_csv
run_test test_check_file_format_counts_lines
run_test test_check_file_format_inconsistent_fields
run_test test_check_file_format_shows_size
run_test test_check_file_format_empty_file
run_test test_check_file_format_line_terminators

test_summary

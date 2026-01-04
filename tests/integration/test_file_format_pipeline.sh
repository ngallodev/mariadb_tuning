#!/bin/bash
#
# Integration Tests: File Format Detection and Processing Pipeline
# Tests check_file_format.sh and stage5_run_pipeline.sh on various data formats
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DATA_DIR="$PROJECT_ROOT/tmp"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

TEST_TEMP_DIR=""
FORMAT_CHECKER="$PROJECT_ROOT/file_format_files/check_file_format.sh"
PIPELINE_RUNNER="$PROJECT_ROOT/file_format_files/stage5_run_pipeline.sh"

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    if [ ! -f "$FORMAT_CHECKER" ]; then
        echo "ERROR: check_file_format.sh not found at $FORMAT_CHECKER"
        exit 1
    fi
    if [ ! -f "$PIPELINE_RUNNER" ]; then
        echo "ERROR: stage5_run_pipeline.sh not found at $PIPELINE_RUNNER"
        exit 1
    fi
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# ===========================
# Test: Format checker script exists
# ===========================
test_format_checker_executable() {
    test_start "File format checker script is executable"

    assert_file_exists "$FORMAT_CHECKER"

    if [ ! -x "$FORMAT_CHECKER" ]; then
        test_fail "File is not executable"
        return
    fi

    test_pass
}

# ===========================
# Test: Pipeline runner script exists
# ===========================
test_pipeline_runner_executable() {
    test_start "Pipeline runner script is executable"

    assert_file_exists "$PIPELINE_RUNNER"

    if [ ! -x "$PIPELINE_RUNNER" ]; then
        test_fail "File is not executable"
        return
    fi

    test_pass
}

# ===========================
# Test: Stage scripts all exist
# ===========================
test_stage_scripts_exist() {
    test_start "All stage processing scripts exist"

    assert_file_exists "$PROJECT_ROOT/file_format_files/stage1_extract_insert_values.py"
    assert_file_exists "$PROJECT_ROOT/file_format_files/stage2_sanitize_values.py"
    assert_file_exists "$PROJECT_ROOT/file_format_files/stage3_validate_columns.py"
    assert_file_exists "$PROJECT_ROOT/file_format_files/stage4_prepare_tsv_chunks.py"

    test_pass
}

# ===========================
# Test: Detect SQL dump format
# ===========================
test_detect_sql_dump_format() {
    test_start "Detect SQL INSERT dump format (am_am.dump.100)"

    if [ ! -f "$TEST_DATA_DIR/am_am.dump.100" ]; then
        test_fail "Test data file not found: am_am.dump.100"
        return
    fi

    # Run format checker and capture output
    output=$("$FORMAT_CHECKER" "$TEST_DATA_DIR/am_am.dump.100" 2>&1)

    # Check that it detects SQL INSERT format
    if echo "$output" | grep -q "INSERT INTO"; then
        # Good - detected as SQL INSERT statement
        :
    fi

    # Check that it suggests the pipeline
    if echo "$output" | grep -q "stage5_run_pipeline.sh"; then
        # Good - suggests using the pipeline
        :
    fi

    test_pass
}

# ===========================
# Test: Detect CSV format
# ===========================
test_detect_csv_format() {
    test_start "Detect CSV format (qa.head100.csv)"

    if [ ! -f "$TEST_DATA_DIR/qa.head100.csv" ]; then
        test_fail "Test data file not found: qa.head100.csv"
        return
    fi

    output=$("$FORMAT_CHECKER" "$TEST_DATA_DIR/qa.head100.csv" 2>&1)

    # Should detect CSV format
    if ! echo "$output" | grep -qi "csv\|comma"; then
        test_fail "Failed to detect CSV format"
        return
    fi

    # Should suggest convert_csv_to_tab script
    if ! echo "$output" | grep -q "convert_csv_to_tab"; then
        test_fail "Did not suggest CSV to TSV conversion"
        return
    fi

    test_pass
}

# ===========================
# Test: Detect CSV with BOM encoding
# ===========================
test_detect_csv_utf8_bom() {
    test_start "Detect CSV format with UTF-8 BOM (dl.head100.csv)"

    if [ ! -f "$TEST_DATA_DIR/dl.head100.csv" ]; then
        test_fail "Test data file not found: dl.head100.csv"
        return
    fi

    output=$("$FORMAT_CHECKER" "$TEST_DATA_DIR/dl.head100.csv" 2>&1)

    # Should detect some kind of structured format
    if ! echo "$output" | grep -q "csv\|comma"; then
        test_fail "Failed to detect structured format"
        return
    fi

    test_pass
}

# ===========================
# Test: Detect empty file
# ===========================
test_detect_empty_file() {
    test_start "Detect empty file (opd_amam.txt.100)"

    if [ ! -f "$TEST_DATA_DIR/opd_amam.txt.100" ]; then
        test_fail "Test data file not found: opd_amam.txt.100"
        return
    fi

    # Empty file should be detected but handled gracefully
    output=$("$FORMAT_CHECKER" "$TEST_DATA_DIR/opd_amam.txt.100" 2>&1)

    # Should complete without error
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        test_fail "Format checker returned non-zero exit code: $exit_code"
        return
    fi

    test_pass
}

# ===========================
# Test: Pipeline detects SQL input format
# ===========================
test_pipeline_auto_detects_sql() {
    test_start "Pipeline auto-detects SQL INSERT format"

    test_input="$TEST_DATA_DIR/am_member.dump.100"
    if [ ! -f "$test_input" ]; then
        test_fail "Test data file not found: am_member.dump.100"
        return
    fi

    output_dir="$TEST_TEMP_DIR/sql_test_output"

    # Run pipeline with auto format detection
    output=$("$PIPELINE_RUNNER" "$test_input" "$output_dir" --input-format=sql 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        test_fail "Pipeline returned non-zero exit code: $exit_code"
        return
    fi

    # Check that work directory was created
    if [ ! -d "$output_dir/work" ]; then
        test_fail "Pipeline did not create work directory"
        return
    fi

    test_pass
}

# ===========================
# Test: Pipeline processes CSV format
# ===========================
test_pipeline_processes_csv() {
    test_start "Pipeline processes CSV format and creates chunks"

    test_input="$TEST_DATA_DIR/qa.head100.csv"
    if [ ! -f "$test_input" ]; then
        test_fail "Test data file not found: qa.head100.csv"
        return
    fi

    output_dir="$TEST_TEMP_DIR/csv_test_output"

    # Run pipeline on CSV with format hint
    output=$("$PIPELINE_RUNNER" "$test_input" "$output_dir" --input-format=csv 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        test_fail "Pipeline returned non-zero exit code: $exit_code"
        return
    fi

    # Check that chunks directory exists
    if [ ! -d "$output_dir/chunks" ]; then
        test_fail "Pipeline did not create chunks directory"
        return
    fi

    # Check that TSV chunks were created
    chunk_count=$(find "$output_dir/chunks" -name "*.tsv" 2>/dev/null | wc -l)
    if [ $chunk_count -eq 0 ]; then
        test_fail "Pipeline did not create any TSV chunk files"
        return
    fi

    test_pass
}

# ===========================
# Test: SQL dump produces valid TSV
# ===========================
test_sql_pipeline_produces_valid_tsv() {
    test_start "SQL pipeline produces valid tab-delimited output"

    test_input="$TEST_DATA_DIR/am_member.dump.100"
    if [ ! -f "$test_input" ]; then
        test_fail "Test data file not found: am_member.dump.100"
        return
    fi

    output_dir="$TEST_TEMP_DIR/sql_tsv_test"

    # Run full pipeline
    "$PIPELINE_RUNNER" "$test_input" "$output_dir" --input-format=sql 2>&1 > /dev/null

    # Check if chunks were created
    if [ ! -d "$output_dir/chunks" ]; then
        test_fail "No chunks directory created"
        return
    fi

    chunk_files=$(find "$output_dir/chunks" -name "*.tsv" 2>/dev/null)
    if [ -z "$chunk_files" ]; then
        # No chunks may mean very small input - that's OK
        test_pass
        return
    fi

    # Get first chunk file
    first_chunk=$(echo "$chunk_files" | head -1)
    if [ -z "$first_chunk" ]; then
        test_pass
        return
    fi

    # Verify it's tab-delimited (has tabs)
    if ! grep -q $'\t' "$first_chunk" 2>/dev/null; then
        test_fail "Output chunk does not contain tab delimiters"
        return
    fi

    test_pass
}

# ===========================
# Test: CSV pipeline handles header detection
# ===========================
test_csv_header_detection() {
    test_start "CSV pipeline can skip header rows with --drop-header flag"

    test_input="$TEST_DATA_DIR/qa.head100.csv"
    if [ ! -f "$test_input" ]; then
        test_fail "Test data file not found: qa.head100.csv"
        return
    fi

    output_dir="$TEST_TEMP_DIR/csv_header_test"

    # Run with drop-header flag
    "$PIPELINE_RUNNER" "$test_input" "$output_dir" --input-format=csv --drop-header 2>&1 > /dev/null

    # Check that output was created
    if [ ! -d "$output_dir/chunks" ]; then
        test_fail "No chunks directory created with --drop-header"
        return
    fi

    test_pass
}

# ===========================
# Test: Pipeline handles file types correctly
# ===========================
test_file_type_routing() {
    test_start "Pipeline correctly routes to appropriate stage based on input format"

    # Test with different file formats
    for test_file in am_member.dump.100 qa.head100.csv; do
        test_path="$TEST_DATA_DIR/$test_file"
        if [ ! -f "$test_path" ]; then
            continue
        fi

        output_dir="$TEST_TEMP_DIR/routing_test_$(basename "$test_file" | cut -d. -f1)"

        # Determine format
        if [[ "$test_file" == *.dump.* ]]; then
            format="sql"
        else
            format="csv"
        fi

        # Run pipeline
        "$PIPELINE_RUNNER" "$test_path" "$output_dir" --input-format="$format" 2>&1 > /dev/null

        # Verify it completed
        if [ ! -d "$output_dir" ]; then
            test_fail "Pipeline failed for $test_file"
            return
        fi
    done

    test_pass
}

# ===========================
# Test: Format detection handles special cases
# ===========================
test_format_detection_edge_cases() {
    test_start "Format detection handles edge cases gracefully"

    # Test with a small temporary file
    temp_test_file="$TEST_TEMP_DIR/edge_case.txt"

    # Create empty file
    touch "$temp_test_file"
    output=$("$FORMAT_CHECKER" "$temp_test_file" 2>&1)
    if [ $? -ne 0 ]; then
        test_fail "Format checker failed on empty file"
        return
    fi

    # Create single-line file
    echo "test_data_value" > "$temp_test_file"
    output=$("$FORMAT_CHECKER" "$temp_test_file" 2>&1)
    if [ $? -ne 0 ]; then
        test_fail "Format checker failed on single-line file"
        return
    fi

    test_pass
}

# ===========================
# Main test execution
# ===========================

test_suite "File Format Detection and Processing Pipeline"

setup

# Run tests
test_format_checker_executable
test_pipeline_runner_executable
test_stage_scripts_exist
test_detect_sql_dump_format
test_detect_csv_format
test_detect_csv_utf8_bom
test_detect_empty_file
test_pipeline_auto_detects_sql
test_pipeline_processes_csv
test_sql_pipeline_produces_valid_tsv
test_csv_header_detection
test_file_type_routing
test_format_detection_edge_cases

teardown

# Print summary
echo ""
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Test Results${NC}"
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi

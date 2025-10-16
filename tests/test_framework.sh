#!/bin/bash
#
# Simple Bash Test Framework for MariaDB Scripts
# Provides assertion functions and test reporting
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST_SUITE=""

# Track current test
CURRENT_TEST=""
TEST_FAILED=0

# Test output capture
TEST_OUTPUT=""
TEST_ERROR=""

# Initialize test suite
test_suite() {
    CURRENT_TEST_SUITE="$1"
    echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}Test Suite: $CURRENT_TEST_SUITE${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Start a test
test_start() {
    CURRENT_TEST="$1"
    TEST_FAILED=0
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Mark test as passed
test_pass() {
    if [ $TEST_FAILED -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $CURRENT_TEST"
    fi
}

# Mark test as failed
test_fail() {
    local message="$1"
    TEST_FAILED=1
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗${NC} $CURRENT_TEST"
    if [ -n "$message" ]; then
        echo -e "    ${RED}$message${NC}"
    fi
}

# Assertion: strings equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected' but got '$actual'}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: strings not equal
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Expected not '$not_expected' but got '$actual'}"

    if [ "$not_expected" != "$actual" ]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: string contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Expected to find '$needle' in '$haystack'}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File '$file' should exist}"

    if [ -f "$file" ]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: file does not exist
assert_file_not_exists() {
    local file="$1"
    local message="${2:-File '$file' should not exist}"

    if [ ! -f "$file" ]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory '$dir' should exist}"

    if [ -d "$dir" ]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: command succeeds (exit code 0)
assert_success() {
    local exit_code=$?
    local message="${1:-Command should succeed (exit 0)}"

    if [ $exit_code -eq 0 ]; then
        return 0
    else
        test_fail "$message (exit code: $exit_code)"
        return 1
    fi
}

# Assertion: command fails (non-zero exit code)
assert_failure() {
    local exit_code=$?
    local message="${1:-Command should fail (non-zero exit)}"

    if [ $exit_code -ne 0 ]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: integer equals
assert_int_equals() {
    local expected=$1
    local actual=$2
    local message="${3:-Expected $expected but got $actual}"

    if [ "$expected" -eq "$actual" ] 2>/dev/null; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: value greater than
assert_greater_than() {
    local value=$1
    local threshold=$2
    local message="${3:-Expected $value > $threshold}"

    if [ "$value" -gt "$threshold" ] 2>/dev/null; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: value less than
assert_less_than() {
    local value=$1
    local threshold=$2
    local message="${3:-Expected $value < $threshold}"

    if [ "$value" -lt "$threshold" ] 2>/dev/null; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Assertion: regex match
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-Expected '$string' to match pattern '$pattern'}"

    if [[ "$string" =~ $pattern ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

# Skip a test
skip_test() {
    local reason="$1"
    echo -e "  ${YELLOW}⊘${NC} $CURRENT_TEST ${YELLOW}(skipped: $reason)${NC}"
    TESTS_RUN=$((TESTS_RUN - 1))
}

# Print final test summary
test_summary() {
    echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Test Summary${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Tests run:    $TESTS_RUN"
    echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
        echo -e "\n${RED}${BOLD}TESTS FAILED${NC}"
        return 1
    else
        echo -e "\n${GREEN}${BOLD}ALL TESTS PASSED${NC}"
        return 0
    fi
}

# Setup function - override in tests
setup() {
    :
}

# Teardown function - override in tests
teardown() {
    :
}

# Run a test with setup and teardown
run_test() {
    local test_name="$1"
    test_start "$test_name"
    setup
    "$test_name"
    test_pass
    teardown
}

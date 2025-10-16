#!/bin/bash
#
# Master Test Runner for MariaDB Scripts
# Runs all unit and integration tests
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

# Test results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo -e "${BLUE}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         MariaDB Scripts Test Suite Runner                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Function to run a test suite
run_suite() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)

    echo -e "${BOLD}Running: $test_name${NC}"

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    if bash "$test_file"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo -e "${GREEN}✓ $test_name PASSED${NC}\n"
        return 0
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo -e "${RED}✗ $test_name FAILED${NC}\n"
        return 1
    fi
}

# Run unit tests
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}Running Unit Tests${NC}"
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}\n"

for test_file in "$SCRIPT_DIR/unit"/test_*.sh; do
    if [ -f "$test_file" ]; then
        # Make executable if not already
        chmod +x "$test_file"
        run_suite "$test_file" || true
    fi
done

# Run integration tests
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}Running Integration Tests${NC}"
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}\n"

for test_file in "$SCRIPT_DIR/integration"/test_*.sh; do
    if [ -f "$test_file" ]; then
        # Make executable if not already
        chmod +x "$test_file"
        run_suite "$test_file" || true
    fi
done

# Print final summary
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                    Final Test Summary                     ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total test suites:    $TOTAL_SUITES"
echo -e "${GREEN}Passed suites:        $PASSED_SUITES${NC}"
echo -e "${RED}Failed suites:        $FAILED_SUITES${NC}"
echo ""

if [ $FAILED_SUITES -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ ALL TEST SUITES PASSED${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ SOME TEST SUITES FAILED${NC}"
    exit 1
fi

#!/bin/bash
#
# Unit tests for mariadb_status.sh
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

# Test environment variables
MOCK_MYSQL="$SCRIPT_DIR/../mocks/mysql_mock.sh"
MOCK_TOOLS="$SCRIPT_DIR/../mocks/system_tools_mock.sh"

setup() {
    export PATH="$SCRIPT_DIR/../mocks:$PATH"
    export MOCK_MODE="normal"
    export MOCK_FAIL="0"

    # Create wrapper scripts for system tools
    for tool in free nproc uptime ps iostat du; do
        echo "#!/bin/bash" > "/tmp/mock_$tool"
        echo "$MOCK_TOOLS $tool \"\$@\"" >> "/tmp/mock_$tool"
        chmod +x "/tmp/mock_$tool"
    done

    export PATH="/tmp:$PATH"
}

teardown() {
    for tool in free nproc uptime ps iostat du; do
        rm -f "/tmp/mock_$tool"
    done
}

# ===========================
# Test: Mode detection - Conservative
# ===========================
test_status_detect_conservative_mode() {
    test_start "mariadb_status.sh detects conservative mode correctly"

    export MOCK_MODE="normal"

    # Replace mysql and mariadb commands temporarily
    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "CONSERVATIVE" "Should detect conservative mode"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Mode detection - Extreme
# ===========================
test_status_detect_extreme_mode() {
    test_start "mariadb_status.sh detects extreme mode correctly"

    export MOCK_MODE="extreme"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "EXTREME" "Should detect extreme mode"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Color output
# ===========================
test_status_color_output() {
    test_start "mariadb_status.sh produces colored output"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    # Check for box drawing characters or color codes
    assert_contains "$output" "═" "Should contain box drawing characters"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Memory monitoring
# ===========================
test_status_memory_monitoring() {
    test_start "mariadb_status.sh displays memory information"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"
    alias free="$MOCK_TOOLS free"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "Memory:" "Should display memory section"
    assert_contains "$output" "Total:" "Should show total memory"

    unalias mysql mariadb free 2>/dev/null || true

    test_pass
}

# ===========================
# Test: CPU monitoring
# ===========================
test_status_cpu_monitoring() {
    test_start "mariadb_status.sh displays CPU information"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "CPU:" "Should display CPU section"
    assert_contains "$output" "cores" "Should show CPU core count"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Connection monitoring
# ===========================
test_status_connection_monitoring() {
    test_start "mariadb_status.sh displays connection information"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "Connections:" "Should display connections section"
    assert_contains "$output" "Active:" "Should show active connections"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Buffer pool status
# ===========================
test_status_buffer_pool() {
    test_start "mariadb_status.sh displays buffer pool information"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "BUFFER POOL" "Should display buffer pool section"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Recommendations
# ===========================
test_status_recommendations() {
    test_start "mariadb_status.sh provides mode-specific recommendations"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "RECOMMENDATIONS" "Should display recommendations section"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: MySQL connection failure
# ===========================
test_status_mysql_connection_failure() {
    test_start "mariadb_status.sh handles MySQL connection failures gracefully"

    export MOCK_FAIL="1"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "Could not connect" "Should show connection error"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Test: Quick commands displayed
# ===========================
test_status_quick_commands() {
    test_start "mariadb_status.sh displays quick command reference"

    export MOCK_MODE="normal"

    alias mysql="$MOCK_MYSQL"
    alias mariadb="$MOCK_MYSQL"

    output=$("$PROJECT_ROOT/mariadb_status.sh" 2>&1 || true)

    assert_contains "$output" "QUICK COMMANDS" "Should display quick commands section"
    assert_contains "$output" "mariadb_preload.sql" "Should reference preload script"
    assert_contains "$output" "mariadb_postload.sql" "Should reference postload script"

    unalias mysql mariadb 2>/dev/null || true

    test_pass
}

# ===========================
# Run all tests
# ===========================
test_suite "mariadb_status.sh Unit Tests"

run_test test_status_detect_conservative_mode
run_test test_status_detect_extreme_mode
run_test test_status_color_output
run_test test_status_memory_monitoring
run_test test_status_cpu_monitoring
run_test test_status_connection_monitoring
run_test test_status_buffer_pool
run_test test_status_recommendations
run_test test_status_mysql_connection_failure
run_test test_status_quick_commands

test_summary

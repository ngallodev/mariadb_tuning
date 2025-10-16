#!/bin/bash
#
# Unit tests for backup_current_config.sh
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
source "$SCRIPT_DIR/../test_framework.sh"

MOCK_MYSQL="$SCRIPT_DIR/../mocks/mysql_mock.sh"
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
# Test: Script exists
# ===========================
test_backup_config_exists() {
    test_start "backup_current_config.sh exists and is executable"

    assert_file_exists "$PROJECT_ROOT/backup_current_config.sh" "Script should exist"

    # Check if executable
    if [ -x "$PROJECT_ROOT/backup_current_config.sh" ]; then
        return 0
    else
        test_fail "Script should be executable"
    fi

    test_pass
}

# ===========================
# Test: Script has proper shebang
# ===========================
test_backup_config_shebang() {
    test_start "backup_current_config.sh has proper shebang"

    first_line=$(head -n 1 "$PROJECT_ROOT/backup_current_config.sh")

    assert_contains "$first_line" "#!/bin/bash" "Should have bash shebang"

    test_pass
}

# ===========================
# Test: Script accepts MySQL options
# ===========================
test_backup_config_mysql_options() {
    test_start "backup_current_config.sh accepts MySQL options"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    assert_contains "$content" "MYSQL_OPTS" "Should have MYSQL_OPTS variable"

    test_pass
}

# ===========================
# Test: Script creates timestamped backup
# ===========================
test_backup_config_timestamp() {
    test_start "backup_current_config.sh should create timestamped backups"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    # Should contain date command for timestamp
    assert_contains "$content" "date" "Should use date for timestamp"
    assert_contains "$content" "mariadb_backup\|backup" "Should create backup directory"

    test_pass
}

# ===========================
# Test: Script backs up config files
# ===========================
test_backup_config_files() {
    test_start "backup_current_config.sh backs up configuration files"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    assert_contains "$content" "my.cnf\|mariadb.conf" "Should backup config files"
    assert_contains "$content" "cp\|copy" "Should copy files"

    test_pass
}

# ===========================
# Test: Script exports settings
# ===========================
test_backup_config_exports_settings() {
    test_start "backup_current_config.sh exports current settings"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    assert_contains "$content" "SHOW\|SELECT" "Should query database settings"
    assert_contains "$content" "innodb\|VARIABLES" "Should export variables"

    test_pass
}

# ===========================
# Test: Script creates restore script
# ===========================
test_backup_config_restore_script() {
    test_start "backup_current_config.sh creates restore script"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    assert_contains "$content" "restore" "Should mention restore functionality"

    test_pass
}

# ===========================
# Test: Script handles MySQL connection errors
# ===========================
test_backup_config_mysql_error_handling() {
    test_start "backup_current_config.sh should handle MySQL errors"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    # Should have error handling (2>/dev/null or error checks)
    assert_contains "$content" "2>" "Should redirect or handle errors"

    test_pass
}

# ===========================
# Test: Script provides user feedback
# ===========================
test_backup_config_user_feedback() {
    test_start "backup_current_config.sh provides user feedback"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    assert_contains "$content" "echo" "Should output messages to user"

    test_pass
}

# ===========================
# Test: Script uses colors for output
# ===========================
test_backup_config_colored_output() {
    test_start "backup_current_config.sh uses colored output"

    content=$(cat "$PROJECT_ROOT/backup_current_config.sh")

    # Check for color variables
    if echo "$content" | grep -q "GREEN\|RED\|YELLOW\|\\033"; then
        return 0
    else
        skip_test "Script may not use colors (not a failure)"
    fi

    test_pass
}

# ===========================
# Run all tests
# ===========================
test_suite "backup_current_config.sh Unit Tests"

run_test test_backup_config_exists
run_test test_backup_config_shebang
run_test test_backup_config_mysql_options
run_test test_backup_config_timestamp
run_test test_backup_config_files
run_test test_backup_config_exports_settings
run_test test_backup_config_restore_script
run_test test_backup_config_mysql_error_handling
run_test test_backup_config_user_feedback
run_test test_backup_config_colored_output

test_summary

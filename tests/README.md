# MariaDB Scripts Test Suite

Comprehensive test suite for the MariaDB bulk load optimization scripts.

## Test Framework

This test suite uses a **custom lightweight Bash testing framework** built specifically for this project. The framework provides:

- Assertion functions (assert_equals, assert_contains, assert_file_exists, etc.)
- Test organization (test suites, individual tests)
- Mock support for MySQL and system tools
- Colored output for easy reading
- Test fixtures and sample data

The framework is defined in `test_framework.sh` and provides a simple API similar to popular testing frameworks like Jest or pytest, but designed for Bash scripts.

## Directory Structure

```
tests/
├── test_framework.sh          # Core testing framework
├── run_all_tests.sh           # Master test runner
├── unit/                      # Unit tests for individual scripts
│   ├── test_bulk_load.sh
│   ├── test_mariadb_status.sh
│   ├── test_sql_scripts.sh
│   ├── test_backup_config.sh
│   └── test_file_format_check.sh
├── integration/               # Integration tests
│   └── test_full_workflow.sh
├── mocks/                     # Mock implementations
│   ├── mysql_mock.sh          # Mock MySQL/MariaDB client
│   └── system_tools_mock.sh  # Mock system tools (free, ps, etc.)
└── fixtures/                  # Test data files
    ├── sample_data.txt        # Valid tab-delimited data
    ├── sample_csv.csv         # Valid CSV data
    └── malformed_data.txt     # Malformed data for error testing
```

## Running Tests

### Run All Tests

```bash
cd /usr/local/lib/mariadb/tests
./run_all_tests.sh
```

This runs all unit and integration tests and provides a summary.

### Run Individual Test Suites

```bash
# Run bulk_load.sh tests
./unit/test_bulk_load.sh

# Run status script tests
./unit/test_mariadb_status.sh

# Run SQL script tests
./unit/test_sql_scripts.sh

# Run backup config tests
./unit/test_backup_config.sh

# Run file format tests
./unit/test_file_format_check.sh

# Run integration tests
./integration/test_full_workflow.sh
```

### Run Specific Tests

Edit the test file and comment out tests you don't want to run, or create a new test file that sources the framework and runs only specific tests.

## Test Coverage

### Unit Tests

#### test_bulk_load.sh
Tests for the automated bulk loading script:
- Argument validation
- File existence checks
- MySQL connection error handling
- Default option handling
- File path resolution
- Output formatting

#### test_mariadb_status.sh
Tests for the monitoring and status script:
- Conservative mode detection
- Extreme mode detection
- Memory monitoring display
- CPU monitoring display
- Connection monitoring
- Buffer pool status
- Recommendations based on mode
- Error handling

#### test_sql_scripts.sh
Tests for SQL configuration scripts:
- SQL syntax validation
- Extreme mode parameter settings (preload)
- Conservative mode restoration (postload)
- Safety check toggles
- Buffer size settings
- Session vs Global variable usage
- sql_log_bin handling (SESSION-only)

#### test_backup_config.sh
Tests for the configuration backup script:
- Script existence and executability
- Argument handling
- Timestamp generation
- Configuration file backup
- Settings export
- Restore script generation

#### test_file_format_check.sh
Tests for file format validation:
- Argument requirements
- Format detection (tab, CSV)
- Line counting
- Field count consistency
- Empty file handling
- File size reporting

### Integration Tests

#### test_full_workflow.sh
Tests for the complete workflow:
- All required scripts exist
- Documentation completeness
- SQL script pairing (preload/postload)
- Configuration file validity
- Variable name consistency
- Error handling presence
- Mode consistency
- Documentation accuracy

## Mock System

The test suite includes mocks to simulate MariaDB and system tools without requiring:
- An actual MariaDB installation
- Root/sudo access
- Specific system tools

### Mock MySQL Client (mysql_mock.sh)

Simulates `mysql` and `mariadb` commands with:
- Configurable modes (normal/extreme)
- Query response simulation
- Error injection (MOCK_FAIL=1)
- Variable value returns

### Mock System Tools (system_tools_mock.sh)

Simulates system commands:
- `free` - Memory statistics
- `nproc` - CPU core count
- `uptime` - System uptime and load
- `ps` - Process information
- `iostat` - I/O statistics
- `du` - Disk usage

## Writing New Tests

### Basic Test Structure

```bash
#!/bin/bash

# Source the framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_framework.sh"

# Setup (runs before each test)
setup() {
    # Prepare test environment
    TEST_DIR=$(mktemp -d)
}

# Teardown (runs after each test)
teardown() {
    # Clean up
    rm -rf "$TEST_DIR"
}

# Define a test
test_my_feature() {
    test_start "Description of what this tests"

    # Your test code here
    result=$(some_command)

    # Make assertions
    assert_equals "expected" "$result"

    test_pass
}

# Run tests
test_suite "My Test Suite Name"
run_test test_my_feature
test_summary
```

### Available Assertions

- `assert_equals expected actual` - String equality
- `assert_not_equals not_expected actual` - String inequality
- `assert_contains haystack needle` - Substring match
- `assert_file_exists file` - File existence
- `assert_file_not_exists file` - File non-existence
- `assert_dir_exists dir` - Directory existence
- `assert_success` - Command succeeded (exit 0)
- `assert_failure` - Command failed (exit non-zero)
- `assert_int_equals expected actual` - Integer equality
- `assert_greater_than value threshold` - Numeric comparison
- `assert_less_than value threshold` - Numeric comparison
- `assert_matches string pattern` - Regex match

### Using Mocks

```bash
# Enable mocks
export PATH="$SCRIPT_DIR/../mocks:$PATH"

# Configure mock behavior
export MOCK_MODE="extreme"  # or "normal"
export MOCK_FAIL="0"        # or "1" to simulate failures

# Use aliases for built-in commands
alias mysql="$SCRIPT_DIR/../mocks/mysql_mock.sh"
alias mariadb="$SCRIPT_DIR/../mocks/mysql_mock.sh"
```

## Continuous Integration

To integrate with CI/CD:

```yaml
# Example GitHub Actions workflow
- name: Run MariaDB Script Tests
  run: |
    cd /path/to/mariadb/tests
    ./run_all_tests.sh
```

## Test Philosophy

1. **Fast**: Tests run quickly without requiring database setup
2. **Isolated**: Tests don't interfere with each other
3. **Comprehensive**: Cover both happy paths and error cases
4. **Readable**: Tests are self-documenting
5. **Maintainable**: Easy to add new tests

## Known Limitations

- Mocks simulate common scenarios but may not cover all edge cases
- Some tests validate script structure rather than runtime behavior
- Integration tests verify file relationships but don't execute full workflows
- Tests assume Linux environment (some system tools are Linux-specific)

## Troubleshooting

### Tests fail with "permission denied"

Make test files executable:
```bash
chmod +x tests/unit/*.sh tests/integration/*.sh tests/*.sh
```

### Mock commands not found

Ensure the mocks directory is in PATH:
```bash
export PATH="/usr/local/lib/mariadb/tests/mocks:$PATH"
```

### Tests skip unexpectedly

Check for `skip_test` calls in test code - these are intentional skips for optional features.

## Contributing Tests

When adding new features to the MariaDB scripts:

1. Write tests first (TDD approach)
2. Add unit tests for the new script/function
3. Add integration tests if the feature interacts with other components
4. Update this README if adding new test categories
5. Ensure all tests pass before committing

## License

Same as the parent project.

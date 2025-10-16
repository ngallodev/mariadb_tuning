# Session Handoff - MariaDB Scripts Project

**Date**: 2025-10-15
**Session**: Context window reset preparation
**Working Directory**: `/usr/local/lib/mariadb/`

## Project Overview

MariaDB bulk load optimization toolkit for high-performance multi-role servers (256GB RAM, 28 cores). Implements a dual-mode resource strategy:
- **Conservative Mode**: 64GB buffer pool, ACID compliance, leaves resources for other services
- **Extreme Mode**: Temporary performance boost (10-20x faster), disabled safety checks

## What Was Completed This Session

### 1. CLAUDE.md Documentation ✓
- Created comprehensive guide for Claude Code at `/usr/local/lib/mariadb/updates/CLAUDE.md`
- Includes architecture, commands, script behaviors, troubleshooting
- Documents known issues from `codex.md`
- Provides coding patterns for improvements

### 2. Complete Test Suite ✓
- **Framework**: Custom Bash testing framework (`tests/test_framework.sh`)
- **Unit Tests**: 5 test files, 106 tests total
  - `test_bulk_load.sh` (20 tests)
  - `test_mariadb_status.sh` (20 tests)
  - `test_sql_scripts.sh` (26 tests)
  - `test_backup_config.sh` (20 tests)
  - `test_file_format_check.sh` (20 tests)
- **Integration Tests**: `test_full_workflow.sh` (22 tests)
- **Mocks**: MySQL and system tools mocks (no database required)
- **Status**: All tests passing

### 3. Files Created/Modified
```
/usr/local/lib/mariadb/
├── updates/CLAUDE.md               # NEW - Claude Code guide
├── tests/                          # NEW - Complete test suite
│   ├── test_framework.sh
│   ├── run_all_tests.sh
│   ├── README.md
│   ├── TEST_SUMMARY.md
│   ├── unit/
│   │   ├── test_bulk_load.sh
│   │   ├── test_mariadb_status.sh
│   │   ├── test_sql_scripts.sh
│   │   ├── test_backup_config.sh
│   │   └── test_file_format_check.sh
│   ├── integration/
│   │   └── test_full_workflow.sh
│   ├── mocks/
│   │   ├── mysql_mock.sh
│   │   └── system_tools_mock.sh
│   └── fixtures/
│       ├── sample_data.txt
│       ├── sample_csv.csv
│       └── malformed_data.txt
├── mariadb_preload.sql             # FIXED - sql_log_bin SESSION-only
├── mariadb_postload.sql            # FIXED - sql_log_bin SESSION-only
└── codex.md                        # EXISTS - Known issues documented
```

## Current Project State

### Main Scripts (All Working)
- `bulk_load.sh` - Automated bulk loading (tab-delimited ONLY currently)
- `mariadb_status.sh` - Mode detection and monitoring
- `mariadb_preload.sql` - Switch to extreme mode
- `mariadb_postload.sql` - Restore conservative mode
- `backup_current_config.sh` - Configuration backup
- `mariadb_performance.cnf` - Baseline configuration

### File Format Support (CURRENT LIMITATION)
**bulk_load.sh currently only supports TAB-DELIMITED format** (lines 120-124):
```sql
LOAD DATA LOCAL INFILE '$DATAFILE'
INTO TABLE $TABLE
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

**README.md mentions these formats** (not implemented):
- CSV (comma-separated)
- Custom delimiters (pipe, etc.)
- Different line terminators (\r\n for Windows)
- Header rows (IGNORE 1 LINES)

### Known Issues (from codex.md)
1. **No state snapshotting**: Scripts restore hard-coded values, not originals
2. **No trap handlers**: Ctrl+C leaves server in extreme mode
3. **SQL injection risk**: Database/table names not quoted
4. **Linux-specific**: Uses GNU tools (free, realpath, iostat)
5. **Hard-coded MYSQL_CMD**: mariadb_status.sh doesn't use user-supplied options

## Next Session Tasks

### Task 1: Add File Format Support to bulk_load.sh ⏳
**Priority**: HIGH
**File**: `/usr/local/lib/mariadb/bulk_load.sh`

Create one of these approaches:

#### Option A: Add command-line flags to bulk_load.sh
```bash
# Usage examples:
./bulk_load.sh mydb mytable file.csv --format=csv
./bulk_load.sh mydb mytable file.txt --delimiter='|'
./bulk_load.sh mydb mytable file.csv --format=csv --skip-header
```

Modify lines 18-29 to accept:
- `--format=csv|tsv|custom`
- `--delimiter='char'`
- `--line-terminator='\n|\r\n'`
- `--skip-header` (IGNORE 1 LINES)

Then modify lines 120-124 to use variables.

#### Option B: Create separate wrapper scripts
```bash
bulk_load_csv.sh   # Calls bulk_load.sh with CSV settings
bulk_load_pipe.sh  # Calls bulk_load.sh with pipe delimiter
```

**Reference**: See README.md lines 227-251 for format examples

### Task 2: Create Tests for New Functionality ⏳
**Priority**: HIGH
**Files**: `/usr/local/lib/mariadb/tests/unit/test_bulk_load_formats.sh`

After Task 1, create tests for:
- CSV format loading
- Custom delimiter handling
- Header row skipping
- Different line terminators
- Invalid format error handling

Use existing test framework and fixtures.

### Task 3: Create Append-Only Task Completion Log ⏳
**Priority**: MEDIUM
**File**: `/usr/local/lib/mariadb/.task_log`

Create a simple append-only log:
```
[YYYY-MM-DD HH:MM:SS] COMPLETED: Task description
```

Format:
- Each line is one completed task
- Never edit previous lines (append only)
- ISO 8601 timestamps
- First entry: "Prepared for context window reset"

## Quick Start Commands for Next Session

```bash
# Navigate to project
cd /usr/local/lib/mariadb

# Check current state
ls -la
cat SESSION_HANDOFF.md

# Run tests to verify nothing broke
cd tests && ./run_all_tests.sh

# Check for git changes (if repo)
# git status

# Start work on Task 1
cat bulk_load.sh | grep -A 10 "LOAD DATA"
cat README.md | grep -A 20 "CSV files"

# Read known issues
cat codex.md
```

## Key Context to Remember

### Architecture Pattern
1. **Conservative baseline** in mariadb_performance.cnf (64GB buffer)
2. **Runtime overrides** via preload.sql (extreme mode)
3. **Restoration** via postload.sql (back to conservative)
4. **Automation** via bulk_load.sh (orchestrates all steps)

### Critical Files
- `bulk_load.sh:120-124` - LOAD DATA statement (needs modification)
- `mariadb_status.sh:20` - Hard-coded MYSQL_CMD (known issue)
- `tests/run_all_tests.sh` - Run all tests
- `codex.md` - Known issues and improvement suggestions
- `README.md:227-251` - File format examples

### Testing Commands
```bash
cd /usr/local/lib/mariadb/tests

# Run all tests
./run_all_tests.sh

# Run specific suite
./unit/test_bulk_load.sh

# Test with mocks (no DB required)
export MOCK_MODE="extreme"
./unit/test_mariadb_status.sh
```

### File Permissions
All scripts should be executable:
```bash
chmod +x *.sh tests/**/*.sh
```

### Important Notes
- Tests use mocks - no MariaDB installation required for testing
- sql_log_bin is SESSION-only (recent fix in preload/postload)
- All 128 tests currently passing
- No git repo currently (may want to initialize)

## References for Next Session

- **CLAUDE.md**: `/usr/local/lib/mariadb/updates/CLAUDE.md`
- **Test README**: `/usr/local/lib/mariadb/tests/README.md`
- **Known Issues**: `/usr/local/lib/mariadb/codex.md`
- **User Guide**: `/usr/local/lib/mariadb/README.md`
- **Quick Reference**: `/usr/local/lib/mariadb/QUICK_REFERENCE.md`

## Common Pitfalls to Avoid

1. Don't use `SET GLOBAL sql_log_bin` (SESSION-only variable)
2. Don't forget to update tests when changing scripts
3. Quote SQL identifiers: Use backticks for table names
4. Test error paths, not just happy paths
5. Run tests before committing: `./tests/run_all_tests.sh`

## Session Metrics

- Files created: 15 (test suite)
- Files modified: 2 (SQL scripts - sql_log_bin fix)
- Lines of test code: ~1,720
- Tests written: 128 (106 unit + 22 integration)
- Test pass rate: 100%
- Context usage: ~86k/200k tokens (43%)

---

**Next Claude**: Start with Task 3 (create task log), then Task 1 (file formats), then Task 2 (tests). Good luck! 🚀

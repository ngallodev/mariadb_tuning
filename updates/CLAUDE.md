# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Conventions

### Task Status Log Signatures
When adding entries to `task_status.log`, **always add a signature** to identify who completed the task:
- Add `- Claude` at the end if you (Claude Code) completed it
- Add `- Codex` at the end if the user's other AI assistant completed it
- Format: `YYYY-MM-DD HH:MMZ | tag | description - Claude`

Example:
```
2025-10-16 07:45Z | testing | Added integration tests for file formats - Claude
2025-10-16 19:01Z | test_cleanup | Removed duplicate tests - Codex
```

### File Ownership
**DO NOT change file ownership** when editing files. All files should remain `nate:nate`.
- Use `sudo bash -c 'command'` for root-owned files if needed
- Never use `chown` or change permissions unless explicitly requested
- Verify ownership with `ls -la` if uncertain

### Testing Philosophy
- **Integration tests > Unit tests**: Focus on end-to-end workflows
- **Condense redundant tests**: Avoid testing the same thing multiple ways
- **Real behavior over edge cases**: Test actual use cases, not every possible error
- Current test count: ~120 tests (92 unit + 28 integration)

## Project Overview

This is a MariaDB bulk load optimization toolkit designed for high-performance multi-role servers (256GB RAM, 28 CPU cores). The project implements a **dual-mode resource strategy**:

- **Conservative Mode**: 64GB buffer pool (~25% RAM), normal ACID compliance, leaves resources for other services
- **Extreme Mode**: Temporarily maximizes session buffers (512MB-1GB), disables safety checks, achieves 10-20x faster bulk loading

The scripts automatically switch between modes during bulk data loads, then restore to conservative settings.

## Architecture

### Dual-Mode System
The architecture centers on dynamic mode switching:

1. **Baseline Configuration** (`mariadb_performance.cnf`): Conservative global settings (64GB buffer pool, ACID=1, IO capacity=200)
2. **Pre-Load SQL** (`mariadb_preload.sql`): Switches to extreme mode (ACID=0, IO capacity=2000-4000, massive session buffers)
3. **Post-Load SQL** (`mariadb_postload.sql`): Restores conservative mode and re-enables safety checks
4. **Automated Orchestration** (`bulk_load.sh`): Handles the entire lifecycle: pre-load → data load → post-load → analyze table

### Key Design Principles
- **Multi-role server optimized**: Conservative baseline leaves 192GB RAM free for other services
- **Temporary extreme mode**: Safety checks disabled only during bulk loads, not for normal operations
- **Automatic restoration**: Scripts ensure settings revert to safe defaults after loading completes
- **Session-level buffers**: Extreme buffers allocated per-connection to avoid impacting global memory

### Known Limitations (see codex.md)
- **No state snapshotting**: Scripts restore to hard-coded "conservative" values, not original pre-load values
- **No trap handlers**: Ctrl+C during bulk_load.sh leaves server in extreme mode
- **Global sql_log_bin issue**: Fixed in recent update - now SESSION-only (correct behavior)
- **SQL injection risk**: Database/table names not quoted in SQL statements
- **Linux-specific**: Uses GNU tools (free, realpath, iostat) that may not work on macOS/BSD

## Common Commands

### Build/Install Configuration
```bash
# Backup current MariaDB configuration
./backup_current_config.sh

# Install performance config (requires restart)
sudo cp mariadb_performance.cnf /etc/mysql/mariadb.conf.d/99-performance.cnf
sudo systemctl restart mariadb

# Verify installation
mysql -u root -p -e "SELECT @@innodb_buffer_pool_size/1024/1024/1024 AS 'Buffer Pool GB';"
```

### Bulk Loading Data

```bash
# Automated (recommended) - handles mode switching automatically
./bulk_load.sh <database> <table> <datafile.txt> ["-u root -p"]

# Manual mode switching
mysql -u root -p < mariadb_preload.sql
# ... load your data ...
mysql -u root -p < mariadb_postload.sql
```

### Monitoring and Status

```bash
# Check current mode (conservative vs extreme)
./mariadb_status.sh

# Real-time monitoring during bulk loads
watch -n 2 './mariadb_status.sh'

# Check specific settings
mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';"
```

### Testing and Validation

```bash
# Run all tests (unit + integration)
cd tests && ./run_all_tests.sh

# Run specific test suite
./tests/unit/test_bulk_load.sh
./tests/integration/test_full_workflow.sh

# Verify mode detection
./mariadb_status.sh | grep "Mode:"

# Time a bulk load operation
time ./bulk_load.sh testdb testtable sample_data.txt

# Check table statistics after load
mysql -u root -p -e "USE mydb; ANALYZE TABLE mytable; SHOW TABLE STATUS LIKE 'mytable'\\G"
```

### Test Suite Overview (Updated 2025-10-16)
- **Total tests**: ~120 (92 unit + 28 integration)
- **Unit tests**: 5 test files covering bulk_load, status, SQL scripts, backup, file format
- **Integration tests**: Full workflow validation including file format support
- **Test framework**: Custom bash framework with mocks (no DB required)
- **Key tests added**: CSV format, custom delimiters, header skipping
- **Test philosophy**: Focus on integration tests, condense redundant unit tests

### File Format Tools

```bash
# Check data file format and detect issues
./file_format_files/check_file_format.sh datafile.txt

# Create sample data files for testing
./file_format_files/create_sample_files.sh
```

## Script Behaviors

### bulk_load.sh
- **Input validation**: Checks for required arguments and file existence (bulk_load.sh:18-42)
- **Format parsing**: Parses format options (CSV, delimiters, headers, etc.) (bulk_load.sh:48-133)
- **File format support**: Full CSV, TSV, custom delimiter support with validation (bulk_load.sh:56-133)
- **Pre-load**: Applies extreme mode settings (both GLOBAL and SESSION) (bulk_load.sh:202-239)
- **Engine detection**: Automatically detects MyISAM vs InnoDB and optimizes accordingly (bulk_load.sh:244-256)
- **Data loading**: Uses dynamic `LOAD DATA LOCAL INFILE` with format variables (bulk_load.sh:260-289)
- **Post-load**: Restores conservative mode, runs `ANALYZE TABLE`, reports statistics (bulk_load.sh:293-349)
- **Error handling**: Exits on failure with `set -e`, trap handler for cleanup (bulk_load.sh:198-199)
- **WARNING**: Global settings changed without snapshotting original values - restore uses hard-coded defaults

### mariadb_status.sh
- **Mode detection**: Analyzes `innodb_flush_log_at_trx_commit`, `innodb_io_capacity`, and `innodb_adaptive_hash_index` (mariadb_status.sh:46-56)
- **Resource monitoring**: Shows memory (total, used, available, MariaDB-specific), CPU usage, disk I/O, connections (mariadb_status.sh:98-153)
- **Buffer pool analysis**: Compares data size to buffer pool size (mariadb_status.sh:156-171)
- **Recommendations**: Context-aware suggestions based on current mode (mariadb_status.sh:173-203)
- **ISSUE**: Hard-codes `sudo mariadb -u root` instead of using user-supplied MYSQL_OPTS (mariadb_status.sh:20)

### mariadb_preload.sql / mariadb_postload.sql
- **Global settings**: Modified dynamically (requires SUPER privilege)
- **Session settings**: Set for current connection only
- **Key toggles**:
  - `innodb_flush_log_at_trx_commit`: 1 (ACID) → 0 (every ~1s) → 1
  - `innodb_io_capacity`: 200 → 2000 → 200
  - `innodb_adaptive_hash_index`: ON → OFF → ON
  - `foreign_key_checks`, `unique_checks`, `sql_log_bin` (SESSION): All toggled OFF/ON
- **FIXED**: `sql_log_bin` now correctly set as SESSION-only (was incorrectly SET GLOBAL in older versions)

### backup_current_config.sh
- **Config backup**: Copies /etc/mysql/my.cnf and mariadb.conf.d/ to timestamped directory
- **Settings snapshot**: Exports current GLOBAL variables, InnoDB settings, status to text files
- **Restoration script**: Generates restore_settings.sql with captured values
- **ISSUE**: Only accepts first argument ($1), not full "$@" for multiple MySQL options

## Configuration File Structure

**mariadb_performance.cnf** uses a layered approach:
- **Buffer Pool**: 64GB split into 48 instances (1.3GB per instance for parallelism)
- **Log Files**: 2GB each for moderate write performance
- **I/O Threads**: 8 read + 8 write threads (conservative for multi-role server)
- **Connections**: 200 max connections (not extreme)
- **Session Buffers**: Small defaults (4MB sort, 2MB read) - increased only during loads
- **Location**: Place in `/etc/mysql/mariadb.conf.d/99-performance.cnf`

The config is designed to be **overridden at runtime** by preload/postload SQL scripts, not edited directly.

## Important Constraints

### Security and Safety
- **Extreme mode disables**: Foreign key checks, unique checks, binary logging, autocommit
- **Data durability**: `innodb_flush_log_at_trx_commit=0` means commits every ~1 second (not every transaction)
- **Never use extreme mode for**: Replication-dependent systems, production OLTP, when foreign keys must be validated during load
- **Privilege requirements**: Scripts require SUPER privilege and passwordless sudo/root access
- **SQL injection risk**: Database and table names not quoted - avoid special characters in names

### Critical Failure Modes
- **Interrupted bulk_load.sh**: Ctrl+C leaves server in extreme mode (no trap handler)
- **Manual mode switch**: If you run mariadb_preload.sql manually, you MUST run mariadb_postload.sql
- **Hard-coded restore**: Post-load scripts restore to hard-coded values, not captured originals
- **Recovery**: If stuck in extreme mode, manually run `mysql -u root -p < mariadb_postload.sql`

### Performance Expectations
- **Small rows (<100 bytes)**: 100K-500K rows/sec in extreme mode
- **Medium rows (100-500 bytes)**: 50K-200K rows/sec
- **Large rows (>500 bytes)**: 20K-100K rows/sec
- **Speedup**: 10-20x over conservative mode

### Resource Constraints
- **Normal operations**: ~70-80GB MariaDB memory usage, <10% CPU
- **Bulk loads**: ~80-100GB MariaDB memory usage, 200-800% CPU (2-8 cores)
- **Always available**: 130-186GB RAM and 20-26 cores for other services

## File Format Support (FULLY IMPLEMENTED ✓)

**bulk_load.sh** has complete file format support (lines 48-133):

### Supported Formats
- **CSV**: `--format=csv` (comma-delimited with quote enclosures)
- **TSV/Tab**: `--format=tsv` or `--format=tab` (default)
- **Custom**: `--delimiter='|'` for pipe, semicolon, etc.

### Supported Options
- `--format=csv|tsv|tab|custom` - Format type selection
- `--delimiter=CHAR` - Custom single-character delimiter
- `--enclosure=CHAR` - Field enclosure ('"' or "'") for CSV
- `--line-terminator=STR` - Line endings (\n or \r\n)
- `--skip-header` - Skip first line (IGNORE 1 LINES)

### Usage Examples
```bash
# CSV with header
./bulk_load.sh mydb mytable data.csv --format=csv --skip-header

# Pipe-delimited
./bulk_load.sh mydb mytable data.txt --delimiter='|'

# Windows line endings
./bulk_load.sh mydb mytable data.txt --line-terminator='\r\n'

# Tab-delimited (default - no flags needed)
./bulk_load.sh mydb mytable data.txt
```

### Implementation Details
- Format validation with error messages (lines 60-80)
- Dynamic LOAD DATA statement building (lines 271-275)
- Backward compatible (defaults to tab-delimited)
- MySQL options pass-through support

**NOTE**: This was NOT a TODO - it was already fully implemented when discovered on 2025-10-16.

## File Structure

```
/usr/local/lib/mariadb/
├── mariadb_performance.cnf       # Baseline conservative config
├── mariadb_preload.sql            # Switch to extreme mode
├── mariadb_postload.sql           # Restore conservative mode
├── bulk_load.sh                   # Automated bulk loading
├── mariadb_status.sh              # Mode & resource monitoring
├── backup_current_config.sh       # Backup tool
├── file_format_files/             # Data file validation tools
│   ├── check_file_format.sh       # Detect format issues
│   ├── create_sample_files.sh     # Generate test data
│   └── FILE_FORMAT_GUIDE.md       # Format documentation
├── codex.md                       # Known issues and review notes
├── README.md                      # User-facing documentation
├── QUICK_REFERENCE.md             # Mode comparison table
└── INSTALLATION_GUIDE.md          # Safe installation steps
```

## Coding Patterns

### Adding Safety Improvements
When modifying bulk_load.sh to add trap handlers:
```bash
# Capture original settings at start
ORIGINAL_FLUSH=$(mysql -sN -e "SELECT @@GLOBAL.innodb_flush_log_at_trx_commit")
ORIGINAL_IO=$(mysql -sN -e "SELECT @@GLOBAL.innodb_io_capacity")

# Add trap to restore on exit
trap 'restore_original_settings' EXIT INT TERM

restore_original_settings() {
  mysql -e "SET GLOBAL innodb_flush_log_at_trx_commit=$ORIGINAL_FLUSH"
  mysql -e "SET GLOBAL innodb_io_capacity=$ORIGINAL_IO"
  # ... restore other settings
}
```

### Quoting SQL Identifiers
When modifying scripts to prevent SQL injection:
```bash
# Bad (current)
mysql -e "USE $DATABASE; LOAD DATA ... INTO TABLE $TABLE"

# Good (recommended)
mysql --database="$DATABASE" -e "LOAD DATA ... INTO TABLE \`$TABLE\`"
```

## Troubleshooting

### "The used command is not allowed with this MariaDB version"
- Enable `local_infile=1` in config
- Connect with `mysql --local-infile -u root -p`

### "MySQL server has gone away"
- Increase `max_allowed_packet` (already set to 1GB in scripts)

### Slow performance during load
- Verify extreme mode: `innodb_flush_log_at_trx_commit` should be 0
- Check disk I/O: `iostat -x 5`
- Ensure no swap usage: `free -h`

### Settings not restored after load
- Manually run: `mysql -u root -p < mariadb_postload.sql`
- Check for script errors in bulk_load.sh output
- If bulk_load.sh was interrupted (Ctrl+C), extreme mode settings remain active

### Mode stuck in "MIXED MODE"
- Run postload to restore conservative: `mysql -u root -p < mariadb_postload.sql`
- Or run preload for full extreme: `mysql -u root -p < mariadb_preload.sql`

### mariadb_status.sh fails with authentication error
- Script hard-codes `sudo mariadb -u root` instead of using passed credentials
- Workaround: Ensure passwordless sudo and root socket auth are configured
- Or modify MYSQL_CMD variable in mariadb_status.sh:20

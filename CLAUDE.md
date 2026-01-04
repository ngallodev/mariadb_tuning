# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🔄 WORKFLOW METHODOLOGY (IMPORTANT)

All Claude Code sessions in this repository follow a **Batch Approval Workflow** to ensure careful, deliberate changes:

### Core Principles
- **No changes until approved**: Files are queued on disk, NOT staged in git
- **Batch approval model**: Review all planned work before any changes are applied
- **Transparency**: Full visibility into what will be changed before it happens
- **No git objects created**: Changes stay on disk until directly requested

### Workflow Steps

**1. INITIALIZATION (At Session Start)**
```
- Initialize task list with TodoWrite
- Plan all intended work
- Show user what will be done
- WAIT for explicit batch approval
```

**2. QUEUE CHANGES (Not in git yet)**
```
- Create files on disk
- Run tests to verify
- Queue changes WITHOUT git staging
- Show what's ready but not committed
- Request batch approval if needed
```

**3. GET EXPLICIT APPROVAL**
```
- Present comprehensive summary
- Show all files to be created/modified
- Wait for user "yes, proceed" or specific instructions
- NEVER proceed without approval
```

**4. EXECUTE (Only after approval)**
```
- Make approved changes only
- Create git objects ONLY if explicitly requested
- Document what was changed
- Log to task status
```

**5. COMPLETE & DOCUMENT**
```
- Update task list with completions
- Document in agent_files/task_status.log with "- Claude" signature
- Provide clear summary for future sessions
- Show exactly what was queued and what's ready
```

### Key Rules
✅ **DO:**
- Use TodoWrite to track ALL planned work upfront
- Queue changes on disk first
- Get explicit batch approval before any action
- Explain the complete plan before executing
- Document everything clearly

❌ **DON'T:**
- Create git objects without explicit request
- Stage files in git without approval
- Make changes without showing user first
- Skip the batch approval step
- Make assumptions about what user wants

### Example Workflow in Action
```
1. User: "Please add tests for X, update Y, and fix Z"
2. Claude: Initialize TodoWrite with 3 tasks
3. Claude: Create files on disk for all work
4. Claude: Show summary: "Here are 15 files queued, 3 tests created..."
5. Claude: "Please review and approve these changes"
6. User: "Approved! But can you also...?"
7. Claude: Update TodoWrite, adjust plan, show new changes
8. User: "Yes, proceed"
9. Claude: Execute ONLY the approved changes
10. Claude: Document completions in task log
```

## 🤝 MULTI-AGENT COORDINATION (IMPORTANT)

Multiple AI agents may work in this repository. Follow these rules to avoid conflicts and ensure smooth collaboration:

### Before Starting Work
```
1. Read agent_files/task_status.log (last 10 lines) to see what other agents did
2. Check agent_files/SESSION_HANDOFF.md for current state and blockers
3. Check agent_files/.NEXT_TASKS for prioritized work and agent notes
4. Run: git status
   - Look for uncommitted changes from other agents
   - Check for queued files on disk (should see ??)
5. Read .git/index.lock if it exists - may indicate another agent is working
```

### Agent Identification
Every agent must identify itself in logs:
```
Format: YYYY-MM-DD HH:MMZ | tag | description - AgentName
Examples:
  2025-11-02 14:30Z | feature | Added bulk load support - Claude
  2025-10-16 09:15Z | testing | Fixed SQL injection - Codex
  2025-11-02 15:45Z | docs | Updated README - Claude
```

**Known agents in this repo:**
- `Claude` - Current AI assistant (Claude Code)
- `Codex` - Previous AI assistant (OpenAI)
- `nate` - Human developer (repository owner)

### Conflict Prevention Rules

**✅ Safe Actions:**
- View any files (reading doesn't conflict)
- Queue new files on disk (don't modify existing queued files)
- Add to agent_files/task_status.log with your agent name
- Create new git branches for experimental features: `agent-agentname-feature`
- Update agent_files/SESSION_HANDOFF.md with your current status
- Modify files you're actively documenting in TodoWrite

**⚠️ Caution Required:**
- Check git log before modifying critical files (CLAUDE.md, agent_files/SESSION_HANDOFF.md, bulk_load.sh)
- If another agent modified a file in the last 2 hours, ask before changing it
- Don't delete .git/config or tracked files without explicit user request

**❌ Forbidden Actions:**
- Modifying agent_files/task_status.log entries from other agents
- Deleting queued files (??  status) without understanding their purpose
- Force-pushing to main branch
- Changing another agent's unfinished work without explicit approval
- Modifying .git/ internals or git hooks

### File Ownership & Respect

**Respect These Permissions:**
```
nate:nate  644  bulk_load.sh          - Never change ownership
nate:nate  644  mariadb_status.sh     - Never change ownership
nate:nate  644  mariadb_performance.cnf - Critical config
nate:nate  755  tests/run_all_tests.sh - Shared test framework
```

**Always Use:**
```bash
# For root-owned files (if needed)
sudo bash -c 'command here'

# Never:
chown -R claude:claude /usr/local/lib/mariadb  # WRONG!
```

### Communication via Documentation

**agent_files/task_status.log** - Real-time activity log
- Append-only (never modify existing entries)
- Use for: progress updates, blockers, completed work
- Format: `YYYY-MM-DD HH:MMZ | tag | description - AgentName`
- Example: `2025-11-02 15:30Z | workflow | Fixed test framework issue - Claude`

**agent_files/SESSION_HANDOFF.md** - Session summaries and state
- Update at END of session with what you accomplished
- Note blockers for next agent
- Document queued files and their status
- Example section:
  ```
  ## Last Session (Agent: Claude, 2025-11-02)
  - Created 13 new files (pipeline stages + tests)
  - All 13 tests passing (100% success rate)
  - Files queued on disk (not in git) - waiting for user approval
  - Status: READY FOR DEPLOYMENT
  ```

**agent_files/.NEXT_TASKS** - Prioritized work queue
- Add new tasks at bottom with agent availability
- Mark completed tasks with ✅
- Note dependencies and blockers
- Example: `[ ] Monitor soharaa removal on GitHub - Due: 2025-11-05 (Claude or any agent)`

### Handling Queued Files

If you see files with `??` status in git:
```bash
# These are queued but not staged
git status | grep "^??"

# Before modifying them:
1. Read agent_files/SESSION_HANDOFF.md - why are they queued?
2. Check agent_files/task_status.log - what agent created them?
3. If recent (<2 hours), ask in log before changing
4. If old (>24 hours) with no activity, safe to modify
5. Never delete - queue for deletion explicitly in agent_files/task_status.log
```

### Branch Strategy for Parallel Work

For experimental features or multiple agents:
```bash
# Create agent-specific branch
git checkout -b agent-claude-feature-x
git checkout -b agent-codex-feature-y

# Main branch stays stable
# Merge only after testing and approval
```

### Debugging Conflicts

**If you see git merge conflicts:**
```bash
# 1. Don't force-push
# 2. Contact other agent via agent_files/task_status.log
# 3. Work on separate branches
# 4. Let user decide merge strategy
```

**If .git/index.lock exists:**
```bash
# Another agent is working - wait or check:
ps aux | grep -E 'git|ssh|rsync'
# Remove lock ONLY if you're 100% sure process isn't running:
rm .git/index.lock
```

### Examples of Good Coordination

**Good: Documenting your work**
```
2025-11-02 14:30Z | feature | Adding file format detection - Claude
2025-11-02 14:35Z | feature | Created stage1_extract_insert_values.py - Claude
2025-11-02 14:45Z | testing | Added 5 format detection tests - Claude
2025-11-02 15:00Z | approval | Queued 13 files, awaiting user batch approval - Claude
```

**Good: Handling blockers**
```
2025-11-02 15:15Z | blocker | Cannot modify CLAUDE.md - Codex modified it 10 min ago - Claude
2025-11-02 15:16Z | action | Waiting for Codex to finish, will merge after - Claude
```

**Good: Respecting queued files**
```
2025-10-16 10:00Z | integration | Created test_file_format_pipeline.sh (13 tests) - Claude
[sits queued on disk for user approval]
2025-11-02 14:00Z | coordination | Noticed queued test file, reviewed and verified - Codex
2025-11-02 14:05Z | coordination | Test still valid, no changes needed - Codex
```

### Questions to Ask Yourself

Before making changes:
1. Is another agent actively working on this file? (check timestamps)
2. Are there queued files I should understand first?
3. Does my change conflict with agent_files/.NEXT_TASKS priorities?
4. Have I documented my work in agent_files/task_status.log?
5. Should I use a separate branch?
6. Does the user need to approve this in a batch?

## Project Overview

MariaDB bulk load optimization toolkit for high-performance multi-role servers (256GB RAM, 28 cores). The system implements a **dual-mode resource strategy** for optimal MariaDB performance:

- **Conservative Mode**: Baseline configuration with 64GB buffer pool, ACID compliance, leaves resources for other server roles
- **Extreme Mode**: Temporary performance boost (10-20x faster) by disabling safety checks and maximizing session buffers

The architecture automatically switches between modes during bulk loading, then restores conservative settings when done.

## Quick Start Commands

### Running Bulk Loads
```bash
# Simple tab-delimited load
./bulk_load.sh mydb mytable data.txt

# CSV format with header skipping
./bulk_load.sh mydb mytable data.csv --format=csv --skip-header

# Custom pipe delimiter
./bulk_load.sh mydb mytable data.txt --delimiter='|'

# Multiple chunked files
./bulk_load.sh mydb mytable 'output/chunks/*.tsv'

# With MySQL credentials
./bulk_load.sh mydb mytable data.txt -u root -p
```

### Monitoring & Status
```bash
# Check current mode and resource usage
./mariadb_status.sh

# Watch resources in real-time (updates every 2 seconds)
watch -n 2 './mariadb_status.sh "-u root -p"'

# Manual mode switching
mysql -u root -p < mariadb_preload.sql    # Enable extreme mode
mysql -u root -p < mariadb_postload.sql   # Restore conservative mode
```

### Testing
```bash
# Run entire test suite
cd tests && ./run_all_tests.sh

# Run single test file
bash tests/unit/test_bulk_load.sh
bash tests/integration/test_full_workflow.sh
```

## High-Level Architecture

### Core Configuration Strategy

1. **Baseline Configuration** (`mariadb_performance.cnf`)
   - 64GB InnoDB buffer pool (25% of 256GB RAM)
   - 48 buffer pool instances for parallelism
   - Leaves ~192GB RAM for other services
   - ACID-compliant settings (innodb_flush_log_at_trx_commit = 1)

2. **Bulk Load Automation** (`bulk_load.sh`)
   - Captures original global settings before changes
   - Applies extreme mode optimizations (SESSION and GLOBAL)
   - Executes LOAD DATA INFILE with format-specific options
   - Restores original settings and analyzes table
   - Handles interrupts with trap cleanup handler
   - **File format support**: CSV, TSV, custom delimiters, header skipping

3. **Runtime Mode Switching**
   - `mariadb_preload.sql`: Enables extreme mode (flush_log = 0, safety checks disabled)
   - `mariadb_postload.sql`: Restores conservative mode
   - `bulk_load.sh`: Automatically applies both via MySQL session

### Data Flow During Bulk Load

```
user runs bulk_load.sh
    ↓
capture original GLOBAL settings
    ↓
SET GLOBAL extreme mode settings (flush_log=0, io_capacity=2000, etc.)
SET SESSION extreme mode settings (512MB buffers, disable checks)
    ↓
LOAD DATA LOCAL INFILE (formatted data from file)
    ↓
COMMIT transaction
    ↓
ANALYZE TABLE (update statistics)
    ↓
restore original GLOBAL settings
    ↓
display statistics (rows/second, duration)
```

### Session-Based vs Global Settings

**Important distinction** for modifying code:
- **SESSION variables**: Per-connection settings (affected by `SET SESSION`)
- **GLOBAL variables**: Server-wide settings (affected by `SET GLOBAL`)
- `bulk_load.sh` uses GLOBAL for safety settings to prevent concurrent connections from interfering
- Trap handler restores GLOBAL values on interruption

## Key File Locations & Purposes

| File | Purpose | Key Behavior |
|------|---------|--------------|
| `bulk_load.sh:1-50` | Argument parsing & format detection | Validates format (csv/tsv/tab/custom) |
| `bulk_load.sh:73-172` | Option parsing loop | Builds MYSQL_OPTS array and DATA_PATTERNS array |
| `bulk_load.sh:212-224` | Capture original settings | Stores ORIG_* variables before modifications |
| `bulk_load.sh:256-274` | Pre-load GLOBAL optimizations | Sets extreme mode for entire server |
| `bulk_load.sh:323-347` | LOAD DATA execution | Builds dynamic SQL with format options |
| `bulk_load.sh:369-391` | Settings restoration | Restores original GLOBAL values, analyzes table |
| `bulk_load.sh:228-250` | Cleanup trap handler | Restores settings on INT/TERM/ERR signals |
| `mariadb_status.sh:41-73` | Mode detection logic | Checks flush_log (0=extreme, 1=conservative) and io_capacity |
| `mariadb_preload.sql` | Extreme mode template | Set GLOBAL and SESSION for maximum speed |
| `mariadb_postload.sql` | Conservative mode template | Restores safe defaults |
| `mariadb_performance.cnf` | Base configuration | Conservative mode baseline (64GB buffer pool) |
| `tests/run_all_tests.sh` | Test orchestration | Runs unit and integration test suites |
| `tests/unit/test_bulk_load.sh` | Bulk load validation | Tests file format, truncate, and basic functionality |
| `tests/integration/test_full_workflow.sh` | End-to-end testing | Tests complete load workflow with different formats |

## File Format Support Details

The `bulk_load.sh` script supports multiple input formats via command-line options:

### Format Options in bulk_load.sh (lines 73-133)
```bash
--format=csv              # Sets delimiter=',', enclosure="", line_terminator='\n'
--format=tsv              # Sets delimiter='\t' (default)
--format=tab              # Alias for tsv
--format=custom           # Requires --delimiter
--delimiter=X             # Single-char field delimiter
--enclosure='"'           # Field enclosure (for CSV)
--line-terminator='\n'    # Line ending ('\n' or '\r\n')
--skip-header             # Skip first line (IGNORE 1 LINES)
```

### LOAD DATA Syntax (lines 337-341)
The script builds a dynamic LOAD DATA statement:
```sql
LOAD DATA LOCAL INFILE 'file'
INTO TABLE tablename
FIELDS TERMINATED BY 'delimiter' [ENCLOSED BY 'enclosure']
LINES TERMINATED BY 'terminator'
IGNORE N LINES;
```

## Testing Architecture

### Test Framework
- Custom Bash testing framework (`tests/test_framework.sh`)
- Mock system for dependency isolation (`tests/mocks/`)
- ~120 total tests (92 unit + 28 integration)

### Test Categories
- **Unit Tests**: Individual script functionality (format parsing, settings capture)
- **Integration Tests**: Full workflows with real MySQL connections
- **Philosophy**: Prefer integration tests over redundant unit tests; focus on actual use cases

### Running Tests
```bash
# All tests
cd tests && ./run_all_tests.sh

# Specific test file
bash tests/unit/test_bulk_load.sh
bash tests/integration/test_full_workflow.sh
```

## Important Conventions

### Task Status Log Signature
When logging activities to `task_status.log`, always add a signature:
```
Format: YYYY-MM-DD HH:MMZ | tag | description - Claude
Example: 2025-10-16 08:45Z | testing | Added new tests - Claude
```

### File Ownership
All files must remain `nate:nate`. If modifying files owned by root, use `sudo bash -c 'command'` instead of changing ownership.

### Trap Handler Pattern
When modifying `bulk_load.sh`, preserve the trap cleanup handler (lines 228-250). This ensures GLOBAL settings are restored if the user interrupts with Ctrl+C.

### Volatile Folders
The `/usr/local/lib/mariadb/tmp/` folder is **volatile** and should not be relied upon:
- Files may not exist in future sessions
- Don't assume test data persists
- Don't create files expecting persistence
- Reference committed test files or create your own as needed
- Always verify file existence before using in tests

## Known Issues & Limitations

See `codex.md` for detailed discussion:

1. **No state snapshotting**: Scripts restore hard-coded values from SQL scripts, not original settings captured at runtime (partially fixed in bulk_load.sh)
2. **No trap handlers in SQL scripts**: Running `mariadb_preload.sql` directly leaves server in extreme mode if interrupted
3. **SQL injection risk**: Database and table names not quoted in SQL statements (uses backticks inconsistently)
4. **Linux-specific**: Uses GNU tools (free, realpath, iostat) - won't work on macOS/BSD without gsed/gutils
5. **Hard-coded MYSQL_CMD**: `mariadb_status.sh` always uses `sudo mariadb` - doesn't fully respect user-supplied options

## Development Patterns

### When Adding Features
1. Modify scripts in `/usr/local/lib/mariadb/` root directory
2. Add corresponding unit tests in `tests/unit/`
3. Add integration tests in `tests/integration/` for end-to-end validation
4. Run full test suite: `cd tests && ./run_all_tests.sh`
5. Commit with "- Claude" signature inagent_files/task_status.log

### When Modifying bulk_load.sh
- Respect the argument parsing section (lines 73-172)
- Preserve the capture/restore pattern for GLOBAL settings
- Keep the trap cleanup handler intact
- Test with multiple file formats if changing LOAD DATA syntax

### When Modifying mariadb_status.sh
- Mode detection logic (lines 64-73) depends on specific threshold values
- IO_CAPACITY >= 1000 indicates extreme mode
- Preserve the query helper function (lines 28-33)

## Performance Expectations

### Conservative Mode (Normal Operations)
- Memory: ~70-80GB MariaDB process
- CPU: <100% (1-2 cores active)
- I/O: <100 IOPS
- Available for other services: ~156-186GB RAM, 20-26 cores

### Extreme Mode (During Bulk Loads)
- Memory: ~80-100GB MariaDB process
- CPU: 200-800% (2-8 cores active)
- I/O: 1000-4000 IOPS
- Load speed: 10-20x faster (50,000-500,000+ rows/second typical)

### Tuning Guidance
- Pre-sort data in file to match primary key order for better cache hits
- Drop indexes before loading empty tables, recreate after
- Use multiple parallel loads for very large datasets
- Increase file system cache: `sysctl -w vm.dirty_ratio=80`

## GitHub & Contributors

- **Repository**: https://github.com/ngallodev/mariadb_tuning
- **Creator**: Nate Gallo ([@ngallodev](https://github.com/ngallodev))
- **AI Development**: Claude Code (Anthropic)
- **License**: GNU GPL v3

See `CONTRIBUTORS.md` for detailed contribution breakdown.

## Quick Navigation

```bash
# Project root
cd /usr/local/lib/mariadb

# Read recent activity
tail -30agent_files/task_status.log

# Check next priorities
cat .NEXT_TASKS

# Verify tests pass
cd tests && ./run_all_tests.sh

# Check git history
git log --oneline -10
```


# Multi-Agent Coordination Guide

**Last Updated**: 2025-11-02
**Status**: ACTIVE for all sessions
**Purpose**: Ensure smooth collaboration between multiple AI agents (Claude, Codex, etc.) working in the same repository

---

## 📌 QUICK REFERENCE

### Before You Start
```bash
# 1. Check for ongoing work
tail -50agent_files/task_status.log              # See what agents did recently
git status                            # Check for queued files or conflicts
ls -la .git/index.lock 2>/dev/null    # Check if another agent is working

# 2. Read coordination info
cat agent_files/SESSION_HANDOFF.MD                # Current state and blockers
cat .NEXT_TASKS                       # Prioritized work

# 3. Understand your workspace
git branch -a                         # Check for agent-specific branches
git log --oneline -5                  # See recent commits

# ⚠️ IMPORTANT: /tmp/ folder is volatile
# - Files in /usr/local/lib/mariadb/tmp/ may not exist in future sessions
# - Don't assume test data is present
# - Don't create files expecting them to persist
# - Reference committed test files or create your own as needed
```

### When You Start Work
```bash
# 1. Identify yourself in logs
# Include your agent name in EVERYagent_files/task_status.log entry:
# Format: YYYY-MM-DD HH:MMZ | tag | description - AgentName

# 2. Plan upfront
# Use TodoWrite to track all planned work
# Show user the plan before executing

# 3. Document progress
# Append toagent_files/task_status.log with agent name
# Update agent_files/SESSION_HANDOFF.MD when session ends
```

---

## 🤖 Known Agents

| Agent | Type | Version | Status |
|-------|------|---------|--------|
| Claude | AI (Anthropic) | Claude Code | Active (current) |
| Codex | AI (OpenAI) | N/A | Inactive (contributed previously) |
| nate | Human | N/A | Repository owner |

### Agent History
- **Codex**: Initial development and testing framework creation
- **Claude**: File format pipeline, batch workflow, multi-agent coordination
- **nate**: Project owner, approves all changes

---

## 📋 COORDINATION PROTOCOLS

### Protocol 1: Starting Your Session

**When you initialize**, follow this sequence:

```
Step 1: ANALYZE CURRENT STATE
├─ tail -50agent_files/task_status.log (see recent work)
├─ cat agent_files/SESSION_HANDOFF.MD (understand blockers)
├─ cat .NEXT_TASKS (check priorities)
├─ git status (look for queued files or index.lock)
└─ git branch -a (check for agent-specific branches)

Step 2: PLAN YOUR WORK
├─ Initialize TodoWrite with all tasks
├─ Check if your work conflicts with other agents
├─ Review queued files (??  status) - don't touch them yet
└─ Show user the complete plan

Step 3: WAIT FOR APPROVAL
├─ Explain batch approval workflow
├─ Document your agent name
├─ Do NOT proceed without explicit approval
└─ Be ready to adjust based on user feedback
```

### Protocol 2: Usingagent_files/task_status.log (Append-Only Log)

**Format** for every entry you add:
```
YYYY-MM-DD HH:MMZ | tag | description - AgentName
```

**Tags** (use consistently):
- `feature` - New functionality
- `testing` - Test-related work
- `bugfix` - Fixing issues
- `docs` - Documentation updates
- `refactor` - Code improvements
- `coordination` - Multi-agent communication
- `blocker` - Blocking issues
- `approval` - Awaiting user approval
- `workflow` - Workflow changes

**Examples**:
```
2025-11-02 14:30Z | feature | Created stage1_extract_insert_values.py - Claude
2025-11-02 14:35Z | testing | Added 13 integration tests - Claude
2025-11-02 15:00Z | approval | Queued 13 files, awaiting batch approval - Claude

2025-11-02 15:15Z | coordination | Noticed Claude's queued files, verified compatibility - Codex
2025-11-02 15:30Z | blocker | Cannot merge feature branch - conflicts with Claude's work - Codex
2025-11-02 15:35Z | coordination | Waiting for Claude to finish before merging - Codex
```

### Protocol 3: Handling Queued Files

When you see files with `??` status (untracked):

```bash
# Step 1: Identify queued files
git status | grep "^??"

# Step 2: Understand why they're queued
# Read agent_files/SESSION_HANDOFF.MD
# Checkagent_files/task_status.log for agent notes
# Look at file timestamps: stat filename

# Step 3: Decide what to do
# If recent (<2 hours old):
#   → Ask agent inagent_files/task_status.log before modifying
#   → Don't delete them
#   → Understand their purpose first
#
# If old (>24 hours, no recent activity):
#   → Safe to modify or ask user about deployment
#   → Still read comments first
```

**Safe with queued files:**
- ✅ Reading them to understand intent
- ✅ Running tests on them
- ✅ Adding new files to the same directory
- ✅ Documenting their status

**NOT safe with queued files:**
- ❌ Deleting them without understanding why
- ❌ Modifying them without asking creator
- ❌ Staging them in git without explicit approval
- ❌ Force-pushing changes that affect them

### Protocol 4: Modifying Critical Files

**Critical files** that multiple agents might touch:
- `CLAUDE.md` - Project guidance
- `SESSION_HANDOFF.md` - Session coordination
- `.NEXT_TASKS` - Work prioritization
- `bulk_load.sh` - Core functionality
- `task_status.log` - Coordination log
- `.git/config` - Git configuration

**Before modifying critical files:**

```bash
# Step 1: Check recent history
git log --oneline -10 --follow -- FILENAME

# Step 2: Check git blame for recent changes
git blame FILENAME | head -20

# Step 3: If another agent modified it in last 2 hours:
# → Document inagent_files/task_status.log that you want to change it
# → Wait for their response or user guidance
# → Don't force-push changes
```

**Safe modifications:**
```bash
# 1. Document your intent
echo "2025-11-02 15:45Z | docs | Updating CLAUDE.md coordination section - Claude" >>agent_files/task_status.log

# 2. Make your changes locally
# (files remain on disk, not staged yet)

# 3. If conflict potential:
# → Create agent-specific branch: git checkout -b agent-claude-docs-update
# → Work on branch without affecting main
# → Request user approval for merge
```

### Protocol 5: Handling Conflicts

**If you detect a conflict**:

```
Scenario: You want to modify CLAUDE.md, but Codex changed it 30 minutes ago

Step 1: Document inagent_files/task_status.log
"2025-11-02 15:45Z | coordination | Need to modify CLAUDE.md - Codex touched it 30 min ago - Claude"

Step 2: Check what Codex did
git log -1 --oneline CLAUDE.md

Step 3: Either:
  A) Wait for Codex to finish (check for activity in log)
  B) Create agent-specific branch: git checkout -b agent-claude-feature
  C) Ask user: "Codex just modified CLAUDE.md, should I proceed or wait?"

Step 4: Never force-push
# WRONG:
git push --force origin main

# RIGHT:
git checkout -b agent-claude-feature
git push -u origin agent-claude-feature
# Tell user about the branch and ask for merge approval
```

**If .git/index.lock exists**:
```bash
# Another agent is using git right now
# DO NOT remove the lock unless:
# 1. You've verified the process isn't running: ps aux | grep git
# 2. You've waited a reasonable time (5-10 minutes)
# 3. You've checkedagent_files/task_status.log for activity
# 4. You've documented the removal

# If you remove it, log it:
echo "2025-11-02 15:50Z | coordination | Removed .git/index.lock (no git process running) - Claude" >>agent_files/task_status.log
```

---

## 🌳 BRANCH STRATEGY

For parallel work by multiple agents:

```
main (stable, shared)
  ├─ agent-claude-feature-x (Claude's feature work)
  │   └─ [tested, queued for user approval]
  │
  ├─ agent-codex-bugfix-y (Codex's bug fixes)
  │   └─ [in progress or awaiting approval]
  │
  └─ experimental/feature-z (Shared exploration branch)
      └─ [multiple agents contributing]
```

**Rules for branches**:
- ✅ Agent-specific branches protect main from concurrent edits
- ✅ Feature branches can be tested independently
- ✅ Main stays stable and deployable
- ❌ Never force-push to main
- ❌ Don't merge without user approval

**Creating agent branch**:
```bash
git checkout -b agent-claude-feature-name
# Make changes, test, queue on disk
# When ready, push:
git push -u origin agent-claude-feature-name
```

**Merging to main**:
```bash
# ONLY after user approves:
git checkout main
git merge agent-claude-feature-name
# Then update agent_files/SESSION_HANDOFF.MD with what was merged
```

---

## 📊 COMMUNICATION CHANNELS

### Primary:agent_files/task_status.log
- **Purpose**: Real-time activity log
- **Format**: Append-only with timestamps
- **Frequency**: Updated as you work
- **Visibility**: All agents see it immediately

### Secondary: agent_files/SESSION_HANDOFF.MD
- **Purpose**: Session summaries and state
- **Update**: At END of session
- **Content**: What you accomplished, blockers for next agent
- **Frequency**: Once per session

### Tertiary: .NEXT_TASKS
- **Purpose**: Prioritized work queue
- **Update**: When you start/complete tasks
- **Format**: Markdown checklist with agent notes
- **Frequency**: As priorities change

### Code Comments
- **Purpose**: Document complex decisions
- **Style**: Referenceagent_files/task_status.log entries
- **Example**:
  ```bash
  # Seeagent_files/task_status.log 2025-11-02 15:30Z - Claude
  # This pattern prevents conflicts with Codex's work
  ```

---

## 🔄 EXAMPLE COORDINATION SCENARIO

**Scenario**: Claude and Codex working simultaneously

```
Timeline:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2025-11-02 14:00Z - Claude initializes
├─ Readsagent_files/task_status.log (empty or old)
├─ Checks agent_files/SESSION_HANDOFF.MD (Codex last worked here)
├─ Sees 13 queued test files
├─ Logs: "2025-11-02 14:00Z | coordination | Starting new session, found 13 queued tests - Claude"
└─ Checks Codex's notes, understands tests are pending approval

2025-11-02 14:15Z - Claude creates improvement
├─ Makes small changes to existing queued tests
├─ Logs: "2025-11-02 14:15Z | testing | Minor improvements to test_file_format_pipeline.sh - Claude"
├─ Creates: agent-claude-test-improvements branch
└─ Doesn't touch main or stage files yet

2025-11-02 14:30Z - Codex initializes
├─ Readsagent_files/task_status.log (sees Claude working on tests)
├─ Logs: "2025-11-02 14:30Z | coordination | Noticed Claude improving tests, will focus on docs - Codex"
├─ Checks .NEXT_TASKS (finds documentation items)
└─ Works on separate files (README.md, CLAUDE.md)

2025-11-02 14:45Z - Codex wants to modify CLAUDE.md
├─ Checks git log: "Claude modified it 10 min ago"
├─ Logs: "2025-11-02 14:45Z | coordination | CLAUDE.md modified by Claude recently, creating branch - Codex"
├─ Creates: agent-codex-docs-update branch
├─ Makes changes on branch (doesn't affect main)
└─ Documents changes in commit message

2025-11-02 15:00Z - User approves Claude's test improvements
├─ Claude merges: agent-claude-test-improvements → main
├─ Updates: agent_files/SESSION_HANDOFF.MD with what was merged
├─ Logs: "2025-11-02 15:00Z | approval | Merged test improvements to main - Claude"
└─ Continues with next task

2025-11-02 15:15Z - User approves Codex's docs changes
├─ Codex merges: agent-codex-docs-update → main
├─ Updates: agent_files/SESSION_HANDOFF.MD with what was merged
├─ Logs: "2025-11-02 15:15Z | approval | Merged docs improvements to main - Codex"
└─ Notes: "No conflicts with Claude's test changes - clean merge"

2025-11-02 15:30Z - Both agents document and handoff
├─ Claude updates: agent_files/SESSION_HANDOFF.MD (tests, improvements)
├─ Codex updates: agent_files/SESSION_HANDOFF.MD (docs changes)
├─ Both: Log completion inagent_files/task_status.log
└─ Next agent finds clean state with full history
```

---

## ✅ BEST PRACTICES

### 1. Always Read Before Starting
```bash
# Spend 5 minutes here BEFORE any work
tail -50agent_files/task_status.log
cat agent_files/SESSION_HANDOFF.MD
cat .NEXT_TASKS
git status
```

### 2. Identify Yourself Consistently
- Same agent name in ALL logs
- Use git author config for commits
- Document your role in agent_files/SESSION_HANDOFF.MD

### 3. Document Decisions
```bash
# When making non-obvious choices:
echo "2025-11-02 16:00Z | feature | Using agent branch for parallel work (Codex also working) - Claude" >>agent_files/task_status.log
```

### 4. Respect Ownership
- Don't delete queued files
- Don't modify files <2 hours old without asking
- Don't force-push to main
- Don't change .git/config

### 5. Test Before Approving
- Run test suite: `cd tests && ./run_all_tests.sh`
- Verify no new errors
- Document results inagent_files/task_status.log

### 6. Update agent_files/SESSION_HANDOFF.MD at Session End
```markdown
## Last Session (Agent: Claude, 2025-11-02)

**Completed:**
- Updated coordination documentation (CLAUDE.md, agent_files/SESSION_HANDOFF.MD)
- Createdagent_files/MULTI_AGENT_COORDINATION.md guide
- All tests still passing (13/13)

**Status:**
- No blockers
- Ready for Codex to continue with next features

**Notes for Next Agent:**
- Multi-agent coordination now documented
- All workflow files up to date
- Current .NEXT_TASKS prioritizes monitoring GitHub contributors
```

---

## 🚨 CRITICAL DON'Ts

1. **Don't force-push**: `git push --force origin main` ❌
2. **Don't delete queued files**: `rm file_format_files/stage1*.py` ❌
3. **Don't modify other agent's logs**: Editagent_files/task_status.log from Codex ❌
4. **Don't ignore conflicts**: Silently merge incompatible changes ❌
5. **Don't work without branching**: Edit main while other agent works ❌
6. **Don't skip approval**: Apply changes without user approval ❌
7. **Don't hoard decisions**: Make choices without documenting ❌
8. **Don't remove .git/ locks**: Without checking for active processes ❌

---

## 📞 GETTING HELP

If you're unsure:

1. **Check CLAUDE.md** - Main guidance document
2. **Check agent_files/SESSION_HANDOFF.MD** - Current state
3. **Checkagent_files/task_status.log** - What other agents did
4. **Ask inagent_files/task_status.log** - Log your question
5. **Wait for user guidance** - Don't guess

Example:
```
2025-11-02 16:15Z | coordination | Should I merge Codex's branch or wait? Conflicting changes detected - Claude
```

---

## 🎓 LEARNING FROM HISTORY

Review past coordination:
```bash
# See what agents did
git log --grep="-Claude" --oneline
git log --grep="-Codex" --oneline

# Understand decisions
git show COMMIT_HASH

# Track evolution
catagent_files/task_status.log | grep "2025-10"
```

---

**Last Updated**: 2025-11-02
**Next Review**: When adding new agents or changing workflow

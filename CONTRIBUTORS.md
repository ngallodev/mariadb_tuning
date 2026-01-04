# Contributors

This project was developed using AI-assisted development by multiple agents.

## Project Owner
- **Nate Gallo** ([@ngallodev](https://github.com/ngallodev))
  - Project creator and maintainer
  - System architecture and requirements
  - Final approval and direction for all features

## AI Development

### Codex (OpenAI)
**Primary developer - Core functionality and pipeline implementation**
- Initial project structure and architecture design
- Bulk load automation (`bulk_load.sh`) - complete implementation
- MariaDB mode switching (`mariadb_status.sh`, `mariadb_preload.sql`, `mariadb_postload.sql`)
- File format detection and analysis (`check_file_format.sh`)
- **Five-stage input file processing pipeline** (`stage1-5_*.py`):
  - Stage 1: SQL INSERT value extraction
  - Stage 2: Value sanitization and normalization
  - Stage 3: Column validation and filtering
  - Stage 4: TSV chunk generation and preparation
  - Stage 5: Pipeline orchestration
- Utility scripts for format conversion and processing
- Initial test suite development (92 unit tests + 28 integration tests)
- Configuration files and SQL scripts
- README and initial documentation
- Git repository setup and contributor history

### Claude Code (Anthropic)
**Enhancement, testing, documentation, and workflow improvements**
- Test suite optimization and condensation (reduced redundant unit tests)
- Integration test development for file format pipeline (13 new tests)
- Test framework improvements and utility functions
- Comprehensive documentation:
  - CLAUDE.md (project guidance for AI assistants)
  - agent_files/SESSION_HANDOFF.MD (session coordination)
  -agent_files/MULTI_AGENT_COORDINATION.md (multi-agent protocol guide)
  - .INIT_WORKFLOW_TEMPLATE.md (initialization template)
  - Documentation of Codex's work in CLAUDE.md
- Batch approval workflow implementation and documentation
- Git history cleanup (removed incorrect co-author tags)
- Multi-agent coordination framework
- File format pipeline integration testing and validation
- CONTRIBUTORS.md (accurate contributor attribution)

## Development Model

This project was developed collaboratively:
- **Codex**: Core functionality, pipeline architecture, primary implementation
- **Nate**: Requirements, architecture approval, final decision maker
- **Claude**: Testing refinement, documentation, workflow framework, multi-agent coordination

## Key Distinction

- **Codex's contributions**: The bulk_load system, file format handling, five-stage pipeline, core MariaDB optimization logic
- **Claude's contributions**: Testing improvements, comprehensive guidance documentation, batch approval workflow, multi-agent coordination, test validation

## Acknowledgments

Special thanks to:
- The MariaDB community for excellent documentation
- Open source contributors who inspired this dual-mode architecture
- Codex for the exceptional core implementation
- Nate for clear requirements and direction

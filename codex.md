# MariaDB Script Review Notes

## General
- The tooling assumes passwordless sudo/root access and SUPER-equivalent MariaDB privileges. Document the requirement and consider graceful fallbacks when privileges or utilities (e.g. `realpath`, `free`, `iostat`) are missing.
- Every script should allow multiple MySQL/MariaDB CLI options (`"$@"`) instead of a single positional argument so users can supply sockets, ports, etc.

## backup_current_config.sh
- `MYSQL_OPTS=${1:-"-u root -p"}` only respects the first argument (`lib/mariadb/backup_current_config.sh:18`). Accepting `"$@"` would allow callers to pass several flags.
- All `mysql` invocations silence STDERR (`2>/dev/null`), which hides the reason the script exits if credentials fail. Consider redirecting to a log instead so operators can see authentication/privilege errors quickly.

## bulk_load.sh
- The script changes many GLOBAL knobs (binlog, buffer sizes, IO capacity, etc.) but never snapshots original values. If the session aborts or the host has non-default tuning, you leave the instance in an unexpected state (`lib/mariadb/bulk_load.sh:52-123`, `lib/mariadb/bulk_load.sh:152-168`). Capture current values and restore them (ideally with a `trap`) instead of hard-coding “conservative” numbers.
- Disabling binary logging (`SET GLOBAL sql_log_bin = 0`) on a primary stops replication for other clients until the script finishes. Add strong warnings and/or scope the change to the session with `SET SESSION` (or use `LOCK BINLOG FOR ADMIN` / `@@persist_only`).
- SQL identifiers are interpolated without quoting (`USE $DATABASE;`, `ALTER TABLE $TABLE ...`, `LOAD DATA ... INTO TABLE $TABLE`). Names that contain special characters or user input can break or be exploited. Use `mysql --database` and wrap table names in backticks (`lib/mariadb/bulk_load.sh:66`, `lib/mariadb/bulk_load.sh:97`, `lib/mariadb/bulk_load.sh:120`).
- A user interrupt (Ctrl+C) between the “extreme” and “restore” blocks leaves the server in extreme mode. Add `trap 'restore_settings' EXIT` protection so the cleanup always runs.
- `realpath` is not guaranteed on macOS/BSD. Replace with `DATAFILE=$(cd "$(dirname "$DATAFILE")" && pwd)/$(basename "$DATAFILE")` or gate on availability.

## mariadb_status.sh
- The script ignores user-supplied CLI options: `MYSQL_OPTS` is parsed but `MYSQL_CMD` hard-codes `sudo mariadb -u root` (`lib/mariadb/mariadb_status.sh:19-20`). This fails where sudo password is required or root doesn’t have socket auth. Wire `MYSQL_CMD="mariadb $MYSQL_OPTS"` (and optionally `sudo` only when needed).
- Memory and CPU collectors assume GNU tools. If no `mysqld` process exists, `xargs printf` emits an error. Guard for empty results before formatting.
- `free -g` is Linux-specific; on macOS/containers you’ll hit `command not found`. Detect OS and fall back to `vm_stat` or `/proc/meminfo`.

## file_format_files/check_file_format.sh
- The “longest line” check pipes every line through `sort -n`, which is O(n log n) and slow on large datasets (`lib/mariadb/file_format_files/check_file_format.sh:195-199`). Use a single-pass `awk 'length>max{max=length} END{print max}'` instead.
- When no delimiter is detected the `awk` branch still runs with an empty `DELIM`, yielding unexpected results. Gate the inconsistency check on a non-empty delimiter constant.

## file_format_files/create_sample_files.sh
- `date -d ...` is GNU-specific. You do attempt a BSD fallback, but if both syntaxes fail you silently drop back to `2024-01-15`. Consider surfacing a warning so users know the dates are synthetic.

## Speed / Reliability Ideas
- Snapshot and restore MariaDB globals via `SHOW GLOBAL VARIABLES WHERE VARIABLE_NAME IN (...)` at the start of `bulk_load.sh`, then reapply them in a `trap` to make mode switches safer and quicker to roll back.
- Switch repeated `mysql` calls to use `mysql --batch --skip-column-names` plus a single query that returns all required settings to reduce connection overhead in monitoring scripts.
- For status reporting, reuse data from `performance_schema` (single query) instead of invoking multiple shell utilities (`ps`, `free`, `iostat`). This cuts execution time and reduces dependencies.
- Add lightweight config caches (e.g. write the captured “conservative” settings to `/var/tmp/mariadb_extreme_defaults.json`) so the restore step can reapply the exact pre-load values without re-querying each time.

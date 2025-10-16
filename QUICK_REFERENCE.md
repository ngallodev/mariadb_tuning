# MariaDB Dual-Mode Quick Reference

## Settings Comparison: Conservative vs Extreme Mode

| Setting | Conservative (Normal Ops) | Extreme (Bulk Load) | Impact |
|---------|--------------------------|---------------------|---------|
| **innodb_buffer_pool_size** | 64GB (25% RAM) | 64GB (same) | Baseline cache |
| **innodb_flush_log_at_trx_commit** | 1 (ACID) | 0 (every ~1s) | 10-20x faster writes |
| **innodb_adaptive_hash_index** | ON | OFF | Prevents interference |
| **innodb_io_capacity** | 200 | 2000 | 10x I/O throughput |
| **innodb_io_capacity_max** | 2000 | 4000 | Max burst I/O |
<!-- | **innodb_log_buffer_size** | 128MB | 256MB | 2x log buffer | -->
| **innodb_change_buffer_max_size** | 25% | 50% | 2x change buffering |
| **bulk_insert_buffer_size** | 64MB | 512MB | 8x insert buffer |
| **sort_buffer_size** | 4MB | 512MB | 128x sort performance |
| **read_buffer_size** | 2MB | 16MB | 8x read buffer |
| **read_rnd_buffer_size** | 4MB | 32MB | 8x random read |
| **join_buffer_size** | 4MB | 32MB | 8x join buffer |
| **foreign_key_checks** | ON | OFF | Skip FK validation |
| **unique_checks** | ON | OFF | Skip uniqueness checks |
| **sql_log_bin** | ON | OFF | No replication log |
| **autocommit** | ON | OFF | Batch transactions |

## Memory Usage Profile

### Conservative Mode (Normal Operations)
```
┌─────────────────────────────────────────────┐
│ Total RAM: 256GB                            │
├─────────────────────────────────────────────┤
│ MariaDB Buffer Pool:    64GB  (25%)         │
│ MariaDB Other:          10GB  (4%)          │
│ OS Cache:               20GB  (8%)          │
│ Available for Others:  162GB  (63%)         │
└─────────────────────────────────────────────┘
```

### Extreme Mode (During Bulk Loads)
```
┌─────────────────────────────────────────────┐
│ Total RAM: 256GB                            │
├─────────────────────────────────────────────┤
│ MariaDB Buffer Pool:    64GB  (25%)         │
│ MariaDB Session Buffers: 2GB  (1%)          │
│ MariaDB Other:          10GB  (4%)          │
│ OS Disk Cache:          50GB  (20%)         │
│ Available for Others:  130GB  (50%)         │
└─────────────────────────────────────────────┘
```

**Key Takeaway:** Even during extreme bulk loads, you still have 130GB+ free for other services!

## CPU Usage Profile

### Conservative Mode
- **MariaDB**: 1-2 cores (<10% of 28 cores)
- **Available**: 26-27 cores for other services

### Extreme Mode (Bulk Load)
- **MariaDB**: 2-8 cores (7-29% of 28 cores)
- **Available**: 20-26 cores for other services

## I/O Profile

### Conservative Mode
- **IOPS**: <200 typical
- **Throughput**: <50 MB/s
- **Pattern**: Random reads/writes

### Extreme Mode (Bulk Load)
- **IOPS**: 1000-4000 burst
- **Throughput**: 200-1000 MB/s
- **Pattern**: Sequential writes

## When Each Mode is Active

### Conservative Mode
- ✅ Normal database queries
- ✅ Web application traffic
- ✅ Scheduled backups
- ✅ Overnight (when not loading)
- ✅ 99% of the time

### Extreme Mode
- ⚡ Active during `bulk_load.sh` execution
- ⚡ When `mariadb_preload.sql` has been run (manual mode)
- ⚡ Automatically restored after load completes
- ⚡ ~1% of the time (during scheduled bulk loads)

## Safety Features

### What's Temporarily Disabled in Extreme Mode
1. **Foreign Key Checks** - FK relationships not validated during insert
2. **Unique Checks** - Uniqueness not validated during insert  
3. **Binary Logging** - No replication log written
4. **Autocommit** - Changes batched into single transaction
5. **Adaptive Hash Index** - AHI disabled to prevent contention

### What Remains Protected
1. ✅ **Data Durability** - Data still written to disk (just less frequently)
2. ✅ **InnoDB Crash Recovery** - Can recover from crashes
3. ✅ **ACID Properties** - Maintained at transaction level (commits every ~1s)
4. ✅ **Table Locks** - Still prevent concurrent modifications
5. ✅ **Data Integrity** - Data itself is not corrupted

### When to NOT Use Extreme Mode
- ❌ When replication slaves need to be synchronized
- ❌ When loading data that must be immediately backed up
- ❌ When other transactions need to access the same tables
- ❌ When foreign key relationships MUST be validated during load
- ❌ When duplicates are expected and must be rejected during load

## Command Reference

### Check Current Mode
```sql
-- Conservative mode should show:
SHOW VARIABLES WHERE Variable_name IN (
  'innodb_flush_log_at_trx_commit',  -- Should be 1
  'innodb_adaptive_hash_index',       -- Should be ON
  'innodb_io_capacity'                -- Should be 200
);
```

### Manually Switch to Extreme Mode
```bash
mysql -u root -p < mariadb_preload.sql
# Perform your data operations
mysql -u root -p < mariadb_postload.sql
```

### Automated Mode Switching
```bash
# The bulk_load.sh script handles everything:
./bulk_load.sh database table datafile.txt
# Automatically: Conservative → Extreme → Load → Conservative
```

## Performance Expectations

### Load Speed Estimates

**Small rows (<100 bytes):**
- Conservative: 10,000-50,000 rows/sec
- Extreme: 100,000-500,000 rows/sec
- **Speedup: 10-50x**

**Medium rows (100-500 bytes):**
- Conservative: 5,000-20,000 rows/sec  
- Extreme: 50,000-200,000 rows/sec
- **Speedup: 10-20x**

**Large rows (>500 bytes):**
- Conservative: 2,000-10,000 rows/sec
- Extreme: 20,000-100,000 rows/sec  
- **Speedup: 10-20x**

### Real-World Example

**Loading 10 million rows of 200-byte records:**
- File size: ~2GB
- Conservative mode: 40-60 minutes
- Extreme mode: 2-5 minutes
- **Time saved: 35-58 minutes per load!**

## Best Practices

1. **Schedule bulk loads during off-peak hours** when other services have lower demand
2. **Monitor resource usage** during first few loads to understand your patterns
3. **Use the automated script** (`bulk_load.sh`) to prevent forgetting to restore settings
4. **Pre-sort data** by primary key order for additional 20-30% speed boost
5. **Drop and recreate indexes** for very large loads (empty tables)
6. **Load in parallel** if you have multiple independent tables to load

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| Load is slow | Still in conservative mode | Check `innodb_flush_log_at_trx_commit` = 0 |
| Out of memory | Other services using RAM | Reduce other services or lower buffer pool |
| High swap usage | Too much memory allocated | Check `free -h`, reduce buffer pool if needed |
| Disk I/O at 100% | Storage bottleneck | Upgrade to SSD or add striped volumes |
| CPU at 100% | Normal for extreme mode | Ensure load runs during off-peak hours |
| Load hangs | Table locks | Check for other connections: `SHOW PROCESSLIST;` |
| Error on restore | Missing privileges | Ensure SUPER privilege: `GRANT SUPER ON *.* TO user;` |

## Additional Tips

### For SSDs (which you likely have)
The configuration already optimizes for SSDs with:
- `innodb_flush_neighbors = 0` (no need to flush adjacent pages)
- `innodb_use_native_aio = 1` (async I/O)
- `O_DIRECT` flush method (bypass OS cache)

### For HDDs (if applicable)
Change in config file:
```ini
innodb_flush_neighbors = 1  # Flush adjacent pages
innodb_io_capacity = 100    # Lower for HDD
innodb_io_capacity_max = 2000
```

### For Even More Extreme Performance (Use with Caution)
```sql
-- Add to preload script for ultimate speed (at risk of data loss):
SET GLOBAL innodb_flush_log_at_trx_commit = 2;  -- OS cache only, no fsync
SET GLOBAL sync_binlog = 0;  -- Don't sync binary log at all
SET GLOBAL innodb_doublewrite = 0;  -- Disable doublewrite buffer (risky!)
```

**Warning:** These settings risk data loss on server crash. Only use for non-critical bulk loads that can be re-run.

# MariaDB Bulk Load Optimization Scripts

Complete set of scripts and configuration for optimizing MariaDB bulk data loads on high-performance multi-role servers.

## 🎯 Dual-Mode Resource Strategy

This configuration uses a **smart dual-mode approach** for resource management:

### Conservative Mode (Normal Operations)
- **InnoDB Buffer Pool**: 64GB (~25% of RAM)
- **Connections**: 200 max connections
- **Memory Usage**: ~70-80GB total
- **Purpose**: Leaves plenty of resources for other server roles

### Extreme Mode (During Bulk Loads)
- **Session Buffers**: 512MB-1GB per connection
- **Global I/O**: Maximized (2000-4000 IOPS capacity)
- **Flush Mode**: Disabled for maximum speed (commits every ~1 second)
- **Checks**: All safety checks disabled
- **Purpose**: Achieves 50,000-500,000+ rows/second load speeds

**The scripts automatically switch between modes**, so you get:
- ✅ Low resource usage during normal operations
- ✅ Extreme performance during data loads
- ✅ Automatic restoration to conservative mode after loads

## Server Specifications
- **RAM**: 256GB DDR4 ECC
- **CPUs**: 2x Xeon 14-core (28 cores total)
- **OS**: Debian
- **Role**: Multi-role server (not dedicated database server)

## Files Included

1. **mariadb_preload.sql** - SQL script to run before data loads (enables extreme mode)
2. **mariadb_postload.sql** - SQL script to run after data loads (restores conservative mode)
3. **mariadb_performance.cnf** - Optimized MariaDB configuration file (conservative baseline)
4. **bulk_load.sh** - Automated bash script for bulk loading with automatic mode switching
5. **mariadb_status.sh** - Real-time monitoring script to check current mode and resource usage
6. **QUICK_REFERENCE.md** - Side-by-side comparison of conservative vs extreme modes
7. **file_format_files/fix_flat_csv.py** - Repairs flattened CSV exports that are missing line endings
8. **file_format_files/convert_csv_to_tab.py** - Converts standard CSV (double-quoted) to TSV while preserving commas
9. **schema/create_fling_body_table.sql** - Starter table definition for the fling_body dataset

## Quick Start

### Option 1: Using the Automated Script (Recommended)

```bash
# Make script executable (already done)
chmod +x bulk_load.sh

# Load data
./bulk_load.sh mydb mytable /path/to/data.txt "-u root -pYourPassword"

# Or for interactive password prompt
./bulk_load.sh mydb mytable /path/to/data.txt
```

### Option 2: Manual SQL Scripts

```bash
# Before loading
mysql -u root -p < mariadb_preload.sql

# Load your data
mysql -u root -p mydb -e "LOAD DATA LOCAL INFILE '/path/to/data.txt' \
  INTO TABLE mytable \
  FIELDS TERMINATED BY '\t' \
  LINES TERMINATED BY '\n';"

# After loading
mysql -u root -p < mariadb_postload.sql

# Analyze table
mysql -u root -p mydb -e "ANALYZE TABLE mytable;"
```

## Monitoring Current Mode & Resources

Use the status script to check if MariaDB is in conservative or extreme mode:

```bash
# Check current status
chmod +x mariadb_status.sh
./mariadb_status.sh

# Or with custom credentials
./mariadb_status.sh "-u root -pYourPassword"

# Watch in real-time (updates every 2 seconds)
watch -n 2 './mariadb_status.sh "-u root -p"'
```

The status script shows:
- ✅ Current mode (Conservative vs Extreme)
- 📊 Memory usage (total, available, MariaDB)
- 💻 CPU usage and load average
- 💾 Disk I/O statistics
- 🔌 Active connections
- 📈 Buffer pool status
- 💡 Recommendations based on current state

## Installation & Configuration

### 1. Install MariaDB Configuration

```bash
# Backup existing configuration
sudo cp /etc/mysql/my.cnf /etc/mysql/my.cnf.backup

# Copy the performance configuration
sudo cp mariadb_performance.cnf /etc/mysql/mariadb.conf.d/99-performance.cnf

# Or manually add to /etc/mysql/my.cnf

# Restart MariaDB
sudo systemctl restart mariadb

# Verify settings
mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
```

### 2. Verify Configuration

```bash
# Check buffer pool size (should be ~64GB)
mysql -u root -p -e "SELECT @@innodb_buffer_pool_size/1024/1024/1024 AS 'Buffer Pool GB';"

# Check other key settings
mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb%';"
```

### 3. Enable Local Data Loading

Ensure your MariaDB allows LOAD DATA LOCAL INFILE:

```bash
# In MariaDB configuration (already in mariadb_performance.cnf)
local_infile = 1

# When connecting with mysql client
mysql --local-infile -u root -p
```

## Key Optimization Techniques

### Pre-Load Optimizations
- **Disable binary logging**: Eliminates replication overhead
- **Disable foreign key checks**: Skips FK validation during load
- **Disable unique checks**: Skips uniqueness validation during load
- **Disable autocommit**: Batches inserts in single transaction
- **Increase buffer sizes**: Uses more memory for faster processing

### Configuration Highlights

**Conservative Baseline (Normal Operations):**
- **InnoDB Buffer Pool**: 64GB (25% of RAM) - leaves 192GB for other services
- **Buffer Pool Instances**: 48 instances for parallelism
- **Log Files**: 2GB each for moderate write performance
- **I/O Threads**: 8 read + 8 write threads
- **Connections**: 200 max connections
- **Total Memory**: ~70-80GB typical usage

**Extreme Mode (Activated During Loads):**
- **Session Buffers**: 512MB-1GB per operation
- **Flush Mode**: `innodb_flush_log_at_trx_commit=0` (fastest, ~1 sec commits)
- **I/O Capacity**: 2000-4000 IOPS
- **Adaptive Hash**: Disabled (prevents interference)
- **Safety Checks**: All disabled (FK, unique, binary log)
- **Result**: 10-20x faster bulk loading

### Post-Load Optimizations
- **ANALYZE TABLE**: Updates table statistics for query optimizer
- **Enable keys**: Re-enables indexes (MyISAM only)
- **Restore settings**: Returns to normal operational mode

## Performance Tips

### For Maximum Load Speed:

1. **Drop indexes before loading** (if table is empty):
```sql
ALTER TABLE mytable DROP INDEX index_name;
-- Load data
ALTER TABLE mytable ADD INDEX index_name (column_name);
```

2. **Disable binary logging entirely** during bulk loads:
```bash
# Stop MariaDB
sudo systemctl stop mariadb

# Edit my.cnf and comment out log_bin
# skip-log-bin

# Start MariaDB
sudo systemctl start mariadb
```

3. **Use InnoDB tables** (faster than MyISAM for bulk loads)

4. **Pre-sort data** in the text file to match primary key order

5. **Use multiple parallel loads** for very large datasets:
```bash
# Split file
split -l 1000000 data.txt data_chunk_

# Load in parallel
for f in data_chunk_*; do
  ./bulk_load.sh mydb mytable "$f" &
done
wait
```

6. **Increase file system cache**:
```bash
# Temporarily
sudo sysctl -w vm.dirty_ratio=80
sudo sysctl -w vm.dirty_background_ratio=50

# Restore after load
sudo sysctl -w vm.dirty_ratio=20
sudo sysctl -w vm.dirty_background_ratio=10
```

### For Different Data Formats:

**CSV files (comma-separated)**:
```sql
LOAD DATA LOCAL INFILE '/path/to/data.csv'
INTO TABLE mytable
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;  -- Skip header
```

**Tab-delimited (default)**:
```sql
LOAD DATA LOCAL INFILE '/path/to/data.txt'
INTO TABLE mytable
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n';
```

**Custom delimiters**:
```sql
LOAD DATA LOCAL INFILE '/path/to/data.txt'
INTO TABLE mytable
FIELDS TERMINATED BY '|'
LINES TERMINATED BY '\r\n';
```

## Monitoring Performance

### Check InnoDB Status:
```sql
SHOW ENGINE INNODB STATUS\G
```

### Monitor Buffer Pool Usage:
```sql
SELECT 
  POOL_ID,
  POOL_SIZE,
  FREE_BUFFERS,
  DATABASE_PAGES,
  OLD_DATABASE_PAGES,
  MODIFIED_DATABASE_PAGES,
  PENDING_READS,
  PENDING_WRITES
FROM information_schema.INNODB_BUFFER_POOL_STATS;
```

### Check Table Size:
```sql
SELECT 
  table_name,
  ROUND((data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'Size (GB)',
  table_rows
FROM information_schema.TABLES
WHERE table_schema = 'your_database'
ORDER BY (data_length + index_length) DESC;
```

## Resource Usage Monitoring

### Monitor System Resources During Loads

**Watch memory usage:**
```bash
# Real-time memory monitoring
watch -n 1 'free -h && echo "" && ps aux | grep mysql | grep -v grep'

# Check MariaDB memory usage
ps aux | grep mysqld | awk '{print $6/1024 " MB"}'
```

**Monitor disk I/O:**
```bash
# Install if needed: sudo apt install sysstat
iostat -x 5
```

**Check CPU usage:**
```bash
# Real-time CPU monitoring
htop -p $(pgrep -d',' mysqld)

# Or use top
top -p $(pgrep mysqld)
```

### Expected Resource Usage

**During Normal Operations (Conservative Mode):**
- Memory: ~70-80GB (MariaDB process)
- CPU: <10% average
- I/O: Minimal, <100 IOPS typically

**During Bulk Loads (Extreme Mode):**
- Memory: ~80-100GB (MariaDB + OS cache)
- CPU: 200-800% (2-8 cores active)
- I/O: 1000-4000 IOPS
- Network: Depends on data source

**Available for Other Services:**
- Memory: ~156-186GB free during normal ops
- Memory: ~126-156GB free during bulk loads
- CPU: 20-26 cores always available for other services

### Verify Mode Status

**Check current flush mode:**
```sql
-- Should be 1 (ACID) during normal operations
-- Should be 0 during bulk loads
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';
```

**Check adaptive hash status:**
```sql
-- Should be ON during normal operations
-- Should be OFF during bulk loads
SHOW VARIABLES LIKE 'innodb_adaptive_hash_index';
```

**Check I/O capacity:**
```sql
-- Should be 200 during normal operations
-- Should be 2000 during bulk loads
SHOW VARIABLES LIKE 'innodb_io_capacity%';
```

## Troubleshooting

### Error: "The used command is not allowed with this MariaDB version"
```bash
# Solution: Enable local_infile in config and use --local-infile flag
mysql --local-infile -u root -p
```

### Error: "MySQL server has gone away"
```bash
# Solution: Increase max_allowed_packet
mysql -u root -p -e "SET GLOBAL max_allowed_packet=1073741824;"
```

### Slow performance during load
- Check disk I/O: `iostat -x 5`
- Check CPU usage: `top`
- Verify buffer pool size: Should be 64GB for conservative mode
- Check for swap usage: `free -h` (swap should be minimal)
- Verify extreme mode is active: Check `innodb_flush_log_at_trx_commit` should be 0

### Out of memory errors
```bash
# Already conservative at 64GB, but can reduce further if needed
# Edit mariadb_performance.cnf
innodb_buffer_pool_size = 48G  # Instead of 64G

# Restart MariaDB
sudo systemctl restart mariadb
```

**Note:** With 256GB RAM on a multi-role server, memory issues are unlikely unless other services are using excessive resources.

## Production Considerations

After bulk loading is complete, consider:

1. **Re-enable binary logging** for replication/backup
2. **Set innodb_flush_log_at_trx_commit = 1** for ACID compliance
3. **Enable performance_schema** for monitoring
4. **Run OPTIMIZE TABLE** to reclaim space and defragment
5. **Update statistics**: `ANALYZE TABLE tablename;`
6. **Test query performance** and add indexes as needed

## Benchmarking

To measure load performance:

```bash
# Time a load operation
time ./bulk_load.sh mydb mytable data.txt

# Or manually
time mysql --local-infile -u root -p mydb -e "LOAD DATA LOCAL INFILE 'data.txt' INTO TABLE mytable;"
```

Expected performance on your hardware:
- **Small datasets** (<1GB): 100,000 - 500,000 rows/second
- **Medium datasets** (1-10GB): 50,000 - 200,000 rows/second
- **Large datasets** (>10GB): 20,000 - 100,000 rows/second

Actual performance depends on:
- Row size
- Number of indexes
- Data complexity
- Disk I/O speed
- Data pre-sorting

## Additional Resources

- MariaDB Optimization Guide: https://mariadb.com/kb/en/optimization-and-tuning/
- InnoDB Tuning: https://mariadb.com/kb/en/innodb-system-variables/
- LOAD DATA: https://mariadb.com/kb/en/load-data-infile/

## Support

For issues or questions:
1. Check MariaDB error log: `/var/log/mysql/error.log`
2. Review slow query log if enabled
3. Monitor system resources: `htop`, `iostat`, `free -h`
4. Check MariaDB status: `systemctl status mariadb`

## Contributors

This project was developed using AI-assisted development:

- **Nate Gallo** ([@ngallodev](https://github.com/ngallodev)) - Project creator and maintainer
- **Claude Code** (Anthropic) - Primary development, test suite, and documentation

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for detailed contribution breakdown.

---

**Note**: Always test these configurations on non-production data first. Backup your database before making configuration changes.

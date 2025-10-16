# Safe Installation Process

## Step-by-Step: Backup Current Config, Install New, Restore if Needed

### Step 1: Backup Your Current Configuration

```bash
# Make script executable
chmod +x backup_current_config.sh

# Run backup (will prompt for password)
./backup_current_config.sh

# Or with password inline (less secure but convenient)
./backup_current_config.sh "-u root -pYourPassword"
```

**This creates a timestamped backup directory with:**
- ✓ All config files (my.cnf, mariadb.conf.d/)
- ✓ All global variables
- ✓ InnoDB settings
- ✓ Current status
- ✓ Restoration script

### Step 2: Review Your Backup

```bash
# View the backup summary
cat mariadb_backup_*/BACKUP_SUMMARY.txt

# See your current key settings
grep "innodb_buffer_pool_size\|max_connections\|innodb_flush" mariadb_backup_*/BACKUP_SUMMARY.txt
```

### Step 3: Install New Configuration

```bash
# Backup the current config one more time (just to be safe)
sudo cp /etc/mysql/my.cnf /etc/mysql/my.cnf.original

# Install the new configuration
sudo cp mariadb_performance.cnf /etc/mysql/mariadb.conf.d/99-performance.cnf

# Verify the file is in place
ls -lh /etc/mysql/mariadb.conf.d/99-performance.cnf

# Restart MariaDB to apply changes
sudo systemctl restart mariadb

# Check that MariaDB started successfully
sudo systemctl status mariadb
```

### Step 4: Verify New Settings

```bash
# Check the new settings
./mariadb_status.sh

# Or check specific settings
mysql -u root -p -e "SELECT @@innodb_buffer_pool_size/1024/1024/1024 AS 'Buffer Pool GB';"
mysql -u root -p -e "SELECT @@max_connections;"
mysql -u root -p -e "SELECT @@innodb_flush_log_at_trx_commit;"
```

**Expected values with new config:**
- Buffer Pool: 64 GB (conservative mode)
- Max Connections: 200
- Flush Log: 1 (ACID compliant)

### Step 5: Test Bulk Loading (Optional)

```bash
# Test with a small file first
./bulk_load.sh test_db test_table small_test_file.txt

# Monitor during the test
./mariadb_status.sh
```

## If Something Goes Wrong: Restoration Options

### Option 1: Restore Configuration Files (Requires Restart)

```bash
# Find your backup directory
ls -ld mariadb_backup_*

# Restore the original config files
cd mariadb_backup_YYYYMMDD_HHMMSS
sudo cp my.cnf.backup /etc/mysql/my.cnf
sudo cp -r mariadb.conf.d.backup/* /etc/mysql/mariadb.conf.d/

# Remove the new config if needed
sudo rm /etc/mysql/mariadb.conf.d/99-performance.cnf

# Restart MariaDB
sudo systemctl restart mariadb
```

### Option 2: Restore Runtime Settings (No Restart for Some)

```bash
# Use the generated restoration script
cd mariadb_backup_YYYYMMDD_HHMMSS
mysql -u root -p < restore_settings.sql
```

**Note:** Some settings like buffer_pool_size still require a restart

### Option 3: Remove Only the New Config

```bash
# Remove just the new performance config
sudo rm /etc/mysql/mariadb.conf.d/99-performance.cnf

# Restart to revert to previous settings
sudo systemctl restart mariadb
```

## Quick Commands Reference

```bash
# Backup current config
./backup_current_config.sh

# Install new config
sudo cp mariadb_performance.cnf /etc/mysql/mariadb.conf.d/99-performance.cnf
sudo systemctl restart mariadb

# Check status
./mariadb_status.sh

# Run bulk load
./bulk_load.sh database table datafile.txt

# Restore if needed
cd mariadb_backup_YYYYMMDD_HHMMSS
sudo cp my.cnf.backup /etc/mysql/my.cnf
sudo systemctl restart mariadb
```

## Troubleshooting

### MariaDB won't start after config change

```bash
# Check the error log
sudo tail -50 /var/log/mysql/error.log

# Common issues:
# 1. Syntax error in config file - check line numbers in error log
# 2. Invalid setting value - review error message
# 3. Insufficient permissions - ensure files are owned by mysql:mysql

# Quick fix: Remove new config and restart
sudo rm /etc/mysql/mariadb.conf.d/99-performance.cnf
sudo systemctl restart mariadb
```

### Settings not taking effect

```bash
# Verify which config file is being used
mysql -u root -p -e "SELECT @@basedir, @@datadir;"

# Check if your config file is being read
sudo mysqld --verbose --help | grep -A 1 "Default options"

# Some settings require restart (buffer pool size, log file size)
sudo systemctl restart mariadb
```

### Want to temporarily disable new config without deleting it

```bash
# Rename the config file
sudo mv /etc/mysql/mariadb.conf.d/99-performance.cnf /etc/mysql/mariadb.conf.d/99-performance.cnf.disabled
sudo systemctl restart mariadb

# Re-enable later
sudo mv /etc/mysql/mariadb.conf.d/99-performance.cnf.disabled /etc/mysql/mariadb.conf.d/99-performance.cnf
sudo systemctl restart mariadb
```

## Safety Checklist

Before making changes:
- [ ] Backup completed: `./backup_current_config.sh`
- [ ] Backup verified: `cat mariadb_backup_*/BACKUP_SUMMARY.txt`
- [ ] Non-peak hours: Check if safe time for restart
- [ ] Other services noted: Know what else is running
- [ ] Testing plan ready: Have small test data file

After making changes:
- [ ] MariaDB started: `sudo systemctl status mariadb`
- [ ] Settings verified: `./mariadb_status.sh`
- [ ] Connections work: `mysql -u root -p -e "SELECT 1;"`
- [ ] Test bulk load: Small file first
- [ ] Monitor resources: Watch memory/CPU during test

## Best Practices

1. **Always backup first** - The backup script is there for a reason!
2. **Change during off-peak** - Restart causes brief downtime
3. **Test with small data** - Before loading huge files
4. **Monitor the first load** - Use `./mariadb_status.sh` to watch
5. **Keep backups** - Don't delete old backups immediately
6. **Document changes** - Note when and why changes were made

Your backup is timestamped and saved, so you can always revert! 🔒

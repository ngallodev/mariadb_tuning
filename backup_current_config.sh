#!/bin/bash
#
# MariaDB Configuration Backup Script
# Captures all current settings before making changes
#
# Usage: ./backup_current_config.sh [mysql_options]
# Example: ./backup_current_config.sh "-u root -p"
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MYSQL_OPTS=${1:-"-u root -p"}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="mariadb_backup_${TIMESTAMP}"

echo -e "${CYAN}MariaDB Configuration Backup Script${NC}"
echo -e "${CYAN}====================================${NC}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}Created backup directory: $BACKUP_DIR${NC}"
echo ""

# 1. Backup configuration files
echo -e "${YELLOW}[1/5] Backing up configuration files...${NC}"

if [ -f /etc/mysql/my.cnf ]; then
    sudo cp /etc/mysql/my.cnf "$BACKUP_DIR/my.cnf.backup"
    echo "  ✓ Backed up /etc/mysql/my.cnf"
fi

if [ -d /etc/mysql/mariadb.conf.d ]; then
    sudo cp -r /etc/mysql/mariadb.conf.d "$BACKUP_DIR/mariadb.conf.d.backup"
    echo "  ✓ Backed up /etc/mysql/mariadb.conf.d/"
fi

if [ -d /etc/mysql/conf.d ]; then
    sudo cp -r /etc/mysql/conf.d "$BACKUP_DIR/conf.d.backup"
    echo "  ✓ Backed up /etc/mysql/conf.d/"
fi

echo ""

# 2. Capture all GLOBAL variables
echo -e "${YELLOW}[2/5] Capturing GLOBAL variables...${NC}"
mysql $MYSQL_OPTS -e "SHOW GLOBAL VARIABLES;" > "$BACKUP_DIR/global_variables.txt" 2>/dev/null
echo "  ✓ Saved to global_variables.txt ($(wc -l < "$BACKUP_DIR/global_variables.txt") variables)"
echo ""

# 3. Capture InnoDB-specific settings
echo -e "${YELLOW}[3/5] Capturing InnoDB settings...${NC}"
mysql $MYSQL_OPTS -e "SHOW VARIABLES LIKE 'innodb%';" > "$BACKUP_DIR/innodb_variables.txt" 2>/dev/null
echo "  ✓ Saved to innodb_variables.txt"
echo ""

# 4. Capture current status
echo -e "${YELLOW}[4/5] Capturing server status...${NC}"
mysql $MYSQL_OPTS -e "SHOW GLOBAL STATUS;" > "$BACKUP_DIR/global_status.txt" 2>/dev/null
echo "  ✓ Saved to global_status.txt"

mysql $MYSQL_OPTS -e "SHOW ENGINE INNODB STATUS\G" > "$BACKUP_DIR/innodb_status.txt" 2>/dev/null
echo "  ✓ Saved to innodb_status.txt"
echo ""

# 5. Create restoration SQL script
echo -e "${YELLOW}[5/5] Creating restoration script...${NC}"

cat > "$BACKUP_DIR/restore_settings.sql" << 'EOF'
-- MariaDB Settings Restoration Script
-- Generated from backup
-- 
-- IMPORTANT: Review this file before executing!
-- Some settings cannot be changed without restart (marked with -- RESTART REQUIRED)
-- 
-- Usage: mysql -u root -p < restore_settings.sql

-- Key settings captured at backup time:

EOF

# Add key InnoDB settings to restoration script
mysql $MYSQL_OPTS -sN -e "
SELECT CONCAT('-- ', VARIABLE_NAME, ' = ', VARIABLE_VALUE, 
              IF(VARIABLE_NAME IN ('innodb_buffer_pool_size', 'innodb_buffer_pool_instances', 
                                     'innodb_log_file_size', 'innodb_log_files_in_group'),
                 ' -- RESTART REQUIRED', ''))
FROM information_schema.GLOBAL_VARIABLES 
WHERE VARIABLE_NAME IN (
    'innodb_buffer_pool_size',
    'innodb_buffer_pool_instances',
    'innodb_log_file_size',
    'innodb_log_buffer_size',
    'innodb_flush_log_at_trx_commit',
    'innodb_flush_method',
    'innodb_io_capacity',
    'innodb_io_capacity_max',
    'innodb_read_io_threads',
    'innodb_write_io_threads',
    'max_connections',
    'max_allowed_packet',
    'table_open_cache',
    'tmp_table_size',
    'max_heap_table_size'
)
ORDER BY VARIABLE_NAME;
" 2>/dev/null >> "$BACKUP_DIR/restore_settings.sql"

# Add runtime-changeable settings
cat >> "$BACKUP_DIR/restore_settings.sql" << 'EOF'

-- Settings that can be changed at runtime (without restart):

EOF

mysql $MYSQL_OPTS -sN -e "
SELECT CONCAT('SET GLOBAL ', VARIABLE_NAME, ' = ', 
              IF(VARIABLE_VALUE REGEXP '^[0-9]+$', VARIABLE_VALUE, 
                 CONCAT('''', VARIABLE_VALUE, '''')), ';')
FROM information_schema.GLOBAL_VARIABLES 
WHERE VARIABLE_NAME IN (
    'innodb_flush_log_at_trx_commit',
    'innodb_io_capacity',
    'innodb_io_capacity_max',
    'innodb_adaptive_hash_index',
    'max_allowed_packet',
    'innodb_log_buffer_size'
)
ORDER BY VARIABLE_NAME;
" 2>/dev/null >> "$BACKUP_DIR/restore_settings.sql"

echo "  ✓ Created restore_settings.sql"
echo ""

# Create a summary report
cat > "$BACKUP_DIR/BACKUP_SUMMARY.txt" << EOF
MariaDB Configuration Backup Summary
====================================
Backup Date: $(date)
Backup Directory: $BACKUP_DIR

Files Included:
---------------
1. Configuration Files:
   - my.cnf.backup                  (Main config file)
   - mariadb.conf.d.backup/         (Config directory)
   - conf.d.backup/                 (Additional configs)

2. Runtime Settings:
   - global_variables.txt           (All global variables)
   - innodb_variables.txt           (InnoDB-specific settings)
   - global_status.txt              (Server status)
   - innodb_status.txt              (InnoDB engine status)

3. Restoration:
   - restore_settings.sql           (SQL script to restore runtime settings)

Key Current Settings:
--------------------
EOF

# Add key settings to summary
mysql $MYSQL_OPTS -sN -e "
SELECT CONCAT(VARIABLE_NAME, ': ', 
              CASE 
                WHEN VARIABLE_NAME LIKE '%size' AND VARIABLE_VALUE > 1024*1024 
                  THEN CONCAT(ROUND(VARIABLE_VALUE/1024/1024/1024, 2), ' GB')
                WHEN VARIABLE_NAME LIKE '%size' AND VARIABLE_VALUE > 1024 
                  THEN CONCAT(ROUND(VARIABLE_VALUE/1024/1024, 2), ' MB')
                ELSE VARIABLE_VALUE
              END)
FROM information_schema.GLOBAL_VARIABLES 
WHERE VARIABLE_NAME IN (
    'innodb_buffer_pool_size',
    'innodb_buffer_pool_instances',
    'innodb_log_file_size',
    'innodb_flush_log_at_trx_commit',
    'max_connections',
    'innodb_io_capacity',
    'innodb_read_io_threads',
    'innodb_write_io_threads'
)
ORDER BY VARIABLE_NAME;
" 2>/dev/null >> "$BACKUP_DIR/BACKUP_SUMMARY.txt"

cat >> "$BACKUP_DIR/BACKUP_SUMMARY.txt" << EOF

How to Restore:
---------------
1. To restore configuration files:
   sudo cp $BACKUP_DIR/my.cnf.backup /etc/mysql/my.cnf
   sudo cp -r $BACKUP_DIR/mariadb.conf.d.backup/* /etc/mysql/mariadb.conf.d/
   sudo systemctl restart mariadb

2. To restore runtime settings (no restart needed for some):
   mysql -u root -p < $BACKUP_DIR/restore_settings.sql

3. Settings requiring restart are marked in restore_settings.sql

IMPORTANT:
----------
- Review restore_settings.sql before executing
- Some settings require MariaDB restart to take effect
- Buffer pool size changes require restart and can take time
- Keep this backup in a safe location

EOF

echo "  ✓ Created BACKUP_SUMMARY.txt"
echo ""

# Display summary
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Backup Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "Backup saved to: ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo "Contents:"
echo "  • Configuration files (my.cnf, mariadb.conf.d/)"
echo "  • All global variables and status"
echo "  • InnoDB-specific settings"
echo "  • Restoration SQL script"
echo "  • Summary report"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review: cat $BACKUP_DIR/BACKUP_SUMMARY.txt"
echo "  2. Keep this backup safe before making changes"
echo "  3. To restore later: mysql -u root -p < $BACKUP_DIR/restore_settings.sql"
echo ""

# Set permissions
chmod 600 "$BACKUP_DIR"/*.txt "$BACKUP_DIR"/*.sql 2>/dev/null || true
echo -e "${GREEN}✓ Backup files secured (chmod 600)${NC}"
echo ""

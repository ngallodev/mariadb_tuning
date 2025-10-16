-- MariaDB Post-Load Restoration Script
-- Run this after bulk loading data from text files
-- This restores settings to conservative mode for normal operations
-- Usage: mysql -u root -p < mariadb_postload.sql

-- =====================================================
-- SESSION SETTINGS RESTORATION
-- =====================================================

-- Commit any pending transactions
COMMIT;

-- Re-enable autocommit
SET SESSION autocommit = 1;

-- Re-enable unique key checks
SET SESSION unique_checks = 1;

-- Re-enable foreign key checks
SET SESSION foreign_key_checks = 1;

-- Re-enable binary logging
SET SESSION sql_log_bin = 1;

-- Restore default buffer sizes (optional, session will reset anyway)
SET SESSION bulk_insert_buffer_size = DEFAULT;
SET SESSION sort_buffer_size = DEFAULT;
SET SESSION read_buffer_size = DEFAULT;
SET SESSION read_rnd_buffer_size = DEFAULT;
SET SESSION join_buffer_size = DEFAULT;

-- =====================================================
-- GLOBAL SETTINGS RESTORATION (back to conservative)
-- =====================================================

-- Note: sql_log_bin is SESSION-only, cannot be set globally
-- It will be re-enabled automatically when sessions reconnect

-- Restore flush settings for ACID compliance
SET GLOBAL innodb_flush_log_at_trx_commit = 1; -- Full ACID compliance

-- Restore flush neighbors (can help on HDD, not needed on SSD)
SET GLOBAL innodb_flush_neighbors = 0;

-- Restore log buffer to moderate size
SET GLOBAL innodb_log_buffer_size = 128 * 1024 * 1024; -- 128MB

-- Re-enable adaptive hash index
SET GLOBAL innodb_adaptive_hash_index = ON;

-- Restore change buffer to default
SET GLOBAL innodb_change_buffer_max_size = 25; -- 25% default

-- Restore I/O capacity to normal levels
SET GLOBAL innodb_io_capacity = 200;
SET GLOBAL innodb_io_capacity_max = 2000;

-- Restore max packet to moderate size
SET GLOBAL max_allowed_packet = 64 * 1024 * 1024; -- 64MB

-- Show current settings
SELECT '========================================' AS ' ';
SELECT 'Settings restored to CONSERVATIVE mode' AS Status;
SELECT '========================================' AS ' ';
SELECT 'Global Settings Restored:' AS ' ';
SELECT '  - innodb_flush_log_at_trx_commit = 1 (ACID)' AS ' ';
SELECT '  - innodb_adaptive_hash_index = ON' AS ' ';
SELECT '  - innodb_io_capacity restored to normal' AS ' ';
SELECT '  - max_allowed_packet = 64MB' AS ' ';
SELECT '' AS ' ';
SELECT 'Session Settings:' AS ' ';
SELECT CONCAT('  - Foreign keys: ', IF(@@SESSION.foreign_key_checks=1, 'ENABLED', 'disabled')) AS ' ';
SELECT CONCAT('  - Unique checks: ', IF(@@SESSION.unique_checks=1, 'ENABLED', 'disabled')) AS ' ';
SELECT CONCAT('  - Autocommit: ', IF(@@SESSION.autocommit=1, 'ENABLED', 'disabled')) AS ' ';
SELECT '========================================' AS ' ';

SELECT '' AS ' ';
SELECT '========================================' AS ' ';
SELECT 'IMPORTANT: Run ANALYZE TABLE' AS ' ';
SELECT '========================================' AS ' ';
SELECT 'After loading, you should run ANALYZE TABLE' AS ' ';
SELECT 'to update statistics for the query optimizer:' AS ' ';
SELECT '' AS ' ';
SELECT '  USE your_database;' AS ' ';
SELECT '  ANALYZE TABLE your_table;' AS ' ';
SELECT '' AS ' ';
SELECT 'Or to analyze all tables in a database:' AS ' ';
SELECT '  mysqlcheck -u root -p --analyze your_database' AS ' ';
SELECT '========================================' AS ' ';

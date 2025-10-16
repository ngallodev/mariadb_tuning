-- MariaDB Pre-Load Optimization Script - EXTREME MODE
-- Run this before bulk loading data from text files
-- This temporarily increases GLOBAL and SESSION variables for maximum speed
-- Usage: mysql -u root -p < mariadb_preload.sql

-- =====================================================
-- GLOBAL SETTINGS (affect entire server during load)
-- =====================================================

-- Note: sql_log_bin is SESSION-only variable
-- Binary logging is disabled per-session below

-- Increase global buffer pool for better caching during load
-- Note: Can't change buffer_pool_size without restart, but can optimize other settings

-- Increase max packet size for large inserts
SET GLOBAL max_allowed_packet = 1073741824; -- 1GB

-- Disable query cache if enabled (deprecated but some versions have it)
SET GLOBAL query_cache_type = 0;
SET GLOBAL query_cache_size = 0;

-- Aggressive flush settings for bulk load
SET GLOBAL innodb_flush_log_at_trx_commit = 0; -- Fastest, commits every ~1 second
SET GLOBAL innodb_flush_neighbors = 0; -- SSD optimization

-- Increase log buffer
SET GLOBAL innodb_log_buffer_size = 256 * 1024 * 1024; -- 256MB

-- Disable adaptive hash index during bulk load (can interfere)
SET GLOBAL innodb_adaptive_hash_index = OFF;

-- Increase change buffer to maximum
SET GLOBAL innodb_change_buffer_max_size = 50; -- 50% of buffer pool

-- Increase I/O capacity for bulk operations
SET GLOBAL innodb_io_capacity = 2000;
SET GLOBAL innodb_io_capacity_max = 4000;

-- =====================================================
-- SESSION SETTINGS (affect only this connection)
-- =====================================================

-- Disable binary logging for this session
SET SESSION sql_log_bin = 0;

-- Disable foreign key checks
SET SESSION foreign_key_checks = 0;

-- Disable unique key checks
SET SESSION unique_checks = 0;

-- Disable autocommit for better transaction batching
SET SESSION autocommit = 0;

-- EXTREME buffer sizes for this session
SET SESSION bulk_insert_buffer_size = 512 * 1024 * 1024; -- 512MB
SET SESSION sort_buffer_size = 512 * 1024 * 1024; -- 512MB
SET SESSION read_buffer_size = 16 * 1024 * 1024; -- 16MB
SET SESSION read_rnd_buffer_size = 32 * 1024 * 1024; -- 32MB
SET SESSION join_buffer_size = 32 * 1024 * 1024; -- 32MB

-- For MyISAM: extreme sort buffer
SET SESSION myisam_sort_buffer_size = 1024 * 1024 * 1024; -- 1GB

-- Show current session settings
SELECT '========================================' AS ' ';
SELECT 'EXTREME MODE: Pre-load optimizations applied' AS Status;
SELECT '========================================' AS ' ';
SELECT 'Global Settings Changed:' AS ' ';
SELECT '  - innodb_flush_log_at_trx_commit = 0 (FASTEST)' AS ' ';
SELECT '  - innodb_adaptive_hash_index = OFF' AS ' ';
SELECT '  - innodb_io_capacity increased' AS ' ';
SELECT '  - max_allowed_packet = 1GB' AS ' ';
SELECT '' AS ' ';
SELECT 'Session Settings:' AS ' ';
SELECT CONCAT('  - bulk_insert_buffer: ', @@SESSION.bulk_insert_buffer_size/1024/1024, ' MB') AS ' ';
SELECT CONCAT('  - sort_buffer: ', @@SESSION.sort_buffer_size/1024/1024, ' MB') AS ' ';
SELECT CONCAT('  - Foreign keys: ', IF(@@SESSION.foreign_key_checks=0, 'DISABLED', 'enabled')) AS ' ';
SELECT CONCAT('  - Unique checks: ', IF(@@SESSION.unique_checks=0, 'DISABLED', 'enabled')) AS ' ';
SELECT '========================================' AS ' ';
SELECT 'Ready for EXTREME bulk loading!' AS ' ';
SELECT '========================================' AS ' ';

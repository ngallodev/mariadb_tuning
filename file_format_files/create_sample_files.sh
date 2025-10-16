#!/bin/bash
#
# Create Sample Data Files in Different Formats
# Run this to generate test files for practicing bulk loads
#
# Usage: ./create_sample_files.sh
#

echo "Creating sample data files in various formats..."
echo ""

# Tab-delimited (default format)
cat > sample_tab.txt << 'EOF'
1	Alice Johnson	alice@example.com	2024-01-15	Engineering
2	Bob Smith	bob@example.com	2024-01-16	Sales
3	Charlie Brown	charlie@example.com	2024-01-17	Marketing
4	Diana Prince	diana@example.com	2024-01-18	Engineering
5	Eve Davis	eve@example.com	2024-01-19	HR
EOF
echo "✓ Created: sample_tab.txt (tab-delimited, default format)"

# CSV without quotes
cat > sample_csv.txt << 'EOF'
1,Alice Johnson,alice@example.com,2024-01-15,Engineering
2,Bob Smith,bob@example.com,2024-01-16,Sales
3,Charlie Brown,charlie@example.com,2024-01-17,Marketing
4,Diana Prince,diana@example.com,2024-01-18,Engineering
5,Eve Davis,eve@example.com,2024-01-19,HR
EOF
echo "✓ Created: sample_csv.txt (comma-separated)"

# CSV with header
cat > sample_csv_header.txt << 'EOF'
id,name,email,signup_date,department
1,Alice Johnson,alice@example.com,2024-01-15,Engineering
2,Bob Smith,bob@example.com,2024-01-16,Sales
3,Charlie Brown,charlie@example.com,2024-01-17,Marketing
4,Diana Prince,diana@example.com,2024-01-18,Engineering
5,Eve Davis,eve@example.com,2024-01-19,HR
EOF
echo "✓ Created: sample_csv_header.txt (CSV with header row)"

# CSV with quoted fields (for values containing commas)
cat > sample_csv_quoted.txt << 'EOF'
1,"Johnson, Alice","alice@example.com","Engineering, Software"
2,"Smith, Bob","bob@example.com","Sales, West Region"
3,"Brown, Charlie","charlie@example.com","Marketing, Digital"
4,"Prince, Diana","diana@example.com","Engineering, Hardware"
5,"Davis, Eve","eve@example.com","HR, Recruiting"
EOF
echo "✓ Created: sample_csv_quoted.txt (CSV with quoted fields)"

# Pipe-delimited
cat > sample_pipe.txt << 'EOF'
1|Alice Johnson|alice@example.com|2024-01-15|Engineering
2|Bob Smith|bob@example.com|2024-01-16|Sales
3|Charlie Brown|charlie@example.com|2024-01-17|Marketing
4|Diana Prince|diana@example.com|2024-01-18|Engineering
5|Eve Davis|eve@example.com|2024-01-19|HR
EOF
echo "✓ Created: sample_pipe.txt (pipe-delimited)"

# Semicolon-delimited
cat > sample_semicolon.txt << 'EOF'
1;Alice Johnson;alice@example.com;2024-01-15;Engineering
2;Bob Smith;bob@example.com;2024-01-16;Sales
3;Charlie Brown;charlie@example.com;2024-01-17;Marketing
4;Diana Prince;diana@example.com;2024-01-18;Engineering
5;Eve Davis;eve@example.com;2024-01-19;HR
EOF
echo "✓ Created: sample_semicolon.txt (semicolon-delimited)"

# File with NULL values
cat > sample_with_nulls.txt << 'EOF'
1	Alice Johnson	alice@example.com	2024-01-15	Engineering
2	Bob Smith	\N	2024-01-16	Sales
3	Charlie Brown	charlie@example.com	\N	Marketing
4	Diana Prince	diana@example.com	2024-01-18	\N
5	Eve Davis	\N	2024-01-19	HR
EOF
echo "✓ Created: sample_with_nulls.txt (with NULL values as \\N)"

# Larger sample file for performance testing (10,000 rows)
{
    for i in {1..10000}; do
        NAME="User$i"
        EMAIL="user$i@example.com"
        DATE=$(date -d "2024-01-01 + $i days" +%Y-%m-%d 2>/dev/null || date -j -f "%Y-%m-%d" -v+${i}d "2024-01-01" +%Y-%m-%d 2>/dev/null || echo "2024-01-15")
        DEPT=$((i % 5))
        case $DEPT in
            0) DEPT_NAME="Engineering";;
            1) DEPT_NAME="Sales";;
            2) DEPT_NAME="Marketing";;
            3) DEPT_NAME="HR";;
            4) DEPT_NAME="Operations";;
        esac
        echo -e "$i\t$NAME\t$EMAIL\t$DATE\t$DEPT_NAME"
    done
} > sample_large.txt
echo "✓ Created: sample_large.txt (10,000 rows for performance testing)"

# Create SQL file to create the test table
cat > create_test_table.sql << 'EOF'
-- Create test database and table for sample data
-- Usage: mysql -u root -p < create_test_table.sql

CREATE DATABASE IF NOT EXISTS test_bulk_load;
USE test_bulk_load;

DROP TABLE IF EXISTS users;

CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    signup_date DATE,
    department VARCHAR(50)
) ENGINE=InnoDB;

SELECT 'Test table created successfully!' AS Status;
SELECT 'Now you can load data with:' AS '';
SELECT './bulk_load.sh test_bulk_load users sample_tab.txt' AS Command;
EOF
echo "✓ Created: create_test_table.sql (table creation script)"

# Create a README for the samples
cat > SAMPLE_FILES_README.txt << 'EOF'
Sample Data Files for Testing Bulk Load
========================================

These sample files demonstrate different formats you can use with the
bulk_load.sh script.

Files Included:
---------------
1. sample_tab.txt           - Tab-delimited (DEFAULT - works without changes)
2. sample_csv.txt           - Comma-separated values
3. sample_csv_header.txt    - CSV with header row
4. sample_csv_quoted.txt    - CSV with quoted fields (commas in data)
5. sample_pipe.txt          - Pipe-delimited
6. sample_semicolon.txt     - Semicolon-delimited
7. sample_with_nulls.txt    - Tab-delimited with NULL values
8. sample_large.txt         - 10,000 rows for performance testing

Setup Instructions:
-------------------
1. Create the test database and table:
   mysql -u root -p < create_test_table.sql

2. Load the default format (no changes needed):
   ./bulk_load.sh test_bulk_load users sample_tab.txt

3. Try other formats (requires modifying bulk_load.sh):
   - For CSV: Change to FIELDS TERMINATED BY ','
   - For pipe: Change to FIELDS TERMINATED BY '|'
   - See FILE_FORMAT_GUIDE.md for details

Check File Format Before Loading:
----------------------------------
   ./check_file_format.sh sample_csv.txt

This will analyze the file and tell you exactly what settings to use!

Performance Test:
-----------------
Load the large file to test performance:
   ./bulk_load.sh test_bulk_load users sample_large.txt

Expected speed: 50,000-200,000 rows/second in extreme mode!

Column Mapping:
---------------
All sample files have these 5 columns in order:
1. id (INT)
2. name (VARCHAR)
3. email (VARCHAR)
4. signup_date (DATE)
5. department (VARCHAR)

Clean Up When Done:
-------------------
   mysql -u root -p -e "DROP DATABASE test_bulk_load;"

Happy testing!
EOF
echo "✓ Created: SAMPLE_FILES_README.txt (documentation)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All sample files created successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Files created:"
ls -lh sample*.txt create_test_table.sql SAMPLE_FILES_README.txt 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}'
echo ""
echo "Quick start:"
echo "  1. mysql -u root -p < create_test_table.sql"
echo "  2. ./bulk_load.sh test_bulk_load users sample_tab.txt"
echo "  3. mysql -u root -p test_bulk_load -e 'SELECT * FROM users;'"
echo ""
echo "Check format: ./check_file_format.sh sample_csv.txt"
echo "Read guide:   cat SAMPLE_FILES_README.txt"
echo ""

# Text File Format Guide for Bulk Loading

## Default Format (Used by bulk_load.sh)

The `bulk_load.sh` script expects **TAB-DELIMITED** files by default:

```
column1_value[TAB]column2_value[TAB]column3_value[NEWLINE]
column1_value[TAB]column2_value[TAB]column3_value[NEWLINE]
```

### Example Default Format:

**File: data.txt**
```
1	John Smith	john@example.com	2024-01-15
2	Jane Doe	jane@example.com	2024-01-16
3	Bob Wilson	bob@example.com	2024-01-17
```

**Table Structure:**
```sql
CREATE TABLE users (
    id INT,
    name VARCHAR(100),
    email VARCHAR(100),
    signup_date DATE
);
```

**Load Command:**
```bash
./bulk_load.sh mydb users data.txt
```

## Supported File Formats

### 1. Tab-Delimited (Default - No Changes Needed)

**Format:**
```
value1[TAB]value2[TAB]value3
value1[TAB]value2[TAB]value3
```

**Use with:**
```bash
./bulk_load.sh database table file.txt
```

---

### 2. CSV (Comma-Separated Values)

**Format:**
```
value1,value2,value3
value1,value2,value3
```

**With quotes for values containing commas:**
```
1,"Smith, John","123 Main St, Apt 4"
2,"Doe, Jane","456 Oak Ave"
```

**Modify bulk_load.sh:** Change line ~85:
```bash
# BEFORE:
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;

# AFTER:
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

**Or use manual loading:**
```bash
mysql -u root -p << EOF
USE database;
SET SESSION foreign_key_checks = 0;
SET SESSION unique_checks = 0;
SET SESSION autocommit = 0;

LOAD DATA LOCAL INFILE '/path/to/file.csv'
INTO TABLE tablename
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;

COMMIT;
EOF
```

---

### 3. CSV with Header Row

**Format:**
```
id,name,email,date
1,John Smith,john@example.com,2024-01-15
2,Jane Doe,jane@example.com,2024-01-16
```

**Modify bulk_load.sh:** Change line ~85:
```bash
# AFTER:
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;  # <-- Skip the header row
```

---

### 4. Pipe-Delimited

**Format:**
```
value1|value2|value3
value1|value2|value3
```

**Modify bulk_load.sh:** Change line ~85:
```bash
# AFTER:
FIELDS TERMINATED BY '|'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

---

### 5. Custom Delimiter

**Format:** Any custom delimiter like `;` or `~`
```
value1;value2;value3
value1;value2;value3
```

**Modify bulk_load.sh:** Change line ~85:
```bash
# AFTER:
FIELDS TERMINATED BY ';'  # <-- Your custom delimiter
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

---

### 6. Windows Line Endings (CRLF)

**Format:** Files created on Windows with `\r\n` line endings

**Modify bulk_load.sh:** Change line ~85:
```bash
# AFTER:
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\r\n'  # <-- Windows format
IGNORE 0 LINES;
```

**Or convert file first:**
```bash
# Convert Windows to Unix line endings
dos2unix datafile.txt

# Or using sed
sed -i 's/\r$//' datafile.txt
```

---

### 7. Fixed-Width Files (Not Directly Supported)

MariaDB's LOAD DATA doesn't handle fixed-width well. Convert first:

```bash
# Example: Convert fixed-width to tab-delimited
awk '{print substr($0,1,10) "\t" substr($0,11,20) "\t" substr($0,31)}' fixed.txt > tab.txt
```

---

## Special Cases

### NULL Values

**Representing NULL in your file:**

**Option 1: Use \N**
```
1	John	john@example.com
2	Jane	\N
3	Bob	bob@example.com
```

**Option 2: Empty field**
```
1	John	john@example.com
2	Jane	
3	Bob	bob@example.com
```

**In bulk_load.sh, add after line 85:**
```bash
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n'
(col1, col2, @var3)
SET col3 = NULLIF(@var3, '');  # <-- Converts empty strings to NULL
```

---

### Flattened CSV Without Line Endings

If the provider concatenated every record into a single line, rebuild proper line
endings before loading:

```bash
python3 lib/mariadb/file_format_files/fix_flat_csv.py \
  input_flat.csv repaired.csv \
  --columns 24 \
  --keep-header \
  --record-prefix-regex '^(?:\r)?\d+_\d+,'
```

Adjust `24` to match your table’s column count. Use `--drop-header` when you plan to
load with `IGNORE 1 LINES`. If you run the fixer on pre-split chunks, add `--skip-partial`
so it drops any truncated record at the end of the chunk. When records always start
with an id like `226517574_53231`, include `^` and optional `\r` in the prefix:
`--record-prefix-regex '^(?:\r)?\d+_\d+,'`. For CP1252/Latin-1 data, pass
`--encoding=latin-1 --encoding-errors=replace`.

To convert the repaired CSV to TSV while keeping embedded commas, use:

```bash
python3 lib/mariadb/file_format_files/convert_csv_to_tab.py \
  repaired.csv repaired.tsv
```

For SQL-style extracts where each row is wrapped in parentheses and uses single quotes,
run:

```bash
python3 lib/mariadb/file_format_files/convert_parenthesized_sql_to_tab.py \
  values_dump.txt values_dump.tsv
```

---

### Dates and Timestamps

**Supported date formats in file:**
- `2024-01-15` (YYYY-MM-DD) - Recommended
- `2024/01/15` (YYYY/MM/DD)
- `01/15/2024` (MM/DD/YYYY) - Requires transformation

**For MM/DD/YYYY format, add transformation:**
```sql
LOAD DATA LOCAL INFILE 'file.txt'
INTO TABLE tablename
FIELDS TERMINATED BY '\t'
(@date_string, other_columns)
SET date_column = STR_TO_DATE(@date_string, '%m/%d/%Y');
```

---

### Escaping Special Characters

**Characters that need escaping:**
- Tab character in data: `\t`
- Newline in data: `\n`
- Backslash: `\\`
- Quote: `\"`

**Example file with escaped characters:**
```
1	John\tSmith	Description with\nnewline
2	Jane\\Doe	Quote: \"Hello\"
```

---

## Quick Format Check Script

Create this script to check your file format:

```bash
#!/bin/bash
# check_file_format.sh

FILE=$1

echo "Checking file format: $FILE"
echo ""

# Check line count
LINES=$(wc -l < "$FILE")
echo "Total lines: $LINES"

# Check first 5 lines
echo ""
echo "First 5 lines:"
head -5 "$FILE"

# Check for tabs
TABS=$(head -100 "$FILE" | grep -c $'\t')
echo ""
echo "Lines with tabs (first 100): $TABS"

# Check for commas
COMMAS=$(head -100 "$FILE" | grep -c ',')
echo "Lines with commas (first 100): $COMMAS"

# Check for pipes
PIPES=$(head -100 "$FILE" | grep -c '|')
echo "Lines with pipes (first 100): $PIPES"

# Check line endings
if file "$FILE" | grep -q CRLF; then
    echo ""
    echo "⚠ Warning: File has Windows line endings (CRLF)"
    echo "Consider converting: dos2unix $FILE"
else
    echo ""
    echo "✓ File has Unix line endings (LF)"
fi

# Show delimiter counts in first line
echo ""
echo "First line delimiter counts:"
FIRST_LINE=$(head -1 "$FILE")
echo "  Tabs: $(echo "$FIRST_LINE" | tr -cd '\t' | wc -c)"
echo "  Commas: $(echo "$FIRST_LINE" | tr -cd ',' | wc -c)"
echo "  Pipes: $(echo "$FIRST_LINE" | tr -cd '|' | wc -c)"

# Sample with visible delimiters
echo ""
echo "First line with visible tabs (·) and newlines ($):"
head -1 "$FILE" | sed 's/\t/[TAB]/g' | cat -A
```

**Use it:**
```bash
chmod +x check_file_format.sh
./check_file_format.sh yourdata.txt
```

---

## Creating Test Files

### Tab-Delimited Test File:
```bash
cat > test_tab.txt << 'EOF'
1	Alice	alice@example.com	2024-01-01
2	Bob	bob@example.com	2024-01-02
3	Charlie	charlie@example.com	2024-01-03
EOF
```

### CSV Test File:
```bash
cat > test_csv.txt << 'EOF'
1,Alice,alice@example.com,2024-01-01
2,Bob,bob@example.com,2024-01-02
3,"Charlie Smith","charlie@example.com",2024-01-03
EOF
```

### CSV with Header:
```bash
cat > test_csv_header.txt << 'EOF'
id,name,email,signup_date
1,Alice,alice@example.com,2024-01-01
2,Bob,bob@example.com,2024-01-02
3,Charlie,charlie@example.com,2024-01-03
EOF
```

---

## Modifying bulk_load.sh for Different Formats

**Location to edit:** Lines 83-91 in `bulk_load.sh`

**Current code:**
```bash
LOAD DATA LOCAL INFILE '$DATAFILE'
INTO TABLE $TABLE
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

**For CSV:**
```bash
LOAD DATA LOCAL INFILE '$DATAFILE'
INTO TABLE $TABLE
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

**For CSV with header:**
```bash
LOAD DATA LOCAL INFILE '$DATAFILE'
INTO TABLE $TABLE
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;
```

**For pipe-delimited:**
```bash
LOAD DATA LOCAL INFILE '$DATAFILE'
INTO TABLE $TABLE
FIELDS TERMINATED BY '|'
LINES TERMINATED BY '\n'
IGNORE 0 LINES;
```

---

## Common File Format Errors

### Error: "Row doesn't contain data for all columns"
**Cause:** Mismatch between file columns and table columns

**Solutions:**
1. Check column count matches table
2. Specify column mapping:
```sql
LOAD DATA LOCAL INFILE 'file.txt'
INTO TABLE tablename
FIELDS TERMINATED BY '\t'
(col1, col2, col3);  # <-- Explicitly map columns
```

### Error: "Incorrect date value"
**Cause:** Date format mismatch

**Solutions:**
1. Use YYYY-MM-DD format in file
2. Transform during load:
```sql
(@date_var, other_columns)
SET date_column = STR_TO_DATE(@date_var, '%m/%d/%Y');
```

### Error: "Data too long for column"
**Cause:** Data exceeds column width

**Solutions:**
1. Increase column size: `ALTER TABLE t MODIFY column VARCHAR(500);`
2. Truncate data during load

---

## Best Practices

1. **Use tab-delimited by default** - Simplest and fastest
2. **No header rows** - Or use `IGNORE 1 LINES` if present
3. **UTF-8 encoding** - Use UTF-8 for international characters
4. **Unix line endings** - Use `\n` not `\r\n`
5. **Consistent delimiters** - Same delimiter throughout file
6. **Escape special chars** - Properly escape tabs, newlines, etc.
7. **Test with small file first** - Validate format before bulk loading
8. **Pre-sort data** - Sort by primary key for 20-30% speed boost

---

## Format Conversion Tools

**Convert CSV to Tab:**
```bash
# Using sed
sed 's/,/\t/g' file.csv > file.txt

# Using awk (better for quoted fields)
awk -F',' '{OFS="\t"; print $1,$2,$3}' file.csv > file.txt
```

**Convert Windows to Unix:**
```bash
dos2unix file.txt
# Or
sed -i 's/\r$//' file.txt
```

**Remove header row:**
```bash
tail -n +2 file.txt > file_no_header.txt
```

**Add line numbers:**
```bash
awk '{print NR "\t" $0}' file.txt > file_with_id.txt
```

---

## Summary: Quick Format Reference

| Format | Delimiter | Sample | Modify Script |
|--------|-----------|--------|---------------|
| Tab (default) | `\t` | `val1[TAB]val2` | No changes needed |
| CSV | `,` | `val1,val2` | `FIELDS TERMINATED BY ','` |
| Pipe | `\|` | `val1\|val2` | `FIELDS TERMINATED BY '\|'` |
| Custom | Any | `val1;val2` | `FIELDS TERMINATED BY ';'` |
| With header | Any | Row 1 = headers | Add `IGNORE 1 LINES` |
| Windows | Any | CRLF endings | `LINES TERMINATED BY '\r\n'` |

**Default works best:** Stick with tab-delimited, no header, Unix line endings for optimal performance!

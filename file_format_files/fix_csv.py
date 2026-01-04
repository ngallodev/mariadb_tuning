from pathlib import Path
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
text = Path(src_path).read_text(encoding="utf-8", newline="")
if not text:
    Path(dst_path).write_text("", encoding="utf-8")
    raise SystemExit
lines = text.splitlines()
sep = ","
expected_commas = lines[0].count(sep)

def analyze(row):
    in_quotes = False
    comma_count = 0
    i = 0
    n = len(row)
    while i < n:
        ch = row[i]
        if ch == '"':
            if in_quotes and i + 1 < n and row[i + 1] == '"':
                i += 2
                continue
            in_quotes = not in_quotes
        elif ch == sep and not in_quotes:
            comma_count += 1
        i += 1
    return in_quotes, comma_count

rows = [lines[0]]
for line in lines[1:]:
    if not rows:
        rows.append(line)
        continue
    in_quotes_prev, _ = analyze(rows[-1])
    commas = analyze(line)[1]
    if commas < expected_commas:
        joiner = '\n' if in_quotes_prev else ' '
        rows[-1] = rows[-1] + joiner + line
    elif in_quotes_prev:
        rows[-1] = rows[-1] + '\n' + line
    else:
        rows.append(line)

Path(dst_path).write_text('\n'.join(rows) + '\n', encoding='utf-8')

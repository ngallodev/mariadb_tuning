#!/usr/bin/env python3
"""Helpers for working with SQL `VALUES (...)` tuple payloads.

Most SQL data dumps arrive as giant INSERT statements.  Each tuple
contains comma-separated fields with single quotes, doubled quotes, and
backslash escapes.  The utilities in this module turn those raw text fragments
into Python objects that preserve both the cleaned value and whether the source
field was quoted.  Downstream pipeline stages can then modify or normalize
fields without losing necessary quoting information when they re-serialize rows.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List


@dataclass(frozen=True)
class ParsedValue:
    """Represents a single field parsed from a SQL tuple.

    Attributes:
        text:       The normalized textual content of the field with escape
                    sequences resolved.
        was_quoted: True if the original field was surrounded by single quotes.
    """

    text: str
    was_quoted: bool


def parse_sql_row(row: str) -> List[ParsedValue]:
    """Parse a SQL `VALUES` tuple payload into :class:`ParsedValue` objects.

    Args:
        row: The substring between parentheses, e.g. `"1,'abc',NULL"`.

    Returns:
        A list of :class:`ParsedValue` instances, one per column.
    """
    values: List[ParsedValue] = []
    current: List[str] = []
    in_quote = False
    was_quoted = False
    i = 0
    length = len(row)

    while i < length:
        ch = row[i]

        if in_quote:
            # Handle backslash escapes for quotes and backslashes.
            if ch == "\\":
                if i + 1 < length:
                    nxt = row[i + 1]
                    if nxt in ("'", "\\"):
                        current.append(nxt)
                        i += 2
                        continue
                current.append("\\")
                i += 1
                continue

            # Handle doubled single quotes inside quoted strings.
            if ch == "'" and i + 1 < length and row[i + 1] == "'":
                current.append("'")
                i += 2
                continue

            # Closing quote.
            if ch == "'":
                in_quote = False
                i += 1
                continue

            current.append(ch)
            i += 1
            continue

        # Outside of quoted strings.
        if ch == "'":
            in_quote = True
            was_quoted = True
            i += 1
            continue

        if ch == ",":
            values.append(ParsedValue("".join(current).strip(), was_quoted))
            current.clear()
            was_quoted = False
            i += 1
            # Skip any extra spaces after a delimiter.
            while i < length and row[i].isspace():
                i += 1
            continue

        if ch in ("\r", "\n"):
            i += 1
            continue

        current.append(ch)
        i += 1

    values.append(ParsedValue("".join(current).strip(), was_quoted))
    return values


def serialize_sql_row(values: Iterable[ParsedValue]) -> str:
    """Serialize :class:`ParsedValue` entries back into a SQL tuple string."""
    parts: List[str] = []
    for item in values:
        if item.was_quoted:
            escaped = (
                item.text.replace("\\", "\\\\")
                .replace("'", "\\'")
            )
            parts.append(f"'{escaped}'")
        else:
            parts.append(item.text)
    return ",".join(parts)


def count_columns(row: str) -> int:
    """Return the number of columns present in *row*."""
    return len(parse_sql_row(row))

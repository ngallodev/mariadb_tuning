#!/usr/bin/env python3
"""
Run convert_parenthesized_sql_to_tab.py across many INSERT files in parallel.

Example:
    python batch_convert_parenthesized.py inserts_dir output_dir \
        --workers 8 --extra "--encoding latin-1 --encoding-errors replace"
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Iterable, List, Sequence

DEFAULT_SCRIPT = Path("/usr/local/lib/mariadb/file_format_files/convert_parenthesized_sql_to_tab.py")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Batch convert parenthesized SQL INSERT files to tab-delimited output."
    )
    parser.add_argument(
        "input_dir",
        type=Path,
        help="Directory containing INSERT chunk files (e.g., *_insert_*.sql).",
    )
    parser.add_argument(
        "output_dir",
        type=Path,
        help="Directory to write converted tab-delimited files.",
    )
    parser.add_argument(
        "--script",
        type=Path,
        default=DEFAULT_SCRIPT,
        help=f"Path to convert_parenthesized_sql_to_tab.py (default: {DEFAULT_SCRIPT}).",
    )
    parser.add_argument(
        "--pattern",
        default="*_insert_*.sql",
        help="Glob pattern to select input files (default: *_insert_*.sql).",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        help="Number of worker processes (default: CPU count).",
    )
    parser.add_argument(
        "--suffix",
        default=".tsv",
        help="Output file suffix/extension (default: .tsv).",
    )
    parser.add_argument(
        "--extra",
        default="",
        help="Additional arguments to pass to the converter (quote as needed).",
    )
    return parser.parse_args()


def build_command(script: Path, src: Path, dst: Path, extra_args: Sequence[str]) -> List[str]:
    cmd = [sys.executable, str(script), str(src), str(dst)]
    return cmd + list(extra_args)


def run_worker(script: Path, src: Path, dst: Path, extra_args: Sequence[str]) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)

    cmd = build_command(script, src, dst, extra_args)
    completed = subprocess.run(cmd, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Conversion failed for {src.name} (exit {completed.returncode}).\n"
            f"Command: {' '.join(cmd)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )


def discover_inputs(directory: Path, pattern: str) -> Iterable[Path]:
    return sorted(directory.glob(pattern))


def main() -> None:
    args = parse_args()

    if not args.input_dir.is_dir():
        raise SystemExit(f"Input directory not found: {args.input_dir}")
    if not args.script.is_file():
        raise SystemExit(f"Converter script not found: {args.script}")

    inputs = list(discover_inputs(args.input_dir, args.pattern))
    if not inputs:
        raise SystemExit(f"No files matching '{args.pattern}' found in {args.input_dir}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    extra_args = shlex.split(args.extra)

    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        futures = {}
        for src in inputs:
            out_name = src.with_suffix(args.suffix).name
            dst = args.output_dir / out_name
            futures[executor.submit(run_worker, args.script, src, dst, extra_args)] = src

        for future in as_completed(futures):
            src = futures[future]
            try:
                future.result()
            except Exception as exc:
                raise SystemExit(f"Error processing {src}:\n{exc}") from exc

    print(f"Converted {len(inputs)} file(s) into {args.output_dir}")


if __name__ == "__main__":
    main()

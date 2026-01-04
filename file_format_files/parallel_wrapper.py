#!/usr/bin/env python3
"""
parallel_wrapper.py

Run an existing single-process file-format utility across a file in parallel.

Example:
    python3 parallel_wrapper.py convert_parenthesized_sql_to_tab.py \
        /path/to/input.sql /path/to/output.tsv --workers 6 --chunk-lines 75000 \
        -- --encoding latin-1 --encoding-errors replace

The wrapper slices the input into newline-aligned chunks, hands each chunk to the
target utility in a separate process, and stitches the outputs back together in
order. Any arguments that follow ``--`` are passed through to the wrapped
utility unchanged.
"""

from __future__ import annotations

import argparse
import multiprocessing as mp
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import os

DEFAULT_CHUNK_LINES = 50000


@dataclass(frozen=True)
class ChunkTask:
    """Instructions for a worker to process a chunk file."""

    index: int
    input_path: Path


def parse_args() -> Tuple[argparse.Namespace, List[str]]:
    parser = argparse.ArgumentParser(
        description="Parallelize line-oriented format converters by chunking input."
    )
    parser.add_argument(
        "script",
        help="Path or basename of the utility to execute (e.g., convert_parenthesized_sql_to_tab.py).",
    )
    parser.add_argument("input", type=Path, help="Input file to process.")
    parser.add_argument("output", type=Path, help="Destination file to write.")
    parser.add_argument(
        "--workers",
        type=int,
        default=max(1, mp.cpu_count() - 1),
        help="Number of worker processes (default: CPU count minus one).",
    )
    parser.add_argument(
        "--chunk-lines",
        type=int,
        default=DEFAULT_CHUNK_LINES,
        help="Maximum lines per chunk passed to each worker (default: %(default)s).",
    )
    parser.add_argument(
        "--temp-dir",
        type=Path,
        default=None,
        help="Directory for temporary chunk files (default: system temp dir).",
    )
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="Preserve chunk temp files for debugging (default: delete on success).",
    )
    args, passthrough = parser.parse_known_args()
    return args, passthrough


def resolve_script(script_arg: str) -> Path:
    candidate = Path(script_arg)
    if candidate.is_file():
        return candidate.resolve()

    # Look relative to this wrapper.
    sibling = Path(__file__).parent / script_arg
    if sibling.is_file():
        return sibling.resolve()

    raise SystemExit(f"Utility script '{script_arg}' not found.")


def chunk_input_file(
    source: Path, chunk_lines: int, temp_dir: Path | None
) -> Iterable[ChunkTask]:
    if chunk_lines <= 0:
        raise SystemExit("--chunk-lines must be greater than zero.")

    with source.open("rb") as src:
        index = 0
        while True:
            chunk_bytes = bytearray()
            line = b""
            for _ in range(chunk_lines):
                line = src.readline()
                if not line:
                    break
                chunk_bytes.extend(line)

            if not chunk_bytes:
                break

            tmp = tempfile.NamedTemporaryFile(
                mode="wb", delete=False, dir=None if temp_dir is None else str(temp_dir)
            )
            try:
                tmp.write(chunk_bytes)
                tmp.flush()
            finally:
                tmp.close()

            yield ChunkTask(index=index, input_path=Path(tmp.name))
            index += 1

            if line == b"":
                break


def worker_job(
    task: ChunkTask,
    script_path: Path,
    passthrough: Sequence[str],
    temp_dir: Path | None,
    keep_temp: bool,
) -> Tuple[int, bytes]:
    tmp_out = tempfile.NamedTemporaryFile(
        mode="wb", delete=False, dir=None if temp_dir is None else str(temp_dir)
    )
    tmp_out_path = Path(tmp_out.name)
    tmp_out.close()
    safe_unlink(tmp_out_path)

    cmd = build_command(script_path, task.input_path, tmp_out_path, passthrough)

    completed = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    if completed.returncode != 0:
        error_lines = [
            f"Chunk {task.index} failed (exit {completed.returncode}).",
            f"Command: {' '.join(cmd)}",
        ]
        if completed.stdout:
            error_lines.append("stdout:\n" + completed.stdout)
        if completed.stderr:
            error_lines.append("stderr:\n" + completed.stderr)

        if not keep_temp:
            safe_unlink(task.input_path)
            safe_unlink(tmp_out_path)

        raise RuntimeError("\n".join(error_lines))

    output_bytes = tmp_out_path.read_bytes()

    if not keep_temp:
        safe_unlink(task.input_path)
        safe_unlink(tmp_out_path)

    return task.index, output_bytes


def safe_unlink(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def build_command(
    script_path: Path,
    chunk_input: Path,
    chunk_output: Path,
    passthrough: Sequence[str],
) -> List[str]:
    suffix = script_path.suffix.lower()

    if suffix == ".py":
        base = [sys.executable, str(script_path)]
    elif suffix in {".sh", ".bash"}:
        base = ["bash", str(script_path)]
    elif os.access(script_path, os.X_OK):
        base = [str(script_path)]
    else:
        base = ["bash", str(script_path)]

    return base + [str(chunk_input), str(chunk_output), *passthrough]


def main() -> None:
    args, passthrough = parse_args()

    input_path = args.input.resolve()
    output_path = args.output.resolve()

    if not input_path.is_file():
        raise SystemExit(f"Input file '{input_path}' not found.")
    if input_path == output_path:
        raise SystemExit("Input and output paths must differ.")

    script_path = resolve_script(args.script)

    if output_path.exists():
        output_path.unlink()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    temp_dir = args.temp_dir.resolve() if args.temp_dir else None
    if temp_dir and not temp_dir.exists():
        temp_dir.mkdir(parents=True, exist_ok=True)

    tasks = list(chunk_input_file(input_path, args.chunk_lines, temp_dir))

    if not tasks:
        output_path.touch()
        return

    def emit_in_order(dest_handle, results: Iterable[Tuple[int, bytes]]) -> None:
        pending: Dict[int, bytes] = {}
        next_index = 0

        for index, chunk_bytes in results:
            pending[index] = chunk_bytes
            while next_index in pending:
                dest_handle.write(pending.pop(next_index))
                next_index += 1

        if pending:
            raise RuntimeError(
                "Processing completed but some chunks were not written in order."
            )

    def sequential_results() -> Iterable[Tuple[int, bytes]]:
        for task in tasks:
            yield worker_job(
                task=task,
                script_path=script_path,
                passthrough=passthrough,
                temp_dir=temp_dir,
                keep_temp=args.keep_temp,
            )

    with output_path.open("wb") as dest:
        if args.workers <= 1:
            emit_in_order(dest, sequential_results())
            return

        try:
            with mp.Pool(processes=args.workers) as pool:
                async_results = [
                    pool.apply_async(
                        worker_job,
                        kwds=dict(
                            task=task,
                            script_path=script_path,
                            passthrough=passthrough,
                            temp_dir=temp_dir,
                            keep_temp=args.keep_temp,
                        ),
                    )
                    for task in tasks
                ]

                def result_iter() -> Iterable[Tuple[int, bytes]]:
                    for async_result in async_results:
                        yield async_result.get()

                emit_in_order(dest, result_iter())
        except (PermissionError, OSError):
            sys.stderr.write(
                "Warning: multiprocessing unavailable; falling back to sequential processing.\n"
            )
            emit_in_order(dest, sequential_results())


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as exc:
        raise SystemExit(str(exc))

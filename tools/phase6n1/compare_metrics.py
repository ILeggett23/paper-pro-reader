#!/usr/bin/env python3
"""Aggregate privacy-safe Phase 6N-1 optical and counter measurements.

Input contains timing/counter outcomes only. Coordinates, text, and raw event
sequences are intentionally unsupported.
"""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from collections import defaultdict
from pathlib import Path


REQUIRED_COLUMNS = {
    "backend",
    "run_id",
    "contact_to_visible_ms",
    "settle_ms",
    "raw_samples",
    "rendered_samples",
    "handed_samples",
    "dropped_samples",
    "display_updates",
    "coalesced_updates",
    "missing_segments",
    "quality_flashes_during_contact",
    "safe_exit",
    "persistence_handoff",
}


def number(row: dict[str, str], key: str) -> float:
    value = row[key].strip()
    return float(value) if value else math.nan


def integer(row: dict[str, str], key: str) -> int:
    value = row[key].strip()
    return int(value) if value else 0


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(value for value in values if not math.isnan(value))
    if not ordered:
        return math.nan
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def yes_count(rows: list[dict[str, str]], key: str) -> tuple[int, int]:
    values = [row[key].strip().lower() for row in rows if row[key].strip()]
    return sum(value in {"yes", "true", "pass", "1"} for value in values), len(values)


def format_number(value: float) -> str:
    return "PENDING" if math.isnan(value) else f"{value:.2f}"


def load_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        columns = set(reader.fieldnames or [])
        missing = REQUIRED_COLUMNS - columns
        if missing:
            raise SystemExit(f"missing columns: {', '.join(sorted(missing))}")
        rows = list(reader)
    if not rows:
        raise SystemExit("measurement file has no data rows")
    return rows


def render(rows: list[dict[str, str]]) -> str:
    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        backend = row["backend"].strip()
        if not backend:
            raise SystemExit("backend must not be blank")
        grouped[backend].append(row)

    lines = [
        "| Backend | Runs | Visible median ms | Visible p95 ms | Settle median ms | Dropped | Missing segments | Contact quality flashes | Safe exit | Persistence |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for backend in sorted(grouped):
        backend_rows = grouped[backend]
        visible = [number(row, "contact_to_visible_ms") for row in backend_rows]
        settle = [number(row, "settle_ms") for row in backend_rows]
        safe_yes, safe_total = yes_count(backend_rows, "safe_exit")
        persist_yes, persist_total = yes_count(backend_rows, "persistence_handoff")
        lines.append(
            "| {backend} | {runs} | {visible_median} | {visible_p95} | {settle_median} | {dropped} | {missing} | {flashes} | {safe} | {persist} |".format(
                backend=backend,
                runs=len(backend_rows),
                visible_median=format_number(statistics.median(v for v in visible if not math.isnan(v)))
                if any(not math.isnan(v) for v in visible) else "PENDING",
                visible_p95=format_number(percentile(visible, 0.95)),
                settle_median=format_number(statistics.median(v for v in settle if not math.isnan(v)))
                if any(not math.isnan(v) for v in settle) else "PENDING",
                dropped=sum(integer(row, "dropped_samples") for row in backend_rows),
                missing=sum(integer(row, "missing_segments") for row in backend_rows),
                flashes=sum(integer(row, "quality_flashes_during_contact") for row in backend_rows),
                safe=f"{safe_yes}/{safe_total}" if safe_total else "PENDING",
                persist=f"{persist_yes}/{persist_total}" if persist_total else "PENDING",
            )
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    result = render(load_rows(arguments.csv))
    if arguments.output:
        arguments.output.write_text(result, encoding="utf-8")
    else:
        print(result, end="")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Patch Cura-style LulzBot TAZ Pro dual-extrusion G-code.

This helper was created for an observed startup issue where the tool head did
not always descend fully to the bed during the wipe routine. It writes a new
``*_patched.gcode`` file next to the input file and leaves the original file
unchanged.

The patch is intentionally conservative and printer-specific. Inspect the
patched G-code in a slicer or G-code viewer before printing.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re

PATCH_MARKER = "added by patch_tazpro_dual.py"

FALLBACK_T1_PRINT_TEMP_C = 250

TOP_INIT_BLOCK = [
    "; --- TOP INIT (added by patch_tazpro_dual.py) ---",
    "G21        ; mm",
    "G90        ; absolute XYZ",
    "M82        ; absolute E",
    "G92 E0",
    "M400       ; wait for planner",
    "G28        ; home all axes",
    "M400",
    "; -----------------------------------------------",
]

PRE_WIPE_BLOCK = [
    "; --- PRE-WIPE HARDENING (added by patch_tazpro_dual.py) ---",
    "G21",
    "G90",
    "M82",
    "G92 E0",
    "M400",
    "G28        ; re-home immediately before wipe",
    "M400",
    "; ----------------------------------------------------------",
]

TOOL_T0_RE = re.compile(r"^\s*T0\s*$")
TOOL_T1_RE = re.compile(r"^\s*T1\s*$")
G12_RE = re.compile(r"^\s*G12(\s|$)")
COMMENT_RE = re.compile(r"^\s*;")
EXTRUDE_POS_RE = re.compile(r"^\s*G0?1\b.*\bE(\d+(\.\d+)?)\b")
T1_TEMP_RE = re.compile(r"^\s*M10[49]\b.*\bT1\b.*\bS(-?\d+(\.\d+)?)\b")


def make_t1_wake_block(t1_temp_c: int) -> list[str]:
    return [
        f"; --- T1 WAKE (added by patch_tazpro_dual.py) target={t1_temp_c}C ---",
        f"M104 T1 S{t1_temp_c}",
        f"M109 T1 S{t1_temp_c}     ; wait before first positive T1 extrusion",
        "; ---------------------------------------------------------------",
    ]


def find_top_insertion_index(lines: list[str]) -> int:
    idx = 0
    while idx < len(lines) and lines[idx].strip() == "":
        idx += 1
    while idx < len(lines) and (COMMENT_RE.match(lines[idx]) or lines[idx].strip() == ""):
        idx += 1
    return idx


def detect_t1_print_temp(lines: list[str]) -> int:
    temps: list[float] = []
    for line in lines:
        match = T1_TEMP_RE.match(line)
        if not match:
            continue
        try:
            value = float(match.group(1))
        except ValueError:
            continue
        if value >= 200:
            temps.append(value)
    if temps:
        return int(round(max(temps)))
    return FALLBACK_T1_PRINT_TEMP_C


def output_path_for(input_path: Path) -> Path:
    if input_path.suffix.lower() == ".gcode":
        return input_path.with_name(input_path.stem + "_patched.gcode")
    return input_path.with_name(input_path.name + "_patched.gcode")


def patch_gcode(input_path: Path, *, allow_repatch: bool = False) -> Path:
    lines = input_path.read_text(errors="replace").splitlines()
    if not allow_repatch and any(PATCH_MARKER in line for line in lines):
        raise RuntimeError(
            "This file already appears to contain patch_tazpro_dual.py blocks. "
            "Use --allow-repatch only if you intentionally want to patch it again."
        )

    t1_target = detect_t1_print_temp(lines)
    t1_wake_block = make_t1_wake_block(t1_target)

    out: list[str] = []
    inserted_prewipe = False
    active_tool: int | None = None
    pending_t1_wait = False

    idx = find_top_insertion_index(lines)
    out.extend(lines[:idx])
    out.extend(TOP_INIT_BLOCK)
    lines_iter = lines[idx:]

    for line in lines_iter:
        if not inserted_prewipe and G12_RE.match(line):
            out.extend(PRE_WIPE_BLOCK)
            inserted_prewipe = True
            out.append(line)
            continue

        if TOOL_T0_RE.match(line):
            active_tool = 0
            pending_t1_wait = False
            out.append(line)
            continue

        if TOOL_T1_RE.match(line):
            active_tool = 1
            pending_t1_wait = True
            out.append(line)
            continue

        if active_tool == 1 and pending_t1_wait and EXTRUDE_POS_RE.match(line):
            out.extend(t1_wake_block)
            pending_t1_wait = False
            out.append(line)
            continue

        out.append(line)

    if not inserted_prewipe:
        raise RuntimeError("Did not find a G12 wipe command to patch before.")

    output_path = output_path_for(input_path)
    output_path.write_text("\n".join(out) + "\n")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gcode_file", type=Path, help="Input .gcode file")
    parser.add_argument(
        "--allow-repatch",
        action="store_true",
        help="Allow patching a file that already contains patch marker comments.",
    )
    args = parser.parse_args()

    if not args.gcode_file.exists():
        raise SystemExit(f"File not found: {args.gcode_file}")

    output_file = patch_gcode(args.gcode_file, allow_repatch=args.allow_repatch)
    print(f"Wrote: {output_file}")


if __name__ == "__main__":
    main()

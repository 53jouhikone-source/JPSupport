#!/usr/bin/env python3
"""
JPSupport-Qt: apply the Japanese-IME patch set to a Lazarus source tree.

Usage:  apply_jpsupport_patches.py [qt5|qt6|both]      (default: both)
Run it inside the Lazarus source tree, or set LAZARUS_SRC_PATH.

Two patch sets live next to this script:
  lazarus_4_8/  generated for the Lazarus 4.8 release (tag lazarus_4_8)
  upstream/     generated for Lazarus main (review snapshots)
The first set that applies completely to the tree is used. Nothing is
changed unless every needed patch of that set applies cleanly.
Patches already applied are skipped. Needs the "patch" command.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path(os.environ.get("LAZARUS_SRC_PATH", os.getcwd()))
SETS = ["lazarus_4_8", "upstream"]


def run_patch(patch, extra):
    return subprocess.run(
        ["patch", "-p1", "-s", "-f"] + extra + ["-i", str(patch)],
        cwd=SRC, stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode


def state(patch):
    if run_patch(patch, ["--dry-run"]) == 0:
        return "new"
    if run_patch(patch, ["-R", "--dry-run"]) == 0:
        return "applied"
    return "fail"


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "both"
    if target not in ("qt5", "qt6", "both"):
        print(f"ERROR: unknown target '{target}' (expected qt5, qt6 or both).")
        return 1
    names = ["lmessages", "lazsynime-refactor"]
    if target in ("qt5", "both"):
        names.append("qt5-bindings")
    if target in ("qt6", "both"):
        names.append("qt6-bindings")

    for setname in SETS:
        patches = [HERE / setname / f"jpsupport-qt-{n}.patch" for n in names]
        if not all(p.is_file() for p in patches):
            continue
        states = [state(p) for p in patches]
        if "fail" in states:
            continue
        print(f"Using patch set: {setname}")
        for p, s in zip(patches, states):
            if s == "applied":
                print(f"  skip (already applied): {p.name}")
                continue
            if run_patch(p, []) != 0:
                print(f"ERROR: failed to apply {p.name}")
                return 1
            print(f"  applied: {p.name}")
        print(f"OK: JPSupport patches ({target}) are in place.")
        return 0

    print("ERROR: no patch set applies cleanly to this Lazarus tree:", SRC)
    print("       (tried: " + ", ".join(SETS) + ")")
    return 1


if __name__ == "__main__":
    sys.exit(main())

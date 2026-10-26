#!/usr/bin/env python3
"""
JPSupport-Qt: apply the Japanese-IME patch set to a Lazarus source tree.

Usage:  apply_jpsupport_patches.py [qt5|qt6|both] [--keep-disabled]
        (default target: both)
Run it inside the Lazarus source tree, or set LAZARUS_SRC_PATH.

Two patch sets live next to this script:
  lazarus_4_8/  generated for the Lazarus 4.8 release (tag lazarus_4_8)
  upstream/     generated for Lazarus main (review snapshots)
The first set that applies completely to the tree is used. Nothing is
changed unless every needed patch of that set applies cleanly.
Patches already applied are skipped. Needs the "patch" command.

The Qt widgetset part is guarded by the define QTFULLINPUTMETHODSUPPORT,
which the patches ship DISABLED in lcl/interfaces/qt5|qt6/qtdefines.inc
(enabling it requires rebuilding libQt5Pas/libQt6Pas). This script enables
it after a successful run, because JPSupport-Qt needs it. Use
--keep-disabled to leave it disabled.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path(os.environ.get("LAZARUS_SRC_PATH", os.getcwd()))
SETS = ["lazarus_4_8", "upstream"]
DEF_ON = "{$DEFINE QTFULLINPUTMETHODSUPPORT}"
DEF_OFF = "{.$DEFINE QTFULLINPUTMETHODSUPPORT}"


def inc_path(q):
    return SRC / "lcl" / "interfaces" / q / "qtdefines.inc"


def set_define(q, enable):
    """Switch the define in qtdefines.inc. Returns True if the file changed."""
    p = inc_path(q)
    if not p.is_file():
        return False
    with p.open("r", encoding="utf-8", newline="") as f:
        s = f.read()
    old, new = (DEF_OFF, DEF_ON) if enable else (DEF_ON, DEF_OFF)
    if s.count(old) != 1:
        return False
    with p.open("w", encoding="utf-8", newline="") as f:
        f.write(s.replace(old, new))
    return True


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


def apply_sets(names, target):
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
        return 0

    print("ERROR: no patch set applies cleanly to this Lazarus tree:", SRC)
    print("       (tried: " + ", ".join(SETS) + ")")
    return 1


def main():
    args = sys.argv[1:]
    keep_disabled = "--keep-disabled" in args
    args = [a for a in args if a != "--keep-disabled"]
    target = args[0] if args else "both"
    if target not in ("qt5", "qt6", "both"):
        print(f"ERROR: unknown target '{target}' (expected qt5, qt6 or both).")
        return 1
    names = ["lmessages", "lazsynime-refactor"]
    if target in ("qt5", "both"):
        names.append("qt5-bindings")
    if target in ("qt6", "both"):
        names.append("qt6-bindings")
    qts = {"qt5": ["qt5"], "qt6": ["qt6"], "both": ["qt5", "qt6"]}[target]

    # Put the define back into the form the patches use, so that already
    # applied patches are recognised; remember what to restore on failure.
    was_on = [q for q in qts if set_define(q, False)]
    rc = apply_sets(names, target)
    if rc == 0 and not keep_disabled:
        for q in qts:
            if set_define(q, True):
                print(f"  enabled QTFULLINPUTMETHODSUPPORT in {q}/qtdefines.inc")
    elif rc != 0:
        for q in was_on:
            set_define(q, True)
    if rc == 0:
        print(f"OK: JPSupport patches ({target}) are in place.")
    return rc


if __name__ == "__main__":
    sys.exit(main())

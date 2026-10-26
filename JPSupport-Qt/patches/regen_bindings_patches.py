#!/usr/bin/env python3
"""Regenerate the Qt5/Qt6 bindings patches from the working trees.

The working trees keep QTFULLINPUTMETHODSUPPORT enabled (for testing).
The generated patches ship it DISABLED, as agreed with the Qt maintainer.
The working trees are always restored afterwards.
"""
import os, subprocess, sys

BASE = os.path.expanduser("~/Projects/JPSupport/JPSupport-Qt")
SETS = {"upstream": "lazarus-main", "lazarus_4_8": "lazarus-4_8"}
DEF_ON = "{$DEFINE QTFULLINPUTMETHODSUPPORT}"
DEF_OFF = "{.$DEFINE QTFULLINPUTMETHODSUPPORT}"
OLD_C = "(cbindings/src/qevent_c.cpp).}"
NEW_C = ("(cbindings/src/qevent_c.cpp).\n"
         "   Disabled by default: enabling it requires rebuilding libQtNPas.}")
MODS = {"5": "qt56.pas", "6": "qt62.pas"}

def run(args, cwd, env=None, ok=(0,)):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                       env=env)
    if r.returncode not in ok:
        print(r.stderr); sys.exit(f"command failed: {args}")
    return r

def check_apply(tree, patch, ref, tag):
    r = subprocess.run(["git", "rev-parse", "--verify", "-q", ref],
                       cwd=tree, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"    ({tag}: {ref} not available, skipped)")
        return
    idx = f"/tmp/idx_regen_{os.getpid()}"
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    run(["git", "read-tree", ref], tree, env)
    r = subprocess.run(["git", "apply", "--cached", "--check", patch],
                       cwd=tree, capture_output=True, text=True, env=env)
    print(f"    {tag} ({ref}): {'OK' if r.returncode == 0 else 'FAIL'}")
    if r.returncode != 0:
        print(r.stderr)
    if os.path.exists(idx):
        os.remove(idx)

for setname, treename in SETS.items():
    tree = os.path.join(BASE, treename)
    for q, mod in MODS.items():
        inc = os.path.join(tree, f"lcl/interfaces/qt{q}/qtdefines.inc")
        patch = os.path.join(BASE, "patches", setname,
                             f"jpsupport-qt-qt{q}-bindings.patch")
        files = [f"lcl/interfaces/qt{q}/cbindings/src/qevent_c.cpp",
                 f"lcl/interfaces/qt{q}/cbindings/src/qevent_c.h",
                 f"lcl/interfaces/qt{q}/{mod}",
                 f"lcl/interfaces/qt{q}/qtdefines.inc",
                 f"lcl/interfaces/qt{q}/qtwidgets.pas"]
        old_patch = open(patch, encoding="utf-8").read()
        header = ""
        for line in old_patch.splitlines(keepends=True):
            if line.startswith("diff --git"):
                break
            header += line
        orig = open(inc, encoding="utf-8").read()
        assert orig.count(DEF_ON) == 1 and orig.count(OLD_C) == 1, inc
        try:
            tmp = orig.replace(DEF_ON, DEF_OFF).replace(OLD_C, NEW_C)
            open(inc, "w", encoding="utf-8").write(tmp)
            body = run(["git", "diff", "HEAD", "--"] + files, tree).stdout
        finally:
            open(inc, "w", encoding="utf-8").write(orig)
        open(patch, "w", encoding="utf-8").write(header + body)
        n = body.count("\ndiff --git") + (1 if body.startswith("diff --git") else 0)
        print(f"{setname} / Qt{q}: {n} files")
        check_apply(tree, patch, "HEAD", "pristine base")
        if setname == "upstream":
            check_apply(tree, patch, "origin/main", "current main")

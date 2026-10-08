# upstream/ — reference patches for upstream review

These are review snapshots for **Lazarus main**, generated for human
review (e.g. by Lazarus maintainers on the forum). The four patches
depend on each other (for example the Qt bindings use the messages
defined in `jpsupport-qt-lmessages.patch`), so they are meant to be
applied together, not one at a time.

A matching set for the **Lazarus 4.8 release** lives in
`../lazarus_4_8/`.

**To actually build and test JPSupport-Qt, use the script:**

```bash
cd /path/to/lazarus-src
python3 /path/to/JPSupport-Qt/patches/apply_jpsupport_patches.py qt5   # or qt6, or both
```

The script picks the patch set (4.8 or main) that applies completely to
your tree, skips patches that are already applied, and changes nothing
if any needed patch does not apply.

## Files

Generated against Lazarus main (e5ece2347d, 2026-10-04) after the
TPaintBox overlay was replaced by real-text insertion (the same
approach as `LazSynImeFull` on Windows). Tested on Debian arm64
(Qt 5.15 and Qt 6.2, fcitx5 + Mozc).

- `jpsupport-qt-lmessages.patch` - `lcl/lmessages.pp` only
  (`LM_IM_SET_PREEDIT`, `TIMEPreeditInfo` and related types).
- `jpsupport-qt-lazsynime-refactor.patch` - SynEdit side:
  `lazsynimmbase.pas`, the new `lazsynqtimm.pas`, `synedit.pp`.
- `jpsupport-qt-qt6-bindings.patch` - Qt6 side: cbindings
  (`qevent_c.cpp/.h`), `qt62.pas`, `qtwidgets.pas`. Needs `libQt6Pas`
  rebuilt.
- `jpsupport-qt-qt5-bindings.patch` - the same change for the Qt5
  widgetset (`qevent_c.cpp/.h`, `qt56.pas`, `qtwidgets.pas`). Needs
  `libQt5Pas` rebuilt.

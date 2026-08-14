# upstream/ — reference patches for upstream review

The files in this directory are **not meant to be applied standalone**
to a clean Lazarus checkout. They are plain `git diff` snapshots,
generated for human review (e.g. by Lazarus maintainers on the forum),
showing a specific slice of the change history — not the full set of
changes needed to build JPSupport-Qt from scratch.

**To actually build and test JPSupport-Qt, use the full patch script
instead:**

```bash
python3 patches/apply_jpsupport_patches.py qt5   # or qt6, or both
```

run against a clean Lazarus `fixes_4` checkout. The script applies
every required change (including `lmessages.pp`, which most of the
files in this directory assume is already patched) in the correct
order.

## Files

- `jpsupport-qt-lazsynime-refactor.patch` — diff of the `LazSynIme`
  subclass refactor (`f379582c5f` → `aa0befe860`), covering
  `lazsynimmbase.pas`, the new `lazsynqtimm.pas`, and `synedit.pp`
  only. Posted for Martin_fr's review of the SynEdit-side design;
  does not include the earlier `lmessages.pp` patch or any of the
  Qt5/Qt6 cbindings changes.

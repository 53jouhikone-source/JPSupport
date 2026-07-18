# JPSupport-Qt

Patches that add Japanese (and other CJK language) input support to SynEdit, the source editor component of Lazarus (FreePascal), for the Qt5 and Qt6 widgetsets.

A sister project to [JPSupport](https://github.com/53jouhikone-source/JPSupport) (the GTK2 version).

## Why Qt5 and Qt6

For a long time, Lazarus's primary widgetset (the underlying rendering toolkit) has been GTK2. But GTK2 development has ended, and its successor, GTK3, is clearly behind Qt5/Qt6 when it comes to input method support. Clinging to GTK2 is not good for the future of Lazarus itself.

Having worked on the GTK2 version of JPSupport, we started this Qt5/Qt6 effort out of that same sense of urgency. This project is a first step in that direction. It's still rough around the edges in places (see below), but Qt's input method API is an officially supported mechanism with a much longer expected lifespan than the now-deprecated mechanism the GTK2 version relies on. Rather than aiming for "perfect right now," our goal is to bring Japanese input to Qt5/Qt6 Lazarus on par with (or better than) the GTK2 version, as a foundation we can keep improving.

## What's Implemented

Tested and confirmed working with Fcitx5 + Mozc:

- **Accurate commit handling**: multi-character conversion results are correctly reflected (previously, some characters could be dropped)
- **IME toggle keys**: both `Ctrl+Space` and `Zenkaku-Hankaku` work correctly
- **Cursor-following candidate window**: the conversion candidate list appears right next to where you're typing (previously it was stuck at a fixed position)
- **Preedit (composing) text display**: the text you're currently converting is actually shown on screen (previously nothing was shown at all)
- **Segment (bunsetsu) highlighting**: the segment you're currently editing is clearly shown in cyan text with a bold underline
- **Cursor tracking during segment navigation**: moving between segments with `Left`/`Right` and `Shift+Left`/`Right` correctly moves this highlight along with it

We've confirmed the display quality holds up well against common Linux apps such as Gedit.

## Getting Started

Two options are available.

### Option 1: Try it with Docker (if you just want to take a look)

Launch a pre-built environment without touching your existing Lazarus setup at all. If you're not very comfortable with the command line, we'd recommend starting here to get a feel for it.

```bash
cd docker
./run-jpsupport-qt5-ubuntu.sh   # Try the Qt5 version
# or
./run-jpsupport-qt6-ubuntu.sh   # Try the Qt6 version
```

The first run takes a while (building Lazarus itself, among other things) - anywhere from a few minutes to tens of minutes depending on your hardware. Subsequent runs start quickly thanks to caching.

### Option 2: Install it into your own Lazarus setup (if you want to actually use it)

**To be upfront about it: unlike the "just install a package" simplicity of the GTK2 version of JPSupport, this requires rebuilding Lazarus itself from source.** This path is for people who are reasonably comfortable with development tools and have some time to spare. If you just want to try it quickly, Option 1 above is the way to go.

For those who still want to give it a shot, here are honest, hands-on-tested instructions and caveats.

#### Before you start

- **You'll be building a new, separate copy of Lazarus from source, alongside your existing installation** - not overwriting it
- **You'll need a full set of development tools installed.** On Debian/Ubuntu-based systems these come from `apt`, but expect a fair amount of disk space and build time (tens of minutes on a Raspberry Pi is typical)
- **You'll need to overwrite a system library that Qt uses for its display features.** This normally doesn't affect your existing setup, but it's not the tidiest thing to do from a package-management standpoint. If you're cautious, back things up first
- **Watch out for a configuration conflict.** On first launch, Lazarus may warn you that its configuration conflicts with an existing installation. **Do not choose "update" or "use as-is" at that point** - doing so risks corrupting your existing Lazarus installation's configuration. See the steps below for the safe way to handle this

#### Steps

1. Install the necessary tools (Qt development packages, Japanese input-related packages, etc.). See `docker/Dockerfile.ubuntu` (Qt5) or `docker/Dockerfile.qt6.ubuntu` (Qt6) for the specific package names

2. Get a fresh copy of the Lazarus source, in a new location

```bash
   git clone --branch fixes_4 https://gitlab.com/freepascal.org/lazarus/lazarus.git lazarus-src
```

3. Move into that folder and apply the patches (specify `qt5`, `qt6`, or both)

```bash
   cd lazarus-src
   python3 /path/to/JPSupport-Qt/patches/apply_jpsupport_patches.py qt5
```

4. Rebuild the Qt binding library (example for Qt5)

```bash
   cd lcl/interfaces/qt5/cbindings
   qmake Qt5Pas.pro
   make
   sudo cp -P libQt5Pas.so* /usr/lib/aarch64-linux-gnu/   # path varies by system
   sudo ldconfig
```

5. Build Lazarus itself (this step takes a while)

```bash
   cd ../../../..
   make bigide LCL_PLATFORM=qt5
```

6. **Launch it with a dedicated config path, so it doesn't clash with your existing setup. This is the single most important step.**

```bash
   ./lazarus --pcp=~/.lazarus_jpsupport_qt5
```

   If you launch without `--pcp` and see a warning about a conflicting configuration, choose "Abort". Proceeding could overwrite your existing Lazarus installation's settings.

From then on, always launch with this `--pcp` option, and you'll have a Japanese-input-capable installation that lives entirely independently of your existing Lazarus setup.

## Technical Notes (for developers)

- Lazarus: developed and tested against the `fixes_4` branch (the 4.8/4.9 series, the latest stable line as of this writing)
- Widgetset: both Qt5 and Qt6 are supported
- Input method: tested with Fcitx5 + Mozc (other IMEs untested)
- Test environments: Ubuntu 24.04 (Docker/ARM64, on Raspberry Pi 4/5), and Debian 12 (bare-metal Raspberry Pi 4, verified via the direct-build "Option 2" path)

- **Why C++ extensions to `libQt5Pas`/`libQt6Pas` were needed**: `QInputMethodEvent::attributes()` (segment/bunsetsu boundaries, cursor position, etc.) was not exposed by Lazarus's bundled bindings at all, so we added accessor functions directly on the C++ side
- **Why the preedit string is never inserted into the text buffer**: to avoid polluting undo history and triggering unnecessary syntax-highlighting recalculation, we use a `TPaintBox` overlay for rendering instead
- **About `SlotInputMethodQuery`'s `Result`**: `QEvent::InputMethodQuery` can ask about several things at once, so `Result` must not be set to `True` unconditionally just because we answered one of them - doing so suppresses Qt's own handling of the others (notably `Qt::ImEnabled`), breaking IME activation entirely. See the in-code comments for details

## Known Limitations / Untested

- Input methods other than Fcitx5 + Mozc (e.g. ibus) are untested
- Widgetsets other than Qt5/Qt6 (e.g. GTK3) are not covered (see [JPSupport](https://github.com/53jouhikone-source/JPSupport) for GTK2)
- Ruby and Surrounding-Text attributes are not handled
- The "Option 2" installation process is not yet polished (packaging/an installer is a future goal)

## Future Direction

This project also serves as a working proof-of-concept toward an upstream contribution to Lazarus itself (a bug report / merge request). We believe the best outcome would be for this to eventually be merged upstream, so that anyone using Qt5/Qt6 Lazarus gets this out of the box, with no extra steps required.

## License

MIT License, same as the main [JPSupport](https://github.com/53jouhikone-source/JPSupport) project. See `LICENSE` at the repository root.

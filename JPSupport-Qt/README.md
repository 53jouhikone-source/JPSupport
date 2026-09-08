# JPSupport-Qt

Patches that add Japanese (and other CJK language) input support to SynEdit, the source editor component of Lazarus (FreePascal), for the Qt5 and Qt6 widgetsets.

A sister project to [JPSupport](https://github.com/53jouhikone-source/JPSupport) (the GTK2 version).

## Why Qt5 and Qt6

For a long time, Lazarus's primary widgetset (the underlying rendering toolkit) has been GTK2. But GTK2 development has ended, and its successor, GTK3, is clearly behind Qt5/Qt6 when it comes to input method support. Clinging to GTK2 is not good for the future of Lazarus itself.

Having worked on the GTK2 version of JPSupport, we started this Qt5/Qt6 effort out of that same sense of urgency. This project is a first step in that direction. It's still rough around the edges in places (see below), but Qt's input method API is an officially supported mechanism with a much longer expected lifespan than the now-deprecated mechanism the GTK2 version relies on. Rather than aiming for "perfect right now," our goal is to bring Japanese input to Qt5/Qt6 Lazarus on par with (or better than) the GTK2 version, as a foundation we can keep improving.

## What's Implemented

SynEdit is a widely used component, not just in the Lazarus IDE itself but in third-party Pascal editors as well. Despite that, languages like Japanese that rely on an IME for committing text have long been poorly supported. Composing text wasn't shown at all. Committed characters could be dropped. The candidate window only ever appeared at a fixed position on screen, with no way to tell what you were actually converting. These aren't minor annoyances - for Japanese speakers, they made the editor genuinely unusable for real work. As a result, many Japanese speakers have resorted to writing Japanese text in a separate editor and pasting it in, or simply ruled out Lazarus entirely whenever Japanese input was needed.

The goal of this project isn't to patch over individual bugs one at a time. It's to bring Japanese input, on Qt5/Qt6 - a widgetset with a long official-support runway ahead of it - up from "sort of works" to "just as usable as any other language."

Tested and confirmed working with Fcitx5 + Mozc:

- **Accurate commit handling**: multi-character conversion results are correctly reflected (previously, some characters could be dropped)
- **IME toggle keys**: both `Ctrl+Space` and `Zenkaku-Hankaku` work correctly
- **Cursor-following candidate window**: the conversion candidate list appears right next to where you're typing (previously it was stuck at a fixed position)
- **Preedit (composing) text display**: the text you're currently converting is actually shown on screen (previously nothing was shown at all)
- **Segment (bunsetsu) highlighting**: the segment you're currently editing is clearly shown in cyan text with a bold underline (a feature the GTK2 version doesn't have)
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

#### Using the GUI wizard (recommended)

The `wizard/` folder contains a Lazarus/LCL GUI tool that automates everything below, with no terminal work required. One button ("Install & Build") handles everything from installing the required packages to building Lazarus itself.

- Switch between Qt5 and Qt6 with the "Build Target" selector
- The "Advanced options" section lets you try a Lazarus version other than the verified default (we recommend sticking with the default for normal use)
- To rebuild from scratch, manually delete the relevant folder (e.g. `wizard/jpsupport-qt-build-qt5`) in a terminal, then run the wizard again
- Two maintenance scripts are also provided: `patches/bump_default_version.sh` (for developers updating the project's official default version) and `wizard/reset_wizard_state.sh` (for resetting local build state)

The instructions below are for those who'd rather do it by hand.

#### Doing it by hand

For those who still want to give it a shot manually, here are honest, hands-on-tested instructions and caveats.

##### Before you start

- **You'll be building a new, separate copy of Lazarus from source, alongside your existing installation** - not overwriting it. The process itself isn't difficult: install the required tools via `apt`, then run the included script once. Everything from fetching the source to finishing the build happens automatically (no manual file editing or GUI steps needed). That said, since it builds all of Lazarus from source, it does take a fair amount of time (see below)
- **You'll need a fair amount of disk space and time** (around 20-25 minutes in our own testing, though this varies by hardware)
- **You'll need to overwrite a system library that Qt uses for its display features.** This normally doesn't affect your existing setup, but it's not the tidiest thing to do from a package-management standpoint. If you're cautious, back things up first
- **Watch out for a configuration conflict.** On first launch, Lazarus may warn you that its configuration conflicts with an existing installation. **Do not choose "update" or "use as-is" at that point** - doing so risks corrupting your existing Lazarus installation's configuration. See the steps below for the safe way to handle this

##### Steps

1. Install the necessary tools. If you're not sure whether you want Qt5 or Qt6 (or want to try both), it's fine to install everything up front - the packages don't conflict with each other.

   ```bash
   sudo apt install -y build-essential gdb git python3 fpc fpc-source \
       qtbase5-dev qt5-qmake qtchooser libqt5x11extras5-dev \
       libqt5pas-dev libqt5pas1 fcitx5 fcitx5-frontend-qt5 \
       fcitx5-frontend-gtk3 fonts-noto-cjk qt6-base-dev
   ```

   To use Japanese input with the Qt6 build, you'll also need to build `fcitx5-qt` from source (Ubuntu 22.04 doesn't ship an `fcitx5-frontend-qt6` package). This only needs to be done **once for the whole system** - you won't need to redo it on subsequent rebuilds. See "4.2 Nothing happens when pressing the conversion key with Fcitx5 + Qt6" in `docs/troubleshooting.md` for the steps.

2. Run `patches/build_jpsupport_qt.sh`. It automates the whole flow - fetching the source, applying patches, rebuilding the Qt binding library, and building Lazarus itself

   ```bash
   ./patches/build_jpsupport_qt.sh qt5
   # or
   ./patches/build_jpsupport_qt.sh qt6
   ```

   This took around 20-25 minutes in our own testing (varies by hardware). When it's done, it prints the exact command you need to launch it with.

   **If you want to try both Qt5 and Qt6**, just run this script separately for each. The build directories (`jpsupport-qt-build-qt5/`, `jpsupport-qt-build-qt6/`) are automatically kept separate per version, so both can coexist.

3. **Launch it with a dedicated config path, so it doesn't clash with your existing setup. This is the single most important step** (the script's output also shows you this command, matching whichever version you actually built)

```bash
   ./lazarus --pcp=~/.lazarus_jpsupport_qt5
   # or, for the Qt6 build
   ./lazarus --pcp=~/.lazarus_jpsupport_qt6
```

   If you launch without `--pcp` and see a warning about a conflicting configuration, choose "Abort". Proceeding could overwrite your existing Lazarus installation's settings.

From then on, always launch with this `--pcp` option, and you'll have a Japanese-input-capable installation that lives entirely independently of your existing Lazarus setup.

##### Checking it works

Once Lazarus is up, click into the source editor and press `Zenkaku-Hankaku` (or `Ctrl+Space`). If you see a reaction, you're most of the way there - type something and confirm Japanese text shows up.

The segment you're currently converting is shown in cyan with a bold underline. See [What's Implemented](#whats-implemented) above for the full picture of what's supported.

You only need to install once - after that, just launch Lazarus with the `--pcp` option to get Japanese input.

If nothing happens when you press the conversion key, check `docs/troubleshooting.md`. In particular, right after restarting the Fcitx5 daemon, or on the first launch with this `--pcp` path, there can be a brief delay of a few tens of seconds before things respond (see that document for details).

## Technical Notes (for developers)

- Lazarus: developed and tested against `lazarus_4_8` (the official release from June 10, 2026). See `docs/upstream-status.md` for details on why this tag was chosen
- Widgetset: both Qt5 and Qt6 are supported
- Input method: tested with Fcitx5 + Mozc (other IMEs untested)
- Test environments: Ubuntu 22.04 (VMware x86_64/XFCE, both Qt5 and Qt6 verified on real hardware), and Debian 12 (bare-metal Raspberry Pi 4, aarch64, both Qt5 and Qt6 verified)
- To try a Lazarus version other than the verified default, use the `--lazarus-version=<tag>` option (e.g. `./patches/build_jpsupport_qt.sh qt5 --lazarus-version=lazarus_4_6`). **This is intended for developers verifying compatibility with new releases, and is not guaranteed to work.** The current verified default can be checked with `./patches/build_jpsupport_qt.sh --show-version`

- **Why C++ extensions to `libQt5Pas`/`libQt6Pas` were needed**: `QInputMethodEvent::attributes()` (segment/bunsetsu boundaries, cursor position, etc.) was not exposed by Lazarus's bundled bindings at all, so we added accessor functions directly on the C++ side
- **Why the preedit string is never inserted into the text buffer**: to avoid polluting undo history and triggering unnecessary syntax-highlighting recalculation, we use a `TPaintBox` overlay for rendering instead
- **About `SlotInputMethodQuery`'s `Result`**: `QEvent::InputMethodQuery` can ask about several things at once, so `Result` must not be set to `True` unconditionally just because we answered one of them - doing so suppresses Qt's own handling of the others (notably `Qt::ImEnabled`), breaking IME activation entirely. See the in-code comments for details

## Known Limitations / Untested

- IBus + Mozc has also been tested and works, but with some limitations compared to Fcitx5 + Mozc (see `docs/verification-matrix.md` for details)
  - `Ctrl+Space` does not work (Lazarus IDE itself hardcodes this key combination as its Code Completion shortcut. `Zenkaku-Hankaku` is unaffected and works fine)
  - The candidate window stays fixed at the top-left of the screen and does not follow the cursor. This is a known upstream Qt bug ([ibus/ibus#2391](https://github.com/ibus/ibus/issues/2391)), not something we can fix on our end
- Widgetsets other than Qt5/Qt6 (e.g. GTK3) are not covered (see [JPSupport](https://github.com/53jouhikone-source/JPSupport) for GTK2)
- Ruby and Surrounding-Text attributes are not handled
- The GUI wizard is still in the field-testing stage; unexpected environments or operation sequences may reveal issues (the manual steps above are kept as a fallback)

## Future Direction

This project also serves as a working proof-of-concept toward an upstream contribution to Lazarus itself (a bug report / merge request). We believe the best outcome would be for this to eventually be merged upstream, so that anyone using Qt5/Qt6 Lazarus gets this out of the box, with no extra steps required.

## License

MIT License, same as the main [JPSupport](https://github.com/53jouhikone-source/JPSupport) project. See `LICENSE` at the repository root.

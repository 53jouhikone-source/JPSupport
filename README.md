# JPSupport

A package that enables Japanese text input in the Lazarus source editor on Linux.

## What is this?

On Linux, Lazarus does not support Japanese text input directly in the source code editor.

By installing JPSupport, this problem is resolved, allowing you to naturally input Japanese comments and strings in the source editor.

## Features

- Underline displayed under text being converted (preedit)
- Candidate window appears near the cursor
- Works correctly even with multiple files open in tabs

## Requirements

- OS: Linux (Debian, Ubuntu, etc.)
- Lazarus 2.2.6 or later
- Free Pascal Compiler 3.2.2 or later
- GTK2 backend
- Japanese input: Fcitx5 or IBus (Mozc recommended)
- Confirmed working:
  - Raspberry Pi 4 (ARM64) / Debian 12 / Lazarus 2.2.6 / Fcitx5 + Mozc
  - Raspberry Pi 4 (ARM64) / Debian 12 / Lazarus 2.2.6 / IBus + Mozc
  - Raspberry Pi 5 (ARM64) / Debian 12 / Lazarus 2.2.6 / Fcitx5 + Mozc
  - VMware Debian 12 (x86_64) / Lazarus 2.2.6 / IBus + Mozc
  - VMware Debian 12 (x86_64) / Lazarus 2.2.6 / Fcitx5 + Mozc

## Installation

### Preparation

Copy the files in the `package` folder of this repository to a suitable location on your computer.

### Steps

Lazarus has a package system for adding features. JPSupport uses this system. You need to install two packages in order.

**First package (JPSupport):**

1. Launch Lazarus
2. Click "Package" → "Open Package File (.lpk)" in the top menu
3. Find and open `JPSupport.lpk`
4. A small "Package" window will open
5. Click the "Compile" button
6. Click the "Install" button
7. Click "Yes" when asked to confirm
8. Lazarus will automatically rebuild (this may take a few minutes)

**Second package (JPSupportIDE):**

After Lazarus restarts, follow the same steps to install `JPSupportIDE.lpk`.

### Verification

After Lazarus restarts following the second installation, click in the source editor and try typing Japanese. If the candidate window appears, the installation was successful.

## Technical Details (for developers)

JPSupport uses GTK2's `gtk_key_snooper_install` to globally intercept key events and forward them to a custom GtkIMContext. Since the standard Lazarus build compiles `synedit.ppu` without the `Gtk2IME` flag, Japanese input is not normally possible. JPSupport resolves this without modifying Lazarus internals.

Key files:
- `JPSupportAdapter.pas` — Core adapter class
- `JPSupportIDEMain.pas` — Lazarus integration
- `JPSupportUnit.pas` — Standalone component

## Known Limitations

- GTK2 backend only (GTK3 and Qt versions not supported)
- IBus and Fcitx5 confirmed working

## License

MIT License

If you modify or redistribute this package, the author would appreciate being informed (not obligatory). Bug reports and feedback are welcome.

## Author

Shortcut (53jou.hikone@gmail.com)

Developed with the assistance of Claude (Anthropic), ChatGPT (OpenAI), and Gemini (Google).

## Acknowledgements

- Referenced GTK2 IME implementation from ATSynEdit
- Thanks to the Lazarus and Free Pascal communities

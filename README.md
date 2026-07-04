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

Install two packages in order.

**First package (JPSupport):**

1. Launch Lazarus
2. Click "Package" → "Open Package File (.lpk)" in the top menu
3. Find and open `JPSupport.lpk` (located in the JPSupport folder)
4. A small window will open — click "Compile"
5. When the message "Compile package JPSupport 1.0: Success" appears at the bottom, compilation is complete
6. Click "Use" → "Install"
7. Click "Yes" when asked "Rebuild Lazarus?"
8. The screen will temporarily disappear as Lazarus rebuilds (this may take a few minutes — this is normal)

**Second package (JPSupportIDE):**

After Lazarus restarts, close the JPSupport package window and follow the same steps to install `JPSupportIDE.lpk` (closing the window is optional but recommended to avoid confusion).

### Verification

After the second restart, click in the source editor and press the input method toggle key (usually the key between Escape and 1). If it responds, you are almost done — type some text and confirm that Japanese characters appear.

Installation is required only once. Japanese input will be available every time you launch Lazarus.

## Technical Details (for developers)

JPSupport uses GTK2's `gtk_key_snooper_install` to globally intercept key events and forward them to a custom GtkIMContext. Since the standard Lazarus build compiles `synedit.ppu` without the `Gtk2IME` flag, Japanese input is not normally possible. JPSupport resolves this without modifying Lazarus internals.

Key files:
- `JPSupportAdapter.pas` — Core adapter class
- `JPSupportIDEMain.pas` — Lazarus integration
- `JPSupportUnit.pas` — Standalone component

## Troubleshooting

If Japanese input is not working, use `tools/JPSupportCheck` to diagnose your environment.

Launch Lazarus first, then run the following from a terminal:

```bash
~/Projects/JPSupport/tools/JPSupportCheck
```

It automatically checks items ① through ⑤ and displays hints if any problems are found.

## Known Limitations

- GTK2 backend only (GTK3 and Qt versions not supported)
- IBus and Fcitx5 confirmed working

## Note for Chinese and Korean Users

Since JPSupport uses `gtk_key_snooper_install` to globally intercept key events and forward them to a custom GtkIMContext, this approach should also work in principle for Chinese and Korean input methods (such as Fcitx5/IBus with Pinyin or Hangul). Feedback from Chinese and Korean users would be very welcome.

## License

MIT License

If you modify or redistribute this package, the author would appreciate being informed (not obligatory). Bug reports and feedback are welcome.

## Author

Shortcut (53jou.hikone@gmail.com)

Developed with the assistance of Claude (Anthropic), ChatGPT (OpenAI), and Gemini (Google).

## Acknowledgements

- Referenced GTK2 IME implementation from ATSynEdit
- Thanks to the Lazarus and Free Pascal communities

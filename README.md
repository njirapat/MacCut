# MacCut

Cut and paste files in Finder with **⌘X** and **⌘V**, the same way as Ctrl+X on Windows.

MacCut is a small menu bar app. It runs entirely on your Mac and never connects to the network.

## Features

- **⌘X, then ⌘V** in Finder moves files and folders. If you cut and never paste, nothing moves.
- **Text editing still works.** While renaming a file or typing in the search field, ⌘X cuts text as usual.
- **Menu bar status.** The icon shows when a cut is waiting to be pasted.
- **Reliable Mode.** If another app (a password manager, a browser) intercepts ⌘X or ⌘V, switch to Reliable Mode: MacCut asks Finder to move the items directly instead of sending keystrokes.
- **Safe replace.** In Reliable Mode, a name clash asks Replace, Keep Both or Stop (with Apply to all). Replaced items go to the Trash, so they can be restored. (Finder's own scripted replace deletes them permanently.)
- **Open at Login** from the menu.
- **No network access.** No telemetry, no update checks, no accounts.
- Universal binary (Apple Silicon and Intel), macOS 14 or later.

## Install

1. Download `MacCut-x.y.z.zip` from [Releases](https://github.com/njirapat/MacCut/releases) and unzip it.
2. Move `MacCut.app` to your Applications folder.
3. MacCut is not notarized by Apple, so remove the download quarantine flag once:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacCut.app
   ```
4. Open MacCut. The guide window shows **Grant Permission**: click it and turn on MacCut in
   System Settings > Privacy & Security > **Device Control and Data Access**
   (called **Accessibility** on macOS 26 and earlier). MacCut starts within two seconds.

Reliable Mode asks for one more permission (to control Finder) the first time you use it.

## Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`). Xcode itself is not needed.

```bash
git clone https://github.com/njirapat/MacCut.git
cd MacCut
bash build.sh            # -> build/MacCut.app
bash release.sh          # -> dist/MacCut-<version>.zip
```

Each local build is signed ad hoc, so macOS treats a rebuilt app as a new app: remove MacCut from the
permission list and add it again after rebuilding.

## How it works

| Mode | ⌘X in Finder | ⌘V in Finder |
|---|---|---|
| Normal | Sent to Finder as ⌘C, and MacCut remembers the clipboard state | If the clipboard still holds the cut items, sent as ⌥⌘V (Move Item Here) |
| Reliable | MacCut records the selected items via AppleScript | MacCut tells Finder to move them to where Finder would paste |

Pressing ⌘C, or copying anything else after a cut, cancels the cut.

## Uninstall

1. Choose **Quit** from the MacCut menu, and turn off **Open at Login** first if you enabled it.
2. Move `/Applications/MacCut.app` to the Trash.
3. Remove MacCut from System Settings > Privacy & Security > Device Control and Data Access.

## Limitations

- Pasting with Edit > Paste in the menu bar does not move files. Use the keyboard shortcut.
- You must open the destination folder before pasting (standard Finder behavior).
- Builds are not notarized, so step 3 of Install is required.

## License

[MIT](LICENSE)

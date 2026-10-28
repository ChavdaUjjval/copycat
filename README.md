<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Copycat icon">
</p>

<h1 align="center">Copycat</h1>

<p align="center">
  Clipboard history for your Mac that lives in the Dock.<br>
  Everything you copy on your Mac or iPhone is kept on a shelf, ready to paste again.
</p>

<p align="center">
  <a href="#install"><img src="https://img.shields.io/badge/Install_for_Mac-one_line_in_Terminal-F5568A?style=for-the-badge&logo=apple&logoColor=white" alt="Install Copycat for Mac"></a>
  <br>
  <sub>Free · macOS 14 Sonoma or later · Apple Silicon and Intel</sub>
</p>

```bash
curl -fsSL https://raw.githubusercontent.com/ChavdaUjjval/copycat/main/install.sh | bash
```

<p align="center">
  <img src="docs/screenshot-light.png" width="380" alt="The Copycat shelf in light mode">
  &nbsp;
  <img src="docs/screenshot-dark.png" width="380" alt="The Copycat shelf in dark mode">
</p>

---

## Features

- **Open it anywhere:** click the Dock icon, or press <kbd>⌃</kbd><kbd>⌘</kbd><kbd>V</kbd> from any app.
- **Click to copy:** single-click an item, or pick one with the arrow keys and press Return. The shelf hides so you can paste as usual.
- **⌘1–⌘9:** copy one of the first nine items straight from the keyboard. Each card shows its shortcut.
- **Paste for you (optional):** turn on *Paste right after choosing an item* in Settings, and the item goes straight into the app you were using.
- **Hover actions:** pin, preview or remove an item with the buttons that appear when you point at it.
- **Quick Look:** press Space to preview text, images, videos and files at full size.
- **Undo:** removed something by mistake? Click Undo in the footer or press <kbd>⌘</kbd><kbd>Z</kbd>.
- **Several at once:** <kbd>⌘</kbd>-click or <kbd>⇧</kbd>-click items, then drag them out or press Return to copy them all.
- **iPhone copies stick around:** Universal Clipboard copies from iPhone or iPad, photos and files included, are saved the moment they arrive. Normally macOS deletes them shortly after.
- **Drag in, drag out:** drop text, photos or videos onto the shelf (or files onto the Dock icon) to keep them, and drag items out into Messages, Mail, Finder and other apps.
- **Works with every app:** web images in formats like WebP or AVIF get a PNG copy, and Live Text from photos pastes as plain text.
- **Search and filter:** start typing to search, or use the filter chips (text, media, files, iPhone), which show how many items each holds.
- **Organized:** pinned items stay at the top, and the rest are grouped into Today, Yesterday and Earlier.
- **Colour codes:** a copied hex colour such as `#F5568A` shows a swatch.
- **Right-click** an item for Copy as Plain Text, Edit Before Copying, Pin to Top, Open Link, Show in Finder and Remove.
- **Dock menu:** recent items, Wipe Clipboard, Pause Capturing, Open at Login and Settings.
- **Settings** (<kbd>⌘</kbd><kbd>,</kbd>): how long to keep items (an hour, a day, a week, a month, or until removed), how many to keep, Open at Login, the Dock badge, and auto-paste.

## Privacy

- Your history stays on your Mac, in `~/Library/Application Support/Copycat`. Copycat makes no network connections.
- Copies that password managers mark as secret or temporary are never saved (see [nspasteboard.org](http://nspasteboard.org)).
- Unpinned items are removed after a day by default; you can change this in Settings. **Wipe Clipboard** empties the clipboard and the shelf at once. Pinned items stay.
- Auto-paste is off by default. Turning it on asks for Accessibility access, which Copycat uses only to press <kbd>⌘</kbd><kbd>V</kbd> for you.

## Install

You don't need Xcode or any developer tools to install Copycat. Pick either way:

### Option 1: one line in Terminal (recommended)

Open **Terminal** (in Applications → Utilities), paste this and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/ChavdaUjjval/copycat/main/install.sh | bash
```

It downloads the latest release, puts Copycat in your Applications folder and opens it. Running it again updates Copycat to the newest version. You can [read the script](install.sh) first.

Copycat isn't notarized by Apple (that needs a paid developer account), so a copy downloaded in a web browser is blocked by macOS at first. The Terminal install avoids that.

### Option 2: download the disk image

1. [Download `Copycat.dmg`](https://github.com/ChavdaUjjval/copycat/releases/latest/download/Copycat.dmg) and open it.
2. Drag **Copycat** onto **Applications**, then eject the disk image.
3. Open Copycat from Applications. macOS says *"Copycat" Not Opened* because the app isn't notarized. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the message about Copycat. Enter your password and click **Open Anyway** again. You only do this once.

If you don't see **Open Anyway**, paste this into Terminal instead. It clears the download flag that macOS checks:

```bash
xattr -dr com.apple.quarantine /Applications/Copycat.app && open /Applications/Copycat.app
```

Either way, Copycat opens its shelf and adds itself to your Login Items, since it can only catch copies while it's running. You can turn this off in Settings or from the Dock icon's menu.

### Uninstall

Quit Copycat (right-click its Dock icon → Quit), then drag it from Applications to the Trash. To also delete your history, remove `~/Library/Application Support/Copycat`.

For iPhone copies, turn on Handoff on both the Mac and the iPhone, and sign in to the same Apple Account on both.

## Build from source

This is only for developers. To just use Copycat, see [Install](#install).

`build.sh` needs Apple's Command Line Tools. If you don't have them, it opens Apple's installer and continues when they're installed.

```bash
./build.sh
```

| Command | What it does |
| --- | --- |
| `./build.sh` | Builds a universal `build/Copycat.app` |
| `./build.sh --install` | Also installs it to `/Applications` |
| `./build.sh --package` | Also makes the installer `build/Copycat.dmg` |

The app is ad-hoc signed. The app icon and the installer artwork are drawn in code (`AppIcon.swift`, `InstallerArt.swift`), so the repository has no binary assets.

`Package.swift` is there for editors and `swift build` checks. Use `build.sh` to make the actual app bundle.

To see the shelf with sample items (the README screenshots are made this way), run:

```bash
build/Copycat.app/Contents/MacOS/Copycat --screenshot shelf.png [--dark] [--empty] [--width 360]
```

### Project layout

| File | Purpose |
| --- | --- |
| `Sources/Copycat/Clip.swift` | The clip model, reading the pasteboard, and image conversion |
| `Sources/Copycat/Store.swift` | History, copying, expiry and storage on disk |
| `Sources/Copycat/ShelfController.swift` | The shelf window: search, sections, list, keyboard, Quick Look, menus, drag and drop |
| `Sources/Copycat/ShelfChrome.swift` | Filter chips, footer and empty state |
| `Sources/Copycat/ClipRow.swift` | The card for each item, with its hover actions |
| `Sources/Copycat/Settings.swift` | Preferences, the Settings window, Open at Login and auto-paste |
| `Sources/Copycat/AppDelegate.swift` | App lifecycle, Dock menu, main menu |
| `Sources/Copycat/HotKey.swift` | The global <kbd>⌃</kbd><kbd>⌘</kbd><kbd>V</kbd> shortcut |
| `Sources/Copycat/AppMover.swift` | Offers to move the app into Applications on first launch |
| `Sources/Copycat/Screenshot.swift` | Renders the shelf with sample items (`--screenshot`) |
| `Support/Info.plist` | The app bundle's Info.plist |
| `install.sh` | The one-line installer: downloads the latest release into Applications |

### Releasing

Push a tag like `v1.0.0`. GitHub Actions builds the DMG and attaches it to a new release.

## Contributing

Issues and pull requests are welcome. Please run `./build.sh` before opening a pull request. The project builds in Swift 6 language mode with no warnings.

## License

[MIT](LICENSE)

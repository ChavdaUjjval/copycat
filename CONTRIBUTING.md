# Contributing

Issues and pull requests are welcome.

## Build

```bash
./build.sh             # build/Copycat.app (universal, macOS 14+)
./build.sh --install   # also copy it to /Applications
./build.sh --package   # also make build/Copycat.dmg
```

`build.sh` needs Apple's Command Line Tools. If they're missing, it opens Apple's installer and continues once they're installed. The project builds in Swift 6 mode with no warnings; please keep it that way.

`Package.swift` is only for editors and `swift build` checks.

To see the shelf with sample items (this is how the README screenshots are made):

```bash
build/Copycat.app/Contents/MacOS/Copycat --screenshot shelf.png [--dark] [--empty] [--width 360]
```

## Project layout

| File | Purpose |
| --- | --- |
| `Sources/Copycat/Clip.swift` | The clip model, reading the pasteboard, image conversion |
| `Sources/Copycat/Store.swift` | History, copying, undo, expiry, storage on disk |
| `Sources/Copycat/ShelfController.swift` | The shelf window: search, sections, keyboard, Quick Look, menus, drag and drop |
| `Sources/Copycat/ShelfChrome.swift` | Filter tabs, footer, empty state |
| `Sources/Copycat/ClipRow.swift` | Item rows and their hover buttons |
| `Sources/Copycat/Settings.swift` | Preferences, Settings window, Open at Login, auto-paste |
| `Sources/Copycat/AppDelegate.swift` | App lifecycle, Dock menu, main menu |
| `Sources/Copycat/HotKey.swift` | The global ⌃⌘V shortcut |
| `Sources/Copycat/AppMover.swift` | Offers to move the app into Applications |
| `Sources/Copycat/AppIcon.swift`, `InstallerArt.swift` | The app icon and disk image artwork, drawn in code |
| `Sources/Copycat/Screenshot.swift` | `--screenshot` sample renders |
| `install.sh` | The one-line installer, published at `chavdaujjval.github.io/copycat/install` |
| `scripts/update-homebrew-tap.sh` | Points the Homebrew cask at a new release |

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist`.
2. Push a tag like `v1.2.0`. GitHub Actions builds the disk image, its checksum and attestation, and publishes the release.
3. Run `scripts/update-homebrew-tap.sh 1.2.0` to point Homebrew at it.

Changes to `install.sh` on `main` go live at the short install link through the Pages workflow.

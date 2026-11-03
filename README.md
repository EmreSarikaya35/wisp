# Wisp — a featherweight Alt+Tab window switcher for macOS

Wisp brings Windows-style **Alt+Tab** to the Mac. Unlike macOS's built-in Cmd+Tab, which switches between *apps*, Wisp lists every *window*. Two Safari windows show up as two entries, and you jump straight to the one you want.

It is built to stay out of your way:

- **0% CPU when idle.** Nothing polls in the background; Wisp only wakes up when you press the shortcut.
- **~12 MB of memory**, a ~200 KB download, and no dependencies. Native Swift + AppKit (no Electron, no SwiftUI).
- The window list, previews and keyboard listener exist only while the switcher is open, and are released when it closes.

**[⬇ Download the latest release](https://github.com/EmreSarikaya35/wisp/releases/latest)** · macOS 14 Sonoma or later · Apple Silicon and Intel

## Features

- **Every window is its own entry**, ordered by most recently used, just like Windows.
- **Two looks:** window previews (thumbnails) or app icons only.
- **Option+Tab** by default, or take over **Cmd+Tab** and replace the macOS app switcher.
- **Quick tap** (press and release fast) jumps to the previous window without showing the panel.
- **Minimized and hidden windows** are listed at the end, dimmed, and restored when you pick them.
- **Current desktop or all desktops** (Spaces).
- Keyboard and mouse: hover to select, click to switch.
- Launch at login, from a tiny menu bar icon.

## Usage

| Keys | Action |
|---|---|
| Hold **Option**, press **Tab** | Open the switcher; the previous window is selected |
| **Tab** / **Shift+Tab**, **←** / **→** | Move the selection |
| Release **Option**, or **Return**, or click | Switch to the selected window |
| **Esc** | Cancel |
| Quick **Option+Tab** tap | Switch to the previous window right away |
| **Shift+Option+Tab** | Open with the last window selected |

In Cmd+Tab mode, use **Cmd** instead of **Option**.

Settings live in the menu bar icon (⧉) → **Settings…**:

| Setting | Options |
|---|---|
| Shortcut | Option+Tab (default) · Cmd+Tab |
| Show | Window previews (default) · App icons only |
| Windows from | Current desktop (default) · All desktops |
| Launch at login | Off (default) |

## Install

1. Download `Wisp.zip` from [Releases](https://github.com/EmreSarikaya35/wisp/releases/latest), unzip it, and move **Wisp.app** to **Applications**.
2. Open it. Wisp isn't notarized by Apple, so the first launch is blocked. To allow it, do one of these:
   - Open **System Settings → Privacy & Security** and click **Open Anyway** next to Wisp.
   - Or run: `xattr -dr com.apple.quarantine /Applications/Wisp.app`
3. Grant **Accessibility** when asked (System Settings → Privacy & Security → Accessibility).

### Permissions

| Permission | Why | Required |
|---|---|---|
| Accessibility | To raise a specific window and to read the shortcut keys | Yes |
| Screen Recording | Only for window previews. Without it Wisp shows app icons. | No |

Wisp makes no network connections and collects nothing.

## Known limitations

- The shortcut doesn't work while a password field is focused. macOS blocks keyboard listeners in secure input.
- **All desktops** mode relies on private macOS APIs. If a future macOS version breaks it, the option is disabled and the default mode keeps working.
- To jump to a window on another desktop, enable System Settings → Desktop & Dock → *"When switching to an application, switch to a Space with open windows for the application"*.
- Release builds are ad-hoc signed. macOS may ask for Accessibility again after you update Wisp.

## Build from source

Requires Xcode 16 or later.

```bash
git clone https://github.com/EmreSarikaya35/wisp.git
cd wisp
swift test        # unit tests
./build.sh        # builds build/Wisp.app and build/Wisp.zip (universal)
open build/Wisp.app
```

- `CONFIG=debug ./build.sh` builds a debug app that logs timings to `log stream --predicate 'subsystem == "io.github.emresarikaya35.wisp"'`.
- Set `SIGN_ID="<your identity>"` to sign with a stable certificate, so macOS keeps permissions across rebuilds.
- Set `NOTARIZE=1 NOTARY_PROFILE=<profile>` to notarize (needs a Developer ID certificate).

### Layout

| Path | Contents |
|---|---|
| `Sources/WispCore` | Pure logic: window filtering and ordering, selection, grid layout, settings. Unit tested. |
| `Sources/Wisp` | AppKit app: hotkey, event taps, panel, ScreenCaptureKit thumbnails, window activation |

## License

[MIT](LICENSE)

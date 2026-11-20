# Wisp — a featherweight Alt+Tab window switcher for macOS

Wisp brings Windows-style **Alt+Tab** to the Mac. Unlike macOS's built-in Cmd+Tab, which switches between *apps*, Wisp lists every *window*. Two Safari windows show up as two entries, and you jump straight to the one you want.

It is built to stay out of your way:

- **No idle polling.** The default shortcut is registered with macOS. Window discovery runs on demand, away from the keyboard event handler.
- A tiny download and no dependencies. Built with native Swift and AppKit.
- Icons, views and previews are loaded only for the displayed page. Wisp releases them when the switcher closes.

**[⬇ Download the latest release](https://github.com/EmreSarikaya35/wisp/releases/latest)** · macOS 14 Sonoma or later · Apple Silicon and Intel

## Features

- **Every window is its own entry**, ordered by most recently used, just like Windows.
- **Three layouts:** window previews, app icons, or a compact list with window titles and app names. The compact list runs without Screen Recording permission.
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
| **Tab** / **Shift+Tab**, **←** / **→** | Move to the next or previous window |
| **↑** / **↓** | Move between rows or through the compact list |
| Release **Option**, or **Return**, or click | Switch to the selected window |
| **Esc** | Cancel |
| Quick **Option+Tab** tap | Switch to the previous window right away |
| **Shift+Option+Tab** | Open with the last window selected |

In Cmd+Tab mode, use **Cmd** instead of **Option**.

Settings live in the menu bar icon (⧉) → **Settings…**:

| Setting | Options |
|---|---|
| Shortcut | Option+Tab (default) · Cmd+Tab |
| Show | Window previews (default) · App icons only · Compact list |
| Windows from | Current desktop (default) · All desktops |
| Launch at login | Off (default) |

## Install

1. Download `Wisp.dmg` from [Releases](https://github.com/EmreSarikaya35/wisp/releases/latest), open it, and drag **Wisp** to **Applications**.
2. Open it. Wisp isn't notarized by Apple, so the first launch is blocked. To allow it, do one of these:
   - Open **System Settings → Privacy & Security** and click **Open Anyway** next to Wisp.
   - Or run: `xattr -dr com.apple.quarantine /Applications/Wisp.app`
3. Grant **Accessibility** when asked (System Settings → Privacy & Security → Accessibility).

### Permissions

| Permission | Why | Required |
|---|---|---|
| Accessibility | To raise a specific window and to read the shortcut keys | Yes |
| Screen Recording | Enables window previews. The previews setting falls back to app icons while permission is unavailable. | No |

Wisp makes no network connections and collects nothing.

## Known limitations

- The shortcut doesn't work while a password field is focused. macOS blocks keyboard listeners in secure input.
- **All desktops** mode relies on private macOS APIs. If a future macOS version breaks it, the option is disabled and the default mode keeps working.
- In **Current desktop** mode, fullscreen windows remain available. From a fullscreen Space, Wisp also lists windows from the last normal desktop it saw on that display, or the first desktop if it started in fullscreen.
- To jump to a window on another desktop, enable System Settings → Desktop & Dock → *"When switching to an application, switch to a Space with open windows for the application"*.
- Release builds are ad-hoc signed. macOS may ask for Accessibility again after you update Wisp.

## Build from source

Requires Xcode 16 or later.

```bash
git clone https://github.com/EmreSarikaya35/wisp.git
cd wisp
swift test        # unit tests
./build.sh        # builds build/Wisp.app and build/Wisp.dmg (universal)
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

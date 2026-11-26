# Wisp — a featherweight Alt+Tab window switcher for macOS

Wisp brings Windows-style **Alt+Tab** to the Mac. Unlike macOS's built-in Cmd+Tab, which switches between *apps*, Wisp lists every *window*. Two Safari windows show up as two entries, and you jump straight to the one you want.

It is built to stay out of your way:

- **No idle polling.** The default shortcut is registered with macOS. Window discovery runs on demand, away from the keyboard event handler.
- A tiny download and no dependencies. Built with native Swift and AppKit.
- Icons, views and previews are loaded only for the displayed page. Wisp releases them when the switcher closes.

**[⬇ Download the latest release](https://github.com/EmreSarikaya35/wisp/releases/latest)** · macOS 14 Sonoma or later · Apple Silicon and Intel

## Features

- **Every window is its own entry**, ordered by most recently used, just like Windows.
- **Four layouts:** window previews, app icons, a compact list with window titles and app names, or **macOS style**, which looks like the built-in app switcher: one row of large icons on a dark rounded panel, with the name under the selected one. Only window previews need Screen Recording permission.
- **Liquid Glass** backdrop, optional and off by default: clear glass that takes its color from the wallpaper and windows behind it, like the system switcher on macOS 26, and follows the light or dark appearance. Real Liquid Glass needs macOS 26; older versions use a plain see-through panel.
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
| Show | Window previews (default) · App icons only · Compact list · macOS style |
| Liquid Glass | Off (default) |
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
- Set `SIGN_ID="<your identity>"` to sign with your own certificate, for example a Developer ID.
- Set `NOTARIZE=1 NOTARY_PROFILE=<profile>` to notarize (needs a Developer ID certificate).

### Keeping permissions across updates

macOS ties the Accessibility and Screen Recording permissions to the app's code signature. An ad-hoc signature is different in every build, so macOS used to ask again each time a new build replaced the old one.

`./build.sh` now signs with a certificate named **Wisp Local Signing**. The first run creates it in your login keychain, and every later build reuses it, so each build has the same identity and the permissions stay.

One-time steps on the Mac that builds Wisp:

1. Run `./build.sh`. When macOS asks whether `codesign` may use the key "Wisp Local Signing", enter your login password and choose **Always Allow**.
2. Install that build. Because the signature changed from ad-hoc to the certificate, macOS asks for the permissions one last time. In System Settings → Privacy & Security → Accessibility (and Screen Recording, if you use previews), remove the old **Wisp** entry with **–**, then turn Wisp on again.

After that, new builds keep their permissions. Good to know:

- Don't delete the certificate from Keychain Access. A new certificate means granting the permissions one more time. To build on another Mac with the same identity, export "Wisp Local Signing" (certificate and private key) from Keychain Access as a `.p12` file and import it there.
- If `codesign` refuses the certificate, open Keychain Access, double-click "Wisp Local Signing", and under **Trust** set **Code Signing** to **Always Trust**.
- `SIGN_ID=- ./build.sh` goes back to ad-hoc signing.

### Layout

| Path | Contents |
|---|---|
| `Sources/WispCore` | Pure logic: window filtering and ordering, selection, grid layout, settings. Unit tested. |
| `Sources/Wisp` | AppKit app: hotkey, event taps, panel, ScreenCaptureKit thumbnails, window activation |

## License

[MIT](LICENSE)

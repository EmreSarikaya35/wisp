import AppKit
import WispCore
import ServiceManagement

/// Built on demand and released on close, so it costs nothing while hidden.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let settings: Settings
    private let onClose: () -> Void
    private var window: NSWindow?
    private let shortcut = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let scope = NSPopUpButton()
    private let login = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(settings: Settings, onClose: @escaping () -> Void) {
        self.settings = settings
        self.onClose = onClose
    }

    func show() {
        if window == nil { build() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()  // activate() is only a request since macOS 14
    }

    private func build() {
        shortcut.addItems(withTitles: ["Option+Tab", "Cmd+Tab"])
        shortcut.selectItem(at: settings.shortcut == .option ? 0 : 1)
        mode.addItems(withTitles: ["Window previews", "App icons only"])
        mode.selectItem(at: settings.mode == .preview ? 0 : 1)
        scope.addItems(withTitles: ["Current desktop", "All desktops"])
        scope.selectItem(at: settings.scope == .currentSpace ? 0 : 1)
        if !Private.allSpacesAvailable {
            scope.autoenablesItems = false
            scope.item(at: 1)?.isEnabled = false
            scope.item(at: 1)?.title = "All desktops (not supported on this macOS)"
            scope.selectItem(at: 0)
        }
        login.state = settings.launchAtLogin ? .on : .off
        for c in [shortcut, mode, scope, login] as [NSControl] {
            c.target = self
            c.action = #selector(changed(_:))
        }

        var rows: [[NSView]] = [
            [label("Shortcut"), shortcut],
            [label("Show"), mode],
        ]
        if !Permissions.screenRecording {
            let note = NSTextField(labelWithString: "Previews need Screen Recording permission")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            let grant = NSButton(title: "Grant…", target: self, action: #selector(grantScreenRecording))
            grant.controlSize = .small
            let stack = NSStackView(views: [note, grant])
            rows.append([NSGridCell.emptyContentView, stack])
        }
        rows += [[label("Windows from"), scope], [label("Launch at login"), login]]

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Wisp Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
        w.contentView = content
        w.setContentSize(content.fittingSize)
        w.center()
        window = w
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    @objc private func changed(_ sender: NSControl) {
        switch sender {
        case shortcut: settings.shortcut = shortcut.indexOfSelectedItem == 0 ? .option : .command
        case mode: settings.mode = mode.indexOfSelectedItem == 0 ? .preview : .icons
        case scope: settings.scope = scope.indexOfSelectedItem == 0 ? .currentSpace : .allSpaces
        case login: setLaunchAtLogin(login.state == .on)
        default: break
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
        } catch {
            login.state = on ? .off : .on
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func grantScreenRecording() { Permissions.requestScreenRecording() }

    func windowWillClose(_ notification: Notification) { onClose() }
}

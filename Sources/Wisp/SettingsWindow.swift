import AppKit
import WispCore
import ServiceManagement

/// Built on demand and released on close, so it costs nothing while hidden.
@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let settings: Settings
    private let applyShortcut: (Shortcut) -> Bool
    private let onClose: () -> Void
    private var window: NSWindow?
    private var form: NSGridView?
    private let shortcut = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let scope = NSPopUpButton()
    private let login = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let displayModes: [Mode] = [.preview, .icons, .list]

    init(settings: Settings, applyShortcut: @escaping (Shortcut) -> Bool, onClose: @escaping () -> Void) {
        self.settings = settings
        self.applyShortcut = applyShortcut
        self.onClose = onClose
    }

    func show() {
        if window == nil { build() }
        refreshStatus()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()  // activate() is only a request since macOS 14
    }

    private func build() {
        shortcut.addItems(withTitles: ["Option+Tab", "Cmd+Tab"])
        shortcut.selectItem(at: settings.shortcut == .option ? 0 : 1)
        mode.addItems(withTitles: ["Window previews", "App icons only", "Compact list"])
        mode.selectItem(at: displayModes.firstIndex(of: settings.mode) ?? 0)
        scope.addItems(withTitles: ["Current desktop", "All desktops"])
        scope.selectItem(at: settings.scope == .currentSpace ? 0 : 1)
        if !Private.allSpacesAvailable {
            scope.autoenablesItems = false
            scope.item(at: 1)?.isEnabled = false
            scope.item(at: 1)?.title = "All desktops (not supported on this macOS)"
            scope.selectItem(at: 0)
        }
        for c in [shortcut, mode, scope, login] as [NSControl] {
            c.target = self
            c.action = #selector(changed(_:))
        }

        shortcut.setAccessibilityLabel("Shortcut")
        mode.setAccessibilityLabel("Show")
        scope.setAccessibilityLabel("Windows from")
        login.setAccessibilityLabel("Launch at login")
        let screenRecording = statusRow("Previews need Screen Recording permission", button: "Grant…",
                                        action: #selector(grantScreenRecording))
        let loginApproval = statusRow("Approval required for launch at login", button: "Open…",
                                       action: #selector(openLoginItems))
        let rows: [[NSView]] = [
            [label("Shortcut"), shortcut],
            [label("Show"), mode],
            [NSGridCell.emptyContentView, screenRecording],
            [label("Windows from"), scope],
            [label("Launch at login"), login],
            [NSGridCell.emptyContentView, loginApproval],
        ]

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
        window = w
        form = grid
        refreshStatus()
        w.center()
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private func statusRow(_ text: String, button title: String, action: Selector) -> NSStackView {
        let note = NSTextField(labelWithString: text)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        return NSStackView(views: [note, button])
    }

    private func refreshStatus() {
        let status = SMAppService.mainApp.status
        login.state = status == .enabled || status == .requiresApproval ? .on : .off
        form?.row(at: 2).isHidden = settings.mode != .preview || Permissions.screenRecording
        form?.row(at: 5).isHidden = status != .requiresApproval
        if let content = window?.contentView { window?.setContentSize(content.fittingSize) }
    }

    @objc private func changed(_ sender: NSControl) {
        switch sender {
        case shortcut:
            let requested: Shortcut = shortcut.indexOfSelectedItem == 0 ? .option : .command
            if !applyShortcut(requested) {
                shortcut.selectItem(at: settings.shortcut == .option ? 0 : 1)
                showError("Couldn’t register the shortcut", detail: "Check whether another app is using this shortcut or whether Wisp has Accessibility permission.")
            }
        case mode:
            if displayModes.indices.contains(mode.indexOfSelectedItem) { settings.mode = displayModes[mode.indexOfSelectedItem] }
            refreshStatus()
        case scope: settings.scope = scope.indexOfSelectedItem == 0 ? .currentSpace : .allSpaces
        case login: setLaunchAtLogin(login.state == .on)
        default: break
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showError("Couldn’t change Launch at login", detail: error.localizedDescription)
        }
        refreshStatus()
    }

    private func showError(_ message: String, detail: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.beginSheetModal(for: window)
    }

    @objc private func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func grantScreenRecording() { Permissions.requestScreenRecording() }

    func windowDidBecomeKey(_ notification: Notification) { refreshStatus() }
    func windowWillClose(_ notification: Notification) { onClose() }
}

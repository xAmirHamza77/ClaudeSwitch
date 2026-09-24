import AppKit
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow?
    let state = AppState.shared

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory agent (resides in Menu Bar, not in Dock)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        autoStartProxyIfActiveProfileUsesLoopback()
    }

    func autoStartProxyIfActiveProfileUsesLoopback() {
        state.refreshAll()
        if let activeId = state.activeProfileId,
           let cfg = ConfigManager.shared.loadProfile(id: activeId) {
            if cfg.inferenceGatewayBaseUrl.contains("127.0.0.1:8080") || cfg.inferenceGatewayBaseUrl.contains("localhost:8080") {
                if !ProxyManager.shared.isRunning {
                    let targetM = ProxyManager.shared.targetModel.isEmpty ? "antigravity/claude-sonnet-4-6" : ProxyManager.shared.targetModel
                    ProxyManager.shared.startProxy(
                        target: ProxyManager.shared.targetUrl,
                        localPort: ProxyManager.shared.port,
                        targetModel: targetM
                    )
                }
            }
        }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let logoPath = Bundle.main.path(forResource: "logo", ofType: "png"),
               let img = NSImage(contentsOfFile: logoPath) {
                let iconSize = NSSize(width: 18, height: 18)
                let resized = NSImage(size: iconSize)
                resized.lockFocus()
                img.draw(in: NSRect(origin: .zero, size: iconSize), from: NSRect(origin: .zero, size: img.size), operation: .copy, fraction: 1.0)
                resized.unlockFocus()
                button.image = resized
            } else {
                button.image = NSImage(systemSymbolName: "asterisk.circle.fill", accessibilityDescription: "ClaudeSwitch")
            }
            button.toolTip = "ClaudeSwitch - Model & Gateway Manager"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate (Dynamic Menu Refresh)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        state.refreshAll()

        // 1. App Title Header
        let titleItem = NSMenuItem(title: "ClaudeSwitch", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "ClaudeSwitch",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // 2. Active Profile Indicator
        let activeProfileName: String
        if let activeId = state.activeProfileId,
           let activeEntry = state.profiles.first(where: { $0.id.lowercased() == activeId.lowercased() }) {
            activeProfileName = activeEntry.name
        } else {
            activeProfileName = "None"
        }

        let profileStatusItem = NSMenuItem(title: "  Profile: \(activeProfileName)", action: nil, keyEquivalent: "")
        profileStatusItem.isEnabled = false
        menu.addItem(profileStatusItem)

        // 3. Proxy Status Indicator
        let isProxyRunning = ProxyManager.shared.isRunning
        let proxyText = isProxyRunning ? "  Proxy: Active (Port \(ProxyManager.shared.port))" : "  Proxy: Stopped"
        let proxyStatusItem = NSMenuItem(title: proxyText, action: nil, keyEquivalent: "")
        proxyStatusItem.image = NSImage(systemSymbolName: isProxyRunning ? "circle.fill" : "circle", accessibilityDescription: nil)
        proxyStatusItem.isEnabled = false
        menu.addItem(proxyStatusItem)

        // 4. Claude Desktop Status Indicator
        let isClaudeRunning = ConfigManager.shared.isClaudeRunning()
        let claudeText = isClaudeRunning ? "  Claude Desktop: Running" : "  Claude Desktop: Inactive"
        let claudeStatusItem = NSMenuItem(title: claudeText, action: nil, keyEquivalent: "")
        claudeStatusItem.image = NSImage(systemSymbolName: isClaudeRunning ? "circle.fill" : "circle", accessibilityDescription: nil)
        claudeStatusItem.isEnabled = false
        menu.addItem(claudeStatusItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Switch Profile Submenu
        let switchSubmenu = NSMenu()
        if state.profiles.isEmpty {
            let noProfiles = NSMenuItem(title: "No profiles configured", action: nil, keyEquivalent: "")
            noProfiles.isEnabled = false
            switchSubmenu.addItem(noProfiles)
        } else {
            for profile in state.profiles {
                let item = NSMenuItem(
                    title: profile.name,
                    action: #selector(didSelectProfileMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.id
                if profile.id.lowercased() == (state.activeProfileId ?? "").lowercased() {
                    item.state = .on
                } else {
                    item.state = .off
                }
                switchSubmenu.addItem(item)
            }
        }

        let switchParentItem = NSMenuItem(title: "Switch Profile", action: nil, keyEquivalent: "")
        switchParentItem.submenu = switchSubmenu
        switchParentItem.image = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: nil)
        menu.addItem(switchParentItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Proxy Toggle Action
        if isProxyRunning {
            let stopProxyItem = NSMenuItem(title: "Stop Loopback Proxy", action: #selector(toggleProxyAction), keyEquivalent: "")
            stopProxyItem.target = self
            stopProxyItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
            menu.addItem(stopProxyItem)
        } else {
            let startProxyItem = NSMenuItem(title: "Start Loopback Proxy", action: #selector(toggleProxyAction), keyEquivalent: "")
            startProxyItem.target = self
            startProxyItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
            menu.addItem(startProxyItem)
        }

        // 7. Restart Claude Desktop Action
        let restartClaudeItem = NSMenuItem(title: "Restart Claude Desktop", action: #selector(restartClaudeAction), keyEquivalent: "")
        restartClaudeItem.target = self
        restartClaudeItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(restartClaudeItem)

        menu.addItem(NSMenuItem.separator())

        // 8. Open Dashboard & Quit
        let openDashboardItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboardAction), keyEquivalent: "o")
        openDashboardItem.target = self
        openDashboardItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openDashboardItem)

        let quitItem = NSMenuItem(title: "Quit ClaudeSwitch", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    // MARK: - Actions
    @objc func didSelectProfileMenuItem(_ sender: NSMenuItem) {
        guard let profileId = sender.representedObject as? String else { return }
        state.activateProfile(id: profileId)
    }

    @objc func toggleProxyAction() {
        if ProxyManager.shared.isRunning {
            ProxyManager.shared.stopProxy()
        } else {
            ProxyManager.shared.startProxy(
                target: ProxyManager.shared.targetUrl,
                localPort: ProxyManager.shared.port,
                targetModel: ProxyManager.shared.targetModel
            )
        }
    }

    @objc func restartClaudeAction() {
        ConfigManager.shared.restartClaude()
    }

    @objc func openDashboardAction() {
        showMainWindow()
    }

    @objc func quitAppAction() {
        ProxyManager.shared.stopProxy()
        NSApp.terminate(nil)
    }

    // MARK: - Window Management
    func showMainWindow() {
        if window == nil {
            let contentView = MainView(state: state)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 750),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "ClaudeSwitch"
            win.contentView = NSHostingView(rootView: contentView)
            win.delegate = self
            win.isReleasedWhenClosed = false
            self.window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false // Prevents terminating the app, keeps running in Menu Bar!
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keeps running in the Menu Bar!
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProxyManager.shared.stopProxy()
    }
}

import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
enum SlackStatApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // Remove the default app menu entirely so macOS doesn't inject
        // system items (Settings gear, etc.) into our status item menu.
        app.mainMenu = NSMenu()
        app.run()
    }
}

/// Wraps a `ConversationItem` (value type) so it can be stored in
/// `NSMenuItem.representedObject` which requires a reference type.
private final class ConversationItemRef: @unchecked Sendable {
    let item: ConversationItem
    init(_ item: ConversationItem) { self.item = item }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    let configManager = ConfigManager()
    let stateStore: StateStore
    private var cancellables = Set<AnyCancellable>()

    override init() {
        let config = ConfigManager().load()
        self.stateStore = StateStore(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        stateStore.startPolling()
        observeStateChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateStore.stopPolling()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "number",
                accessibilityDescription: "SlackStat")
            button.imagePosition = .imageLeading
        }

        rebuildMenu()
    }

    private func observeStateChanges() {
        stateStore.$items
            .combineLatest(stateStore.$aggregated, stateStore.$sidebarSections, stateStore.$connectionStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.updateMenuBarTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem?.button else { return }

        let title = MenuBarTitle.format(aggregated: stateStore.aggregated)
        if title.isEmpty {
            // No activity — show logo icon only
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "number",
                accessibilityDescription: "SlackStat")
        } else {
            // Has unreads — show category counts, hide logo icon
            button.title = title
            button.image = nil
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Status indicator if not connected
        switch stateStore.connectionStatus {
        case .connected:
            break
        case .offline:
            let item = NSMenuItem(title: "Offline", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        case .reconnecting:
            let item = NSMenuItem(title: "Reconnecting...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        case .error(let desc):
            let item = NSMenuItem(title: "Error: \(desc)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Grouped conversation sections
        let grouped = StateStore.groupBySections(
            items: stateStore.items, sections: stateStore.sidebarSections)

        for group in grouped {
            // Section header (bold)
            let header = NSMenuItem(title: group.section.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            let headerFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            header.attributedTitle = NSAttributedString(
                string: group.section.name, attributes: [.font: headerFont])
            menu.addItem(header)

            // Conversation rows
            for item in group.items {
                let prefix = (item.type == .dm || item.type == .mpim) ? "" : "#"
                let badge = item.mentionCount > 0 ? " (\(item.mentionCount))" : ""
                let timeStr = item.latestTimestamp.map { RelativeTime.format($0) } ?? ""
                let timeDisplay = timeStr.isEmpty ? "" : "  \(timeStr)"

                let title = "  \(prefix)\(item.name)\(badge)\(timeDisplay)"
                let menuItem = NSMenuItem(
                    title: title,
                    action: #selector(openConversation(_:)),
                    keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = ConversationItemRef(item)
                menu.addItem(menuItem)
            }

            menu.addItem(.separator())
        }

        if grouped.isEmpty {
            if case .connected = stateStore.connectionStatus {
                let noItems = NSMenuItem(
                    title: "All caught up!", action: nil, keyEquivalent: "")
                noItems.isEnabled = false
                menu.addItem(noItems)
                menu.addItem(.separator())
            }
        }

        // App controls
        // NOTE: macOS auto-attaches a gear icon to menu items whose action
        // selector is named "openSettings". Using a different name avoids this.
        menu.addItem(
            NSMenuItem(
                title: "Preferences",
                action: #selector(showPrefsWindow),
                keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Quit SlackStat",
                action: #selector(quitApp),
                keyEquivalent: ""))

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc func openConversation(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? ConversationItemRef else { return }
        DeepLinkHandler.openInSlack(teamId: ref.item.teamId, channelId: ref.item.id)
    }

    @objc func showPrefsWindow() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(store: stateStore, configManager: configManager)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SlackStat Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

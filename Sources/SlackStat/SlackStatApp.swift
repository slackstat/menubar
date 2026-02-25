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
            // Skip the section header for threads — the single item already says "Threads"
            if group.section.type != "threads" {
                // Section header (bold)
                let header = NSMenuItem(title: group.section.name, action: nil, keyEquivalent: "")
                header.isEnabled = false
                let headerFont = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
                header.attributedTitle = NSAttributedString(
                    string: group.section.name, attributes: [.font: headerFont])
                menu.addItem(header)
            }

            // Conversation rows
            for item in group.items {
                let badge = item.mentionCount > 0 ? " (\(item.mentionCount))" : ""
                let timeStr = item.latestTimestamp.map { RelativeTime.format($0) } ?? ""

                // Build attributed string with inline SF Symbol icon to avoid
                // the image column that NSMenuItem.image creates.
                // Use a right-aligned tab stop to push relative time to the right edge.
                let para = NSMutableParagraphStyle()
                let rightTab = NSTextTab(textAlignment: .right, location: 250)
                para.tabStops = [rightTab]

                let titleStr = NSMutableAttributedString()
                let symbolName: String?
                switch item.type {
                case .dm, .mpim:
                    symbolName = nil
                case .thread:
                    symbolName = "text.bubble"
                default:
                    symbolName = item.isPrivate ? "lock" : "number"
                }
                if let symbolName,
                   let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    let sized = img.withSymbolConfiguration(config) ?? img
                    let attachment = NSTextAttachment()
                    attachment.image = sized
                    titleStr.append(NSAttributedString(attachment: attachment))
                    titleStr.append(NSAttributedString(string: " "))
                }
                titleStr.append(NSAttributedString(string: "\(item.name)\(badge)"))
                if !timeStr.isEmpty {
                    let dimColor = NSColor.secondaryLabelColor
                    titleStr.append(NSAttributedString(string: "\t"))
                    titleStr.append(NSAttributedString(
                        string: timeStr,
                        attributes: [.foregroundColor: dimColor]))
                }
                titleStr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: titleStr.length))

                let menuItem = NSMenuItem(title: "", action: #selector(openConversation(_:)), keyEquivalent: "")
                menuItem.attributedTitle = titleStr
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
        if ref.item.type == .thread {
            DeepLinkHandler.openSlack(teamId: ref.item.teamId)
        } else {
            DeepLinkHandler.openInSlack(teamId: ref.item.teamId, channelId: ref.item.id)
        }
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

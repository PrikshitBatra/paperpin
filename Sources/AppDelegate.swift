import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let store = BoardStore()
    let navigation = Navigation()
    private(set) var window: NSWindow!
    private(set) var statusItem: NSStatusItem!
    private(set) var popover = NSPopover()
    private var subscriptions: Set<AnyCancellable> = []
    private var hotKey: HotKey?
    private var boardIsOnDesktop = false
    private var transitioningFullScreen = false
    private var ordinaryCollectionBehavior: NSWindow.CollectionBehavior = []
    private let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        makeWindow()
        makeStatusItem()
        hotKey = HotKey { [weak self] in self?.toggleQuick() }
        applyHotKeyPreference()
        if !boardIsOnDesktop { showWindow() }
        #if PAPERPIN_QA
        runWindowChecksIfRequested(self)
        #endif
    }

    private func makeWindow() {
        let content = BoardView(store: store, navigation: navigation, openQuick: { [weak self] in self?.toggleQuick() })
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        window = BoardWindow(contentRect: NSRect(x: 0, y: 0, width: min(992, available.width - 30),
                                              height: min(710, available.height - 30)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Paperpin"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.contentView = NSHostingView(rootView: content)
        window.setAccessibilityLabel("Paperpin")
        if !window.setFrameUsingName("PaperpinBoard") { window.center() }
        window.setFrameAutosaveName("PaperpinBoard")
        ordinaryCollectionBehavior = window.collectionBehavior
        navigation.$sidebarHidden.removeDuplicates().sink { [weak self] hidden in
            self?.updateMinimumSize(sidebarHidden: hidden)
        }.store(in: &subscriptions)
        navigation.$floats.removeDuplicates().sink { [weak self] on in
            guard let self, !self.boardIsOnDesktop else { return }
            self.window.level = on ? .floating : .normal
        }.store(in: &subscriptions)
        navigation.$desktopMode.removeDuplicates().sink { [weak self] on in
            self?.applyDesktopMode(on)
        }.store(in: &subscriptions)
    }

    private func updateMinimumSize(sidebarHidden: Bool) {
        let size = sidebarHidden ? NSSize(width: 475, height: 340) : NSSize(width: 665, height: 440)
        window.minSize = size
        var frame = window.frame
        guard frame.width < size.width || frame.height < size.height else { return }
        let top = frame.maxY
        frame.size.width = max(frame.width, size.width)
        frame.size.height = max(frame.height, size.height)
        frame.origin.y = top - frame.height
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true)
    }

    private func applyDesktopMode(_ on: Bool) {
        guard !transitioningFullScreen else { return }
        if window.styleMask.contains(.fullScreen) {
            if on { window.toggleFullScreen(nil) }
            return
        }
        guard on != boardIsOnDesktop else { return }
        boardIsOnDesktop = on
        if on && window.isMiniaturized { window.deminiaturize(nil) }
        let dismissControls: NSWindow.StyleMask = [.closable, .miniaturizable]
        if on { window.styleMask.subtract(dismissControls) }
        else { window.styleMask.formUnion(dismissControls) }
        // Keep the transparent title bar for dragging and the resize edges for placement.
        window.collectionBehavior = on
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone, .fullScreenDisallowsTiling]
            : ordinaryCollectionBehavior
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = on
        }
        window.canHide = !on
        window.isExcludedFromWindowsMenu = on
        window.level = on ? desktopLevel : (navigation.floats ? .floating : .normal)
        if on { window.orderFrontRegardless() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !boardIsOnDesktop }

    func windowWillEnterFullScreen(_ notification: Notification) { transitioningFullScreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { transitioningFullScreen = true }
    func windowDidEnterFullScreen(_ notification: Notification) {
        transitioningFullScreen = false
        applyDesktopMode(navigation.desktopMode)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        transitioningFullScreen = false
        applyDesktopMode(navigation.desktopMode)
    }

    func applicationDidResignActive(_ notification: Notification) {
        if boardIsOnDesktop { window.level = desktopLevel }
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = PaperArt.menuMark
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(statusClicked)
        store.$board.combineLatest(navigation.$showsNextTask)
            .map { board, showNext -> MenuBarText in
                let task = showNext ? board.sortedNotes.lazy.compactMap { $0.tasks.first }.first : nil
                return MenuBarText(count: board.pendingCount, task: task?.displayText)
            }
            .removeDuplicates().sink { [weak button] display in
                button?.title = display.title
                button?.toolTip = "\(display.description). Click for tasks or Option-click for the board."
                button?.setAccessibilityLabel(display.description)
            }.store(in: &subscriptions)
        popover.behavior = .transient
        popover.animates = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.diskIssue != nil {
            store.retrySave()
            if store.diskIssue != nil {
                let alert = NSAlert()
                alert.messageText = "Paperpin needs attention"
                alert.informativeText = store.diskIssue ?? ""
                alert.addButton(withTitle: "Keep open")
                alert.addButton(withTitle: "Quit")
                return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
            }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) { hotKey?.unregister() }

    func showWindow() {
        popover.performClose(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        // An explicit Open Board request can reach the notes even when other windows cover them.
        if boardIsOnDesktop { window.level = .normal }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { showBoard() }
        else { toggleQuick() }
    }

    @objc func toggleQuick() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button, button.window != nil else { showBoard(); return }
        popover.contentViewController = NSHostingController(rootView:
            QuickPanel(store: store, navigation: navigation, openBoard: { [weak self] id in
                guard let self else { return }
                self.showBoard()
                if let id { self.navigation.reveal(id, editingTitle: false) }
            }, openArchive: { [weak self] in self?.showArchive() }, close: { [weak self] in self?.popover.performClose(nil) }))
        popover.contentSize = NSSize(width: 348, height: 412)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func newNote() {
        showWindow()
        navigation.reveal(store.addNote(), editingTitle: true)
    }

    @objc private func showBoard() { navigation.go(.board); showWindow() }
    @objc private func showArchive() { navigation.go(.archive); showWindow() }
    @objc private func findNotes() { showWindow(); navigation.focusRequest = FocusRequest(.search) }
    @objc private func floatBoard() { navigation.floats.toggle() }
    @objc private func toggleDesktopMode() { navigation.desktopMode.toggle() }
    @objc private func toggleSidebar() { navigation.sidebarHidden.toggle() }
    @objc private func toggleNextTask() { navigation.showsNextTask.toggle() }
    @objc private func toggleShortcut() {
        let wasOff = UserDefaults.standard.bool(forKey: "DisableQuickShortcut")
        UserDefaults.standard.set(!wasOff, forKey: "DisableQuickShortcut")
        applyHotKeyPreference()
    }

    private func applyHotKeyPreference() {
        if UserDefaults.standard.bool(forKey: "DisableQuickShortcut") {
            hotKey?.unregister()
            navigation.hotKeyAvailable = false
        } else {
            navigation.hotKeyAvailable = hotKey?.register() ?? false
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(floatBoard) {
            menuItem.state = navigation.floats && !navigation.desktopMode ? .on : .off
            return !navigation.desktopMode
        }
        if menuItem.action == #selector(toggleDesktopMode) { menuItem.state = navigation.desktopMode ? .on : .off }
        if menuItem.action == #selector(toggleSidebar) { menuItem.title = navigation.sidebarHidden ? "Show Sidebar" : "Hide Sidebar" }
        if menuItem.action == #selector(toggleNextTask) { menuItem.state = navigation.showsNextTask ? .on : .off }
        if menuItem.action == #selector(toggleShortcut) {
            menuItem.state = UserDefaults.standard.bool(forKey: "DisableQuickShortcut") ? .off : .on
        }
        return true
    }

    private func buildMenu() {
        let bar = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            top.submenu = menu
            bar.addItem(top)
            return menu
        }
        func item(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "",
                  modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let entry = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            entry.target = target
            entry.keyEquivalentModifierMask = modifiers
        }

        let appMenu = submenu("Paperpin")
        item(appMenu, "About Paperpin", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        appMenu.addItem(.separator())
        item(appMenu, "Hide Paperpin", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(appMenu, "Quit Paperpin", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = submenu("File")
        item(file, "New Sticky", #selector(newNote), "n", target: self)
        item(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("Edit")
        item(edit, "Undo", NSSelectorFromString("undo:"), "z")
        item(edit, "Redo", NSSelectorFromString("redo:"), "Z")
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, "Find…", #selector(findNotes), "f", target: self)
        let view = submenu("View")
        item(view, "Sticky Board", #selector(showBoard), "1", target: self)
        item(view, "Archive", #selector(showArchive), "2", target: self)
        item(view, "Quick Panel", #selector(toggleQuick), target: self)
        view.addItem(.separator())
        item(view, "Desktop Mode", #selector(toggleDesktopMode), target: self)
        item(view, "Hide Sidebar", #selector(toggleSidebar), "s", modifiers: [.command, .control], target: self)
        item(view, "Keep Board on Top", #selector(floatBoard), target: self)
        view.addItem(.separator())
        item(view, "Show Next Task in Menu Bar", #selector(toggleNextTask), target: self)
        item(view, "Use ⌃⌥Space for Quick Panel", #selector(toggleShortcut), target: self)
        let windows = submenu("Window")
        item(windows, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(windows, "Zoom", #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = windows
        NSApp.mainMenu = bar
    }
}

private final class BoardWindow: NSWindow {
    override func miniaturize(_ sender: Any?) {
        if styleMask.contains(.miniaturizable) { super.miniaturize(sender) }
    }
}

private struct MenuBarText: Equatable {
    let count: Int
    let task: String?

    var title: String {
        guard let task else { return " \(count)" }
        let line = task.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let preview = line.count > 24 ? String(line.prefix(23)) + "…" : line
        return " \(count) · \(preview)"
    }

    var description: String {
        let counter = "Paperpin, \(plural(count, "pending task", "pending tasks"))"
        return task.map { "\(counter). Next task, \($0)" } ?? counter
    }
}

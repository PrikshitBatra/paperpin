import AppKit
import Carbon

private func pause(_ ms: UInt64 = 230) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

private func snapshot(_ window: NSWindow, _ path: URL) {
    window.displayIfNeeded()
    if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: path)
        print("SNAP \(path.lastPathComponent) \(image.width)x\(image.height)")
    }
}

// Post normal AppKit mouse events to this process's own window. Test coordinates are
// in points from the top left of the content view and match the fixed QA window size.
private func click(_ x: CGFloat, _ y: CGFloat, in view: NSView) {
    guard let window = view.window else { return }
    let local = NSPoint(x: view.bounds.minX + x, y: view.isFlipped ? view.bounds.minY + y : view.bounds.maxY - y)
    let point = view.convert(local, to: nil)
    for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        NSApp.postEvent(event, atStart: false)
    }
}

private func key(_ string: String, _ code: UInt16, in window: NSWindow, flags: NSEvent.ModifierFlags = []) {
    for type: NSEvent.EventType in [.keyDown, .keyUp] {
        NSApp.postEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                         context: nil, characters: string, charactersIgnoringModifiers: string,
                                         isARepeat: false, keyCode: code)!, atStart: false)
    }
}

private func insert(_ value: String, in window: NSWindow) {
    print("INPUT \(type(of: window.firstResponder)) \(String(describing: window.firstResponder.map { type(of: $0) }))")
    (window.firstResponder as? NSTextInputClient)?.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0))
}

private func sendRegisteredHotKey() -> OSStatus {
    var event: EventRef?
    let result = CreateEvent(nil, UInt32(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(),
                             EventAttributes(kEventAttributeNone), &event)
    guard result == noErr, let event else { return result }
    defer { ReleaseEvent(event) }
    var id = EventHotKeyID(signature: 0x50504E31, id: 1)
    let added = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  MemoryLayout<EventHotKeyID>.size, &id)
    guard added == noErr else { return added }
    return SendEventToEventTarget(event, GetApplicationEventTarget())
}

@MainActor
private func choosePopupItem(_ title: String, at point: NSPoint, in view: NSView) async {
    let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { event in
        guard let menu = event.object as? NSMenu else { return }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            let index = menu.items.firstIndex { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
            print("MENU", menu.items.map(\.title))
            menu.cancelTracking()
            if let index {
                menu.performActionForItem(at: index)
            }
        }
    }
    defer { NotificationCenter.default.removeObserver(token) }
    click(point.x, point.y, in: view)
    await pause(420)
}

@MainActor
private func checkDesktopMode(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    let window = delegate.window!
    let navigation = delegate.navigation
    let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    let viewMenu = NSApp.mainMenu!.item(withTitle: "View")!.submenu!
    func choose(_ name: String) {
        viewMenu.update()
        let index = viewMenu.indexOfItem(withTitle: name)
        if index >= 0 { viewMenu.performActionForItem(at: index) }
    }
    func actualLayer() -> Int? {
        let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return all.first { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }?[kCGWindowLayer as String] as? Int
    }

    delegate.showWindow()
    navigation.go(.board)
    navigation.floats = true
    window.performMiniaturize(nil)
    await pause(550)
    check(window.isMiniaturized, "ordinary board can be minimized")
    choose("Desktop Mode")
    await pause(550)
    check(navigation.desktopMode && window.isVisible && !window.isMiniaturized, "Desktop Mode retrieves a minimized board")
    check(window.level.rawValue == desktopLevel && actualLayer() == desktopLevel, "WindowServer places the visible board directly above desktop icons")
    check(window.collectionBehavior.contains([.stationary, .canJoinAllSpaces, .ignoresCycle]) && !window.canHide, "desktop board stays with the desktop across Spaces")
    check(buttons.allSatisfy { window.standardWindowButton($0)?.isHidden != false }, "all window buttons disappear")
    window.performClose(nil)
    window.performMiniaturize(nil)
    window.miniaturize(nil)
    await pause()
    check(window.isVisible && !window.isMiniaturized, "close and minimize actions leave the desktop board visible")

    delegate.statusItem.button?.performClick(nil)
    await pause(350)
    if let panel = delegate.popover.contentViewController?.view {
        snapshot(panel.window!, directory.appendingPathComponent("layout-panel.png"))
        await choosePopupItem("Hide sidebar", at: NSPoint(x: 284, y: 25), in: panel)
        check(navigation.sidebarHidden, "quick-panel options hide the sidebar")
        await choosePopupItem("Show sidebar", at: NSPoint(x: 284, y: 25), in: panel)
        check(!navigation.sidebarHidden, "quick-panel options restore the sidebar")
        click(64, 394, in: panel)
    }
    await pause(350)
    check(navigation.desktopMode && !delegate.popover.isShown && window.isKeyWindow && actualLayer() == NSWindow.Level.normal.rawValue, "Open Board temporarily brings the desktop board forward")
    let before = window.frame
    key("s", 1, in: window, flags: [.command, .control])
    await pause()
    check(navigation.sidebarHidden && window.frame == before, "sidebar shortcut expands board content in place")
    window.setContentSize(.init(width: 485, height: 395))
    await pause()
    check(window.frame.width < 500, "sidebar-free board can be sized for a desktop corner")
    snapshot(window, directory.appendingPathComponent("06-compact-desktop.png"))

    await choosePopupItem("Open archive", at: NSPoint(x: window.frame.width - 183, y: 69), in: window.contentView!)
    check(navigation.section == .archive && navigation.sidebarHidden, "board layout menu opens Archive with sidebar hidden")
    key("1", 18, in: window, flags: .command)
    key("f", 3, in: window, flags: .command)
    await pause()
    insert("match", in: window)
    await pause()
    check(navigation.query == "match", "fronted desktop board accepts keyboard input")
    key("\u{1b}", 53, in: window)
    await pause()
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?
        .activate(options: [.activateIgnoringOtherApps])
    await pause(450)
    check(!NSApp.isActive && actualLayer() == desktopLevel && window.isVisible, "switching apps parks the edited board behind other windows")

    choose("Desktop Mode")
    await pause()
    check(!navigation.desktopMode && navigation.sidebarHidden && window.level == .floating && window.canHide,
          "leaving desktop mode restores previous floating preference independently of sidebar")
    check(window.styleMask.contains([.closable, .miniaturizable]) && buttons.allSatisfy { window.standardWindowButton($0)?.isHidden == false },
          "ordinary window controls return")
    choose("Show Sidebar")
    await pause()
    check(!navigation.sidebarHidden && window.frame.width >= 665, "showing sidebar from the View menu restores room for navigation")

    window.performClose(nil)
    await pause()
    check(!window.isVisible, "ordinary board can close after leaving desktop mode")
    choose("Desktop Mode")
    choose("Hide Sidebar")
    await pause()
    check(navigation.desktopMode && navigation.sidebarHidden && window.isVisible && actualLayer() == desktopLevel, "desktop mode reopens a closed board")
    check(UserDefaults.standard.bool(forKey: "DesktopMode") && UserDefaults.standard.bool(forKey: "SidebarHidden"), "both layout choices are saved")
}

@MainActor
func runWindowChecksIfRequested(_ delegate: AppDelegate) {
    guard let directory = ProcessInfo.processInfo.environment["PAPERPIN_TEST_DIRECTORY"] else { return }
    let url = URL(fileURLWithPath: directory, isDirectory: true)
    Task { @MainActor in
        await pause(600)
        let window = delegate.window!
        let view = window.contentView!
        let store = delegate.store
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print("\(ok ? "PASS" : "FAIL") \(name)"); fflush(stdout)
            if !ok { failures += 1 }
        }
        if ProcessInfo.processInfo.environment["PAPERPIN_CHECK_LAYOUT"] == "1" {
            if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
                let level = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
                check(delegate.navigation.desktopMode && delegate.navigation.sidebarHidden, "fresh process remembers both layout choices")
                check(window.isVisible && window.level.rawValue == level && !window.styleMask.contains(.closable), "fresh launch stays on desktop with controls hidden")
                check(store.board.notes.first?.body == "Layout test" && store.pendingCount == 1, "changing layout preserves saved content")
            } else {
                store.editNote(store.board.notes[0].id) { $0.body = "Layout test"; $0.draft = "One pending task" }
                store.addDraft(on: store.board.notes[0].id)
                await checkDesktopMode(delegate, directory: url, check: check)
            }
            print("FINISHED \(failures) layout failures")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
            check(store.board.notes.count == 4 && store.pendingCount == 5 && store.board.archive.count == 1, "fresh process restores notes, pending tasks, and archive")
            check(store.board.quickDraft == "Finish this draft later" && store.board.notes.contains { $0.body == "Autosaved body\nSecond line" }, "fresh process restores unsubmitted draft and multiline text")
            check(delegate.statusItem.button?.title == " 5", "menu bar starts with saved count")
            print("FINISHED \(failures) relaunch failures")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        window.setContentSize(.init(width: 950, height: 612))
        await pause()
        snapshot(window, url.appendingPathComponent("01-first.png"))
        let inbox = store.board.notes[0].id

        // The first-run inline checklist is editable before Return commits the task.
        click(321, 328, in: view); await pause()
        insert("Inbox task", in: window); await pause()
        check(BoardStore(file: store.file).note(inbox)?.draft == "Inbox task", "unsubmitted inline draft autosaved")
        key("\r", 36, in: window); await pause()
        check(store.note(inbox)?.tasks.first?.text == "Inbox task" && store.note(inbox)?.draft == "", "Return adds an inline task")

        store.editNote(inbox) { $0.title = "Today"; $0.body = "Leave room for a walk this afternoon."; $0.pinned = true; $0.tasks = []; $0.draft = "" }
        for text in ["Pick up groceries", "Send the revised draft", "Book a table for Friday"] {
            store.editNote(inbox) { $0.draft = text }; store.addDraft(on: inbox)
        }
        let errands = store.addNote()
        store.editNote(errands) { $0.title = "Weekend"; $0.body = "A few things for Saturday." }
        for text in ["Water the plants", "Return library books"] {
            store.editNote(errands) { $0.draft = text }; store.addDraft(on: errands)
        }
        let ideas = store.addNote()
        store.editNote(ideas) { $0.title = "Ideas"; $0.body = "Notes for the next design session." }
        window.makeFirstResponder(nil)
        await pause(350)
        snapshot(window, url.appendingPathComponent("02-board.png"))
        check(delegate.statusItem.button?.title == " 5", "live status count before completion")
        delegate.navigation.showsNextTask = true
        check(delegate.statusItem.button?.title == " 5 · Pick up groceries", "optional task title appears in menu bar")
        delegate.navigation.showsNextTask = false
        let finished = store.note(inbox)!.tasks[0]
        click(253, 327, in: view); await pause()
        check(store.board.archive.first?.id == finished.id && store.pendingCount == 4, "board checkbox moves task into archive")
        check(delegate.statusItem.button?.title == " 4", "live status count after completion")
        click(66, 198, in: view); await pause()
        check(delegate.navigation.section == .archive, "archive navigation control")
        snapshot(window, url.appendingPathComponent("03-archive.png"))
        click(877, 260, in: view); await pause()
        check(store.board.archive.isEmpty && store.note(inbox)?.tasks.first?.id == finished.id, "archive restore control")
        click(80, 162, in: view); await pause()

        // Cmd-N must reveal and focus the new sticky, including when existing notes are pinned.
        key("n", 45, in: window, flags: .command); await pause(400)
        check(store.board.notes.count == 4, "Command-N creates a note")
        let newID = store.board.notes[0].id
        insert("Call notes", in: window); await pause()
        check(store.note(newID)?.title == "Call notes", "new note automatically focuses its title")
        key("\r", 36, in: window); await pause()
        insert("Autosaved body", in: window); await pause()
        check(BoardStore(file: store.file).note(newID)?.body == "Autosaved body", "body typed in normal editor autosaved before blur")
        key("\r", 36, in: window); await pause()
        insert("Second line", in: window); await pause()
        check(store.note(newID)?.body == "Autosaved body\nSecond line", "Return inserts a newline in freeform notes")
        key("f", 3, in: window, flags: .command); await pause()
        insert("library books", in: window); await pause()
        check(delegate.navigation.query == "library books", "Command-F focuses search")
        key("\u{1b}", 53, in: window); await pause()
        check(delegate.navigation.query.isEmpty, "Escape clears search")

        window.performClose(nil); await pause()
        check(!window.isVisible, "close board window")
        delegate.statusItem.button?.performClick(nil); await pause(400)
        check(delegate.popover.isShown, "menu bar click with closed board")
        if let panelView = delegate.popover.contentViewController?.view, let panel = panelView.window {
            snapshot(panel, url.appendingPathComponent("04-quick.png"))
            let target = store.captureNote!.id
            let before = store.pendingCount
            insert("Quick task from panel", in: panel); await pause()
            check(BoardStore(file: store.file).board.quickDraft == "Quick task from panel", "menu panel focuses capture and autosaves draft")
            key("\r", 36, in: panel); await pause()
            check(store.note(target)?.tasks.last?.text == "Quick task from panel" && store.pendingCount == before + 1, "Return in menu panel adds to destination")
            click(29, 138, in: panelView); await pause()
            check(store.board.archive.first?.task.text == "Pick up groceries" && store.pendingCount == before, "menu panel checkbox and live count")
            click(64, 394, in: panelView); await pause()
            check(window.isVisible && !delegate.popover.isShown, "Open board button in menu panel")
        }
        if !window.isVisible { delegate.showWindow() }
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(300)
        snapshot(window, url.appendingPathComponent("05-light.png"))
        check(BoardStore(file: store.file).board == store.board, "reopened state equals final visible data")
        check(delegate.navigation.hotKeyAvailable, "global shortcut registered with macOS")
        window.performClose(nil)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?
            .activate(options: [.activateIgnoringOtherApps])
        await pause(500)
        check(!NSApp.isActive, "shortcut test starts with Paperpin inactive")
        let delivered = sendRegisteredHotKey()
        await pause(350)
        let shortcutPanel = delegate.popover.contentViewController?.view.window
        check(delivered == noErr && delegate.popover.isShown && shortcutPanel != nil, "registered hotkey handler opens the panel")
        check(NSApp.isActive && shortcutPanel?.isKeyWindow == true, "panel receives keyboard focus from another app")
        if let shortcutPanel {
            insert("Finish this draft later", in: shortcutPanel)
            await pause()
        }
        _ = sendRegisteredHotKey()
        await pause()
        check(!delegate.popover.isShown && !window.isVisible, "shortcut dismisses panel while board stays closed")
        print("FINISHED \(failures) failures")
        fflush(stdout)
        NSApp.terminate(nil)
    }
}

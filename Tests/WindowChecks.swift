import AppKit
import Carbon

func pause(_ ms: UInt64 = 230) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

@MainActor
private func awaitSave(_ store: BoardStore) async {
    let deadline = Date().addingTimeInterval(4)
    while store.saveState != .saved && store.diskIssue == nil && Date() < deadline { await pause(25) }
}

func snapshot(_ window: NSWindow, _ path: URL) {
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

func nativeEditor(in view: NSView) -> NSTextView? {
    if let editor = view as? NSTextView { return editor }
    return view.subviews.lazy.compactMap { nativeEditor(in: $0) }.first
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
@discardableResult
private func choosePopupItem(_ title: String, at point: NSPoint, in view: NSView,
                             performAction: Bool = true, inspect: ((NSMenuItem) -> Void)? = nil) async -> [String] {
    var titles: [String] = []
    let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { event in
        guard let menu = event.object as? NSMenu else { return }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            menu.update()
            let index = menu.items.firstIndex { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
            titles = menu.items.map(\.title)
            print("MENU", titles)
            if let index { inspect?(menu.items[index]) }
            menu.cancelTracking()
            if performAction, let index {
                menu.performActionForItem(at: index)
            }
        }
    }
    defer { NotificationCenter.default.removeObserver(token) }
    click(point.x, point.y, in: view)
    await pause(420)
    return titles
}

@MainActor
private func checkBoardLayout(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    let window = delegate.window!
    let navigation = delegate.navigation
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
    check(UserDefaults.standard.object(forKey: "DesktopMode") == nil && !navigation.minimalMode
          && window.level == .normal && window.canHide,
          "legacy DesktopMode preference is removed and leaves an ordinary board")
    check(viewMenu.item(withTitle: "Desktop Mode") == nil && viewMenu.item(withTitle: "Minimal Mode") != nil,
          "View menu exposes Minimal Mode without the retired Desktop Mode toggle")
    check(window.styleMask.contains([.closable, .miniaturizable])
          && buttons.allSatisfy { window.standardWindowButton($0)?.isHidden == false },
          "ordinary board retains its close minimize and zoom controls")
    choose("Keep Board on Top")
    await pause(200)
    check(navigation.floats && window.level == .floating && actualLayer() == NSWindow.Level.floating.rawValue,
          "Keep Board on Top raises the ordinary board")
    window.performMiniaturize(nil)
    await pause(550)
    check(window.isMiniaturized, "ordinary board can be minimized")
    delegate.showWindow()
    await pause(350)
    check(window.isVisible && !window.isMiniaturized && window.isKeyWindow && window.level == .floating,
          "Open Board restores a minimized board and preserves floating preference")

    delegate.statusItem.button?.performClick(nil)
    await pause(350)
    if let panel = delegate.popover.contentViewController?.view {
        snapshot(panel.window!, directory.appendingPathComponent("layout-panel.png"))
        let titles = await choosePopupItem("Hide sidebar", at: NSPoint(x: 284, y: 25), in: panel)
        check(!titles.contains(where: { $0.localizedCaseInsensitiveCompare("Desktop mode") == .orderedSame })
              && titles.contains(where: { $0.localizedCaseInsensitiveCompare("Minimal mode") == .orderedSame }),
              "quick-panel options retain Minimal Mode and omit Desktop Mode")
        check(navigation.sidebarHidden, "quick-panel options hide the sidebar")
        await choosePopupItem("Show sidebar", at: NSPoint(x: 284, y: 25), in: panel)
        check(!navigation.sidebarHidden, "quick-panel options restore the sidebar")
        click(64, 394, in: panel)
    }
    await pause(350)
    check(!delegate.popover.isShown && window.isKeyWindow && window.level == .floating,
          "quick-panel Open Board preserves the board's normal floating behavior")
    let before = window.frame
    key("s", 1, in: window, flags: [.command, .control])
    await pause()
    check(navigation.sidebarHidden && window.frame == before, "sidebar shortcut expands board content in place")
    window.setContentSize(.init(width: 485, height: 395))
    await pause()
    check(window.frame.width < 500, "sidebar-free board can use a compact normal window")
    snapshot(window, directory.appendingPathComponent("06-compact-board.png"))

    let layoutTitles = await choosePopupItem("Open archive", at: NSPoint(x: window.frame.width - 183, y: 93), in: window.contentView!)
    check(!layoutTitles.contains(where: { $0.localizedCaseInsensitiveCompare("Desktop mode") == .orderedSame }),
          "board layout menu omits Desktop Mode")
    check(navigation.section == .archive && navigation.sidebarHidden, "board layout menu opens Archive with sidebar hidden")
    key("1", 18, in: window, flags: .command)
    key("f", 3, in: window, flags: .command)
    await pause()
    insert("match", in: window)
    await pause()
    check(navigation.query == "match", "ordinary compact board accepts keyboard input")
    key("\u{1b}", 53, in: window)
    await pause()
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?
        .activate(options: [.activateIgnoringOtherApps])
    await pause(450)
    check(!NSApp.isActive && window.level == .floating && window.isVisible,
          "switching apps retains the explicit keep-on-top preference")

    choose("Keep Board on Top")
    await pause()
    check(!navigation.floats && window.level == .normal && window.canHide,
          "turning off Keep Board on Top restores normal window level")
    choose("Show Sidebar")
    await pause()
    check(!navigation.sidebarHidden && window.frame.width >= 665, "showing sidebar from the View menu restores room for navigation")
    window.performClose(nil)
    await pause()
    check(!window.isVisible, "ordinary board can close")
    choose("Keep Board on Top")
    choose("Hide Sidebar")
    delegate.showWindow()
    await pause()
    check(navigation.floats && navigation.sidebarHidden && window.isVisible && window.level == .floating,
          "reopening a closed board retains floating and sidebar choices")
    check(UserDefaults.standard.bool(forKey: "FloatBoard") && UserDefaults.standard.bool(forKey: "SidebarHidden"),
          "floating and sidebar layout choices are saved")
}

private func containsGlassMaterial(_ view: NSView) -> Bool {
    if view is NSVisualEffectView { return true }
    if let glassClass = NSClassFromString("NSGlassEffectView"), view.isKind(of: glassClass) { return true }
    return view.subviews.contains(where: containsGlassMaterial)
}

@MainActor
private func checkGlassUnavailable(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    let appearance = AppearanceSettings.shared
    let store = delegate.store
    let coordinator = delegate.minimalWindows!
    let relaunch = ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1"
    let savedText = "Available without glass.\nSaved after editing."
    check(!appearance.nativeGlassAvailable && !appearance.effectiveGlass,
          "unavailable native glass always selects paper appearance")
    check(appearance.glassEnabled && UserDefaults.standard.bool(forKey: "LiquidGlassEnabled")
          && appearance.glassStatus?.isEmpty == false,
          "unavailable glass retains the saved enabled preference and explains availability")

    let viewMenu = NSApp.mainMenu!.item(withTitle: "View")!.submenu!
    viewMenu.update()
    if let item = viewMenu.item(withTitle: "Liquid Glass") {
        check(!item.isEnabled && item.state == .off && item.toolTip == appearance.glassStatus,
              "View Liquid Glass item is disabled off and explanatory")
        if let action = item.action { _ = NSApp.sendAction(action, to: item.target, from: item) }
        check(appearance.glassEnabled && !appearance.effectiveGlass
              && UserDefaults.standard.bool(forKey: "LiquidGlassEnabled"),
              "direct menu action cannot change an unavailable glass preference")
    } else { check(false, "View Liquid Glass menu item exists") }

    if relaunch {
        check(delegate.navigation.minimalMode && coordinator.windows.count == 1
              && store.board.notes.first?.body == savedText && store.pendingCount == 1,
              "paper desktop restores its selection text and checklist after relaunch")
    }
    delegate.showWindow()
    delegate.window.setContentSize(NSSize(width: 950, height: 612))
    await pause(300)
    if let content = delegate.window.contentView {
        check(delegate.window.isOpaque && !containsGlassMaterial(content),
              "unsupported board is opaque and contains no glass or frosted material")
        var state: (enabled: Bool, value: NSControl.StateValue)?
        let titles = await choosePopupItem("Liquid Glass", at: NSPoint(x: delegate.window.frame.width - 183, y: 93),
                                          in: content, performAction: false) { item in
            state = (item.isEnabled, item.state)
        }
        check(state?.enabled == false && state?.value == .off
              && titles.contains(appearance.glassStatus ?? ""),
              "board layout glass option is disabled off and explains unsupported native glass")
        snapshot(delegate.window, directory.appendingPathComponent("glass-unavailable-board.png"))
    } else { check(false, "unsupported board content is available") }

    delegate.statusItem.button?.performClick(nil)
    await pause(300)
    if let panel = delegate.popover.contentViewController?.view {
        var state: (enabled: Bool, value: NSControl.StateValue)?
        let titles = await choosePopupItem("Liquid Glass", at: NSPoint(x: 284, y: 25),
                                          in: panel, performAction: false) { item in
            state = (item.isEnabled, item.state)
        }
        check(state?.enabled == false && state?.value == .off
              && titles.contains(appearance.glassStatus ?? ""),
              "quick panel glass option is disabled off and explains unsupported native glass")
    } else { check(false, "unsupported quick panel opens") }
    delegate.popover.performClose(nil)

    let id = store.board.notes[0].id
    if !relaunch {
        store.editNote(id) { $0.title = "Paper works everywhere"; $0.body = "Available without glass."; $0.draft = "Keep the content" }
        store.addDraft(on: id)
        delegate.navigation.minimalMode = true
    }
    coordinator.showNote(id)
    await pause(300)
    guard let sticky = coordinator.windows[id], let content = sticky.contentView,
          let editor = nativeEditor(in: content) else {
        check(false, "unsupported native desktop editor exists"); return
    }
    check(sticky.isOpaque && !containsGlassMaterial(content),
          "unsupported desktop note is opaque and contains no glass or frosted material")
    if !relaunch {
        sticky.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText("\nSaved after editing.", replacementRange: NSRange(location: NSNotFound, length: 0))
        await awaitSave(store)
        check(store.note(id)?.body == savedText && BoardStore(file: store.file).note(id)?.body == savedText,
              "native editing and saving work while glass is unavailable")
    } else {
        check(editor.string == savedText, "restored paper editor contains the saved native edits")
    }
    snapshot(sticky, directory.appendingPathComponent("glass-unavailable-desktop.png"))
    delegate.window.performClose(nil)
    coordinator.flushAndPersist()
    check(appearance.glassEnabled && UserDefaults.standard.bool(forKey: "LiquidGlassEnabled"),
          "using paper does not erase the preference for a supported environment")
}

@MainActor
func runWindowChecksIfRequested(_ delegate: AppDelegate) {
    guard let directory = ProcessInfo.processInfo.environment["PAPERPIN_TEST_DIRECTORY"] else { return }
    let url = URL(fileURLWithPath: directory, isDirectory: true)
    if let mode = ProcessInfo.processInfo.environment["PAPERPIN_ENERGY_MODE"] {
        let id = delegate.store.board.notes[0].id
        delegate.store.editNote(id) { $0.body = "Desktop note\nA quiet place for today's tasks." }
        delegate.store.flushPendingSave()
        AppearanceSettings.shared.glassEnabled = mode.contains("glass")
        delegate.navigation.sidebarHidden = true
        if mode.hasPrefix("minimal") {
            delegate.navigation.minimalMode = true
        } else {
            delegate.navigation.minimalMode = false
            delegate.navigation.floats = false
            delegate.showWindow()
            delegate.window.makeFirstResponder(nil)
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?
            .activate(options: [.activateIgnoringOtherApps])
        return
    }
    Task { @MainActor in
        await pause(600)
        let window = delegate.window!
        let store = delegate.store
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print("\(ok ? "PASS" : "FAIL") \(name)"); fflush(stdout)
            if !ok { failures += 1 }
        }
        if ProcessInfo.processInfo.environment["PAPERPIN_CHECK_GLASS_UNAVAILABLE"] == "1" {
            await checkGlassUnavailable(delegate, directory: url, check: check)
            print("FINISHED \(failures) glass availability failures")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        if ProcessInfo.processInfo.environment["PAPERPIN_CHECK_POLISH"] == "1" {
            await checkPolish(delegate, directory: url, check: check)
            print("FINISHED \(failures) polish failures")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        if ProcessInfo.processInfo.environment["PAPERPIN_CHECK_MINIMAL"] == "1" {
            await checkMinimalMode(delegate, directory: url, check: check)
            print("FINISHED \(failures) minimal failures")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        let view = window.contentView!
        if ProcessInfo.processInfo.environment["PAPERPIN_CHECK_LAYOUT"] == "1" {
            if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
                check(delegate.navigation.floats && delegate.navigation.sidebarHidden, "fresh process remembers floating and sidebar choices")
                check(window.isVisible && window.level == .floating && window.styleMask.contains([.closable, .miniaturizable]),
                      "fresh launch restores a normal floating board with window controls")
                check(UserDefaults.standard.object(forKey: "DesktopMode") == nil, "retired desktop preference stays removed after relaunch")
                check(store.board.notes.first?.body == "Layout test" && store.pendingCount == 1, "changing layout preserves saved content")
            } else {
                store.editNote(store.board.notes[0].id) { $0.body = "Layout test"; $0.draft = "One pending task" }
                store.addDraft(on: store.board.notes[0].id)
                await checkBoardLayout(delegate, directory: url, check: check)
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
        await awaitSave(store)
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
        await awaitSave(store)
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
            await awaitSave(store)
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
        await awaitSave(store)
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

@MainActor
private func checkMinimalMode(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    let store = delegate.store
    let navigation = delegate.navigation
    let coordinator = delegate.minimalWindows!
    let level = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
        check(navigation.minimalMode && !delegate.window.isVisible, "relaunch restores minimal mode without full board")
        check(coordinator.windows.count == 1 && coordinator.savedOpenNoteIDs.count == 1,
              "relaunch opens only the remaining selected note")
        check(coordinator.windows.values.allSatisfy { $0.level.rawValue == level && $0.isVisible },
              "relaunch parks notes at desktop level")
        check(store.board.notes.count == 2, "hiding a sticky preserves its original data")
        if let sticky = coordinator.windows.values.first {
            check(abs(sticky.frame.width - 360) < 1 && abs(sticky.frame.height - 440) < 1,
                  "relaunch restores note dimensions")
            snapshot(sticky, directory.appendingPathComponent("minimal-restored.png"))
        }
        return
    }
    let first = store.board.notes[0].id
    store.editNote(first) { $0.title = "Today"; $0.body = "A little room to think.\n\nNotes stay here while you work." }
    navigation.floats = true
    navigation.sidebarHidden = true
    navigation.minimalMode = true
    await pause(400)
    check(!delegate.window.isVisible && coordinator.windows.count == 1, "minimal mode hides board and opens first note")
    check(coordinator.windows[first]?.minSize == NSSize(width: 200, height: 160), "desktop note has compact resize limits")
    let second = store.addNote()
    store.editNote(second) { $0.title = "Small things"; $0.body = "One thing at a time."; $0.draft = "Review the draft" }
    store.addDraft(on: second)
    navigation.showOnDesktop(second)
    await pause(350)
    check(coordinator.windows.count == 2 && coordinator.windows[second]?.isKeyWindow == true,
          "Show on Desktop opens an independent editable note")
    navigation.showOnDesktop(second)
    check(coordinator.windows.count == 2, "opening the same note does not duplicate windows")
    guard let firstWindow = coordinator.windows[first], let secondWindow = coordinator.windows[second] else {
        check(false, "minimal windows exist for interaction checks"); return
    }
    let originalFrame = firstWindow.frame
    firstWindow.setContentSize(NSSize(width: 200, height: 160))
    await pause(200)
    check(firstWindow.frame.size == NSSize(width: 200, height: 160), "desktop note actually resizes to 200 by 160")
    snapshot(firstWindow, directory.appendingPathComponent("minimal-compact.png"))
    firstWindow.setFrame(originalFrame, display: true)
    coordinator.showNote(first)
    await pause(250)
    click(60, 65, in: firstWindow.contentView!)
    await pause()
    key("a", 0, in: firstWindow, flags: .command)
    await pause(80)
    insert("Today\n\nPlan the next step.\nKeep it simple. 🌱", in: firstWindow)
    await pause()
    check(store.note(first)?.body == "Today\n\nPlan the next step.\nKeep it simple. 🌱", "minimal editor supports selection and multiline Unicode input")
    check(nativeEditor(in: firstWindow.contentView!)?.undoManager?.canUndo == true, "native minimal typing retains undo support")
    await awaitSave(store)
    check(BoardStore(file: store.file).note(first)?.body == store.note(first)?.body, "minimal edits persist through shared store")
    delegate.showWindow()
    await pause(200)
    check(delegate.window.isVisible && coordinator.windows.count == 2, "full board opens alongside desktop notes")
    check(delegate.window.styleMask.contains(.closable) && delegate.window.level == .floating
          && navigation.sidebarHidden, "full board remains closable and preserves floating and sidebar preferences")
    delegate.window.performClose(nil)
    await pause(200)
    check(!delegate.window.isVisible && coordinator.windows.count == 2, "temporary board closes back to desktop notes")
    delegate.showWindow()
    await pause(200)
    store.editNote(first) { $0.body += "\nShared with the board." }
    await pause(200)
    check(nativeEditor(in: firstWindow.contentView!)?.undoManager?.canUndo == false,
          "external board edits invalidate stale undo offsets in minimal editor")
    snapshot(firstWindow, directory.appendingPathComponent("minimal-paper.png"))
    snapshot(secondWindow, directory.appendingPathComponent("minimal-checklist.png"))
    let task = store.note(second)!.tasks[0]
    store.finish(task.id, on: second)
    await pause(100)
    check(store.board.archive.contains { $0.id == task.id } && store.note(second)?.tasks.isEmpty == true,
          "minimal notes share task completion and archive")
    store.restore(task.id)
    await pause(100)
    check(store.note(second)?.tasks.first?.id == task.id, "archive restore returns task to desktop note")
    AppearanceSettings.shared.glassEnabled = true
    NSApp.appearance = NSAppearance(named: .aqua)
    await pause(500)
    check(firstWindow.isOpaque == !AppearanceSettings.shared.effectiveGlass, "glass updates already-open desktop windows")
    snapshot(firstWindow, directory.appendingPathComponent("minimal-glass-light.png"))
    snapshot(delegate.window, directory.appendingPathComponent("board-glass-light.png"))
    NSApp.appearance = NSAppearance(named: .darkAqua)
    await pause(400)
    snapshot(firstWindow, directory.appendingPathComponent("minimal-glass-dark.png"))
    snapshot(delegate.window, directory.appendingPathComponent("board-glass-dark.png"))
    AppearanceSettings.shared.glassEnabled = false
    NSApp.appearance = nil
    await pause(200)
    coordinator.parkOnDesktop()
    check(coordinator.windows.values.allSatisfy { $0.level.rawValue == level && $0.collectionBehavior.contains([.canJoinAllSpaces, .stationary]) },
          "all notes park behind app windows across Spaces")
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let repaired = MinimalWindowCoordinator.constrainedFrame(NSRect(x: 4000, y: -1000, width: 2000, height: 1200), to: [screen])
    check(screen.contains(repaired) && repaired.width >= 200 && repaired.height >= 160,
          "simulated display removal recovers off-screen and oversized notes")
    var frame = secondWindow.frame
    frame.size = NSSize(width: 360, height: 440)
    secondWindow.setFrame(frame, display: true)
    coordinator.flushAndPersist()
    firstWindow.performClose(nil)
    await pause(200)
    check(coordinator.windows[first] == nil && store.note(first) != nil, "closing hides a note without deleting content")
    navigation.minimalMode = false
    await pause(200)
    check(coordinator.windows.isEmpty && delegate.window.isVisible, "leaving minimal mode restores full board")
    check(navigation.floats && navigation.sidebarHidden && delegate.window.level == .floating
          && delegate.window.styleMask.contains(.closable),
          "leaving minimal mode preserves board floating sidebar and ordinary window controls")
    navigation.floats = false
    delegate.window.toggleFullScreen(nil)
    await pause(1500)
    navigation.showOnDesktop(second)
    let deadline = Date().addingTimeInterval(6)
    while (delegate.window.styleMask.contains(.fullScreen) || coordinator.windows.isEmpty) && Date() < deadline { await pause(100) }
    check(!delegate.window.styleMask.contains(.fullScreen) && !delegate.window.isVisible, "entering minimal mode exits full screen before hiding board")
    check(coordinator.windows[second]?.isKeyWindow == true, "Show on Desktop honors selected note after full-screen exit")
    check(coordinator.windows.count == 1 && coordinator.windows[second] != nil, "mode toggle preserves chosen notes and hidden notes")
    let temporary = store.addNote()
    navigation.showOnDesktop(temporary)
    store.deleteNote(temporary)
    await pause(100)
    check(coordinator.windows[temporary] == nil && !coordinator.savedOpenNoteIDs.contains(temporary), "deleting a note removes its desktop presentation")
    coordinator.windows[second]?.performClose(nil)
    navigation.minimalMode = false
    navigation.minimalMode = true
    check(coordinator.windows.isEmpty, "closing every sticky does not reseed Inbox on next mode entry")
    navigation.showOnDesktop(second)
    store.editNote(second) { $0.body = "Saved before sleep." }
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    check(BoardStore(file: store.file).note(second)?.body == "Saved before sleep.", "sleep notification flushes pending edits")
    // The runner launches this same isolated profile again to test restoration.
    coordinator.flushAndPersist()
    check(coordinator.savedOpenNoteIDs == [second] && coordinator.windows[second] != nil,
          "selected note is present immediately before orderly quit")

    let suite = "local.paperpin.recovery-check.\(UUID().uuidString)"
    let isolated = UserDefaults(suiteName: suite)!
    defer { isolated.removePersistentDomain(forName: suite) }
    let savedID = UUID()
    let savedFrame = "{{40, 50}, {320, 420}}"
    isolated.set([savedID.uuidString], forKey: "MinimalOpenNotes")
    isolated.set([savedID.uuidString: savedFrame], forKey: "MinimalWindowFrames")
    isolated.set(true, forKey: "MinimalModeInitialized")
    let brokenFile = directory.appendingPathComponent("unreadable-board.json")
    try! Data("unreadable".utf8).write(to: brokenFile)
    let broken = BoardStore(file: brokenFile)
    let recovery = MinimalWindowCoordinator(store: broken, navigation: Navigation(), openBoard: {}, defaults: isolated)
    recovery.setEnabled(true)
    check(broken.requiresFileRecovery && recovery.windows.isEmpty && recovery.savedOpenNoteIDs == [savedID]
          && isolated.dictionary(forKey: "MinimalWindowFrames")?[savedID.uuidString] as? String == savedFrame,
          "unreadable board preserves saved desktop selection and geometry")
}

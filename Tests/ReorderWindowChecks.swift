import AppKit

/// Exercise real destination callbacks/geometry without synthesizing system input.
private final class ReorderDragInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingSource: Any?
    var draggingLocation: NSPoint
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
    init(source: TaskGripView, window: NSWindow, point: NSPoint, token: UUID) {
        draggingSource = source; draggingDestinationWindow = window; draggingLocation = point
        super.init()
        draggingPasteboard.setString(token.uuidString, forType: TaskReorderSession.pasteboardType)
    }
    deinit { draggingPasteboard.releaseGlobally() }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

func reorderGrips(in view: NSView) -> [TaskGripView] {
    (view as? TaskGripView).map { [$0] } ?? view.subviews.flatMap { reorderGrips(in: $0) }
}

@MainActor
func prepareReorderPreview(_ delegate: AppDelegate) -> UUID {
    let store = delegate.store
    let note = store.board.notes[0].id
    store.editNote(note) {
        $0.title = "Reorder tasks"; $0.body = ""; $0.pinned = true; $0.color = .blue
        $0.tasks = ["Alpha — plan the week", "Bravo — write the outline", "Charlie — review the draft", "Delta — send the update"].map { ChecklistItem(text: $0) }
        $0.draft = "Unfinished task stays here"
    }
    let other = store.addNote()
    store.editNote(other) { $0.title = "Other note"; $0.tasks = [ChecklistItem(text: "Keep this task here"), ChecklistItem(text: "And this one too")] }
    store.flushPendingSave()
    delegate.navigation.minimalMode = true
    delegate.minimalWindows.showNote(note)
    let screen = NSScreen.main!.visibleFrame
    delegate.minimalWindows.windows[note]?.setFrame(NSRect(x: screen.minX + 910, y: screen.maxY - 550, width: 320, height: 420), display: true)
    delegate.showWindow()
    delegate.window.setFrame(NSRect(x: screen.minX + 30, y: screen.maxY - 680, width: 850, height: 620), display: true)
    return note
}

@MainActor
func checkReordering(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    let store = delegate.store
    if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
        let note = store.sortedNotes.first!
        check(note.tasks.map(\.text) == ["Charlie — review the draft", "Alpha — plan the week", "Bravo — write the outline", "Delta — send the update"],
              "relaunch restores reordered tasks without changing text")
        check(note.draft == "Unfinished task stays here" && store.pendingCount == 6,
              "relaunch retains draft other note and task counts")
        return
    }
    let id = prepareReorderPreview(delegate)
    await pause(500)
    let desktop = delegate.minimalWindows.windows[id]!
    let original = store.note(id)!.tasks.map(\.id)
    func grip(_ window: NSWindow, _ task: UUID) -> TaskGripView? {
        window.contentView.flatMap { reorderGrips(in: $0).first { $0.taskID == task && !$0.isHiddenOrHasHiddenAncestor } }
    }
    func displayed(_ window: NSWindow) -> [UUID] {
        guard let content = window.contentView else { return [] }
        return reorderGrips(in: content).filter { $0.noteID == id && !$0.isHiddenOrHasHiddenAncestor }.sorted {
            $0.convert($0.bounds, to: nil).midY > $1.convert($1.bounds, to: nil).midY
        }.map(\.taskID)
    }
    func drop(_ source: UUID, onto target: UUID, below: Bool, in window: NSWindow, host: NSView) -> Bool {
        guard let handle = grip(window, source),
              let row = TaskRowTargetView.rows.allObjects.first(where: { $0.window === window && $0.taskID == target && !$0.isHiddenOrHasHiddenAncestor }),
              let item = TaskReorderSession.shared.begin(task: source, note: id, store: store, window: window) else { return false }
        let point = row.convert(NSPoint(x: row.bounds.midX, y: below ? row.bounds.maxY - 2 : row.bounds.minY + 2), to: nil)
        let info = ReorderDragInfo(source: handle, window: window, point: point, token: item.token)
        guard host.draggingEntered(info) == .move else { TaskReorderSession.shared.end(); return false }
        return host.performDragOperation(info)
    }
    func checkEveryPosition(in window: NSWindow, host: NSView, name: String) async {
        let saved = store.note(id)!.tasks
        var correct = true
        // Every source to every final index: also checks no-op drops, middle
        // positions and the previously overlapping row rectangles on newer macOS.
        for source in original {
            for index in original.indices {
                let current = store.note(id)!.tasks.map(\.id)
                let others = current.filter { $0 != source }
                let target = index == others.count ? others.last! : others[index]
                var expected = others
                expected.insert(source, at: index)
                let accepted = drop(source, onto: target, below: index == others.count, in: window, host: host)
                await pause(55)
                correct = correct && accepted && store.note(id)!.tasks.map(\.id) == expected
                    && displayed(delegate.window) == expected && displayed(desktop) == expected
            }
        }
        check(correct, "\(name) native drops move every task to every position and synchronize both editors")
        store.editNote(id) { $0.tasks = saved }
        await pause()
    }
    func checkWrapped(in window: NSWindow, host: NSView, name: String) async {
        let saved = store.note(id)!.tasks
        store.editTask(original[0], on: id, text: "Plan the week\nInclude the next steps")
        await pause()
        await checkEveryPosition(in: window, host: host, name: "\(name) with wrapped text")
        check(store.note(id)!.tasks.first(where: { $0.id == original[0] })?.text == "Plan the week\nInclude the next steps",
              "\(name) moving wrapped text preserves all its lines")
        store.editNote(id) { $0.tasks = saved }
        await pause()
    }
    func checkDropRejection(in window: NSWindow, host: NSView, name: String) {
        guard let source = grip(window, original[0]),
              let row = TaskRowTargetView.rows.allObjects.first(where: { $0.window === window && $0.taskID == original[1] && !$0.isHiddenOrHasHiddenAncestor }) else {
            check(false, "\(name) drop rejection fixture exists"); return
        }
        let before = store.board
        let session = TaskReorderSession.shared
        _ = session.begin(task: original[0], note: id, store: store, window: window)!
        let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let invalid = ReorderDragInfo(source: source, window: window, point: point, token: UUID())
        check(host.draggingEntered(invalid).isEmpty && !host.performDragOperation(invalid) && store.board == before,
              "\(name) rejects an external or stale payload without changing notes")
        let next = session.begin(task: original[0], note: id, store: store, window: window)!
        let outside = ReorderDragInfo(source: source, window: window, point: NSPoint(x: -20, y: -20), token: next.token)
        check(host.draggingEntered(outside).isEmpty && !host.performDragOperation(outside) && store.board == before,
              "\(name) rejects a drop outside the task list")
        if let other = TaskRowTargetView.rows.allObjects.first(where: { $0.window === window && $0.noteID != id && !$0.isHiddenOrHasHiddenAncestor }) {
            let active = session.begin(task: original[0], note: id, store: store, window: window)!
            let cross = ReorderDragInfo(source: source, window: window,
                                       point: other.convert(NSPoint(x: other.bounds.midX, y: other.bounds.midY), to: nil), token: active.token)
            check(host.draggingEntered(cross).isEmpty && !host.performDragOperation(cross) && store.board == before,
                  "\(name) rejects a drop onto another note")
        }
        let active = session.begin(task: original[0], note: id, store: store, window: window)!
        let valid = ReorderDragInfo(source: source, window: window, point: point, token: active.token)
        _ = host.draggingEntered(valid)
        let marked = session.target === row && row.marker != nil
        host.draggingExited(valid)
        session.end()
        check(marked && row.marker == nil && session.active == nil && store.board == before,
              "\(name) shows and clears the insertion line without moving on hover or cancel")
    }
    func checkScrolling(in window: NSWindow, host: NSView, name: String) async {
        let saved = store.note(id)!.tasks
        let extra = (1...30).map { ChecklistItem(text: "Additional task \($0)") }
        store.editNote(id) { $0.tasks = saved + extra }
        await pause(300)
        guard let source = grip(window, saved[0].id),
              let row = TaskRowTargetView.rows.allObjects.first(where: { $0.window === window && $0.taskID == saved[0].id && !$0.isHiddenOrHasHiddenAncestor }),
              let scroll = row.enclosingScrollView else {
            check(false, "\(name) scrollable task list exists")
            store.editNote(id) { $0.tasks = saved }; return
        }
        let clip = scroll.contentView
        let start = clip.bounds.origin.y
        let item = TaskReorderSession.shared.begin(task: saved[0].id, note: id, store: store, window: window)!
        let info = ReorderDragInfo(source: source, window: window,
                                   point: row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil), token: item.token)
        _ = host.draggingEntered(info)
        let bottom = clip.isFlipped ? clip.bounds.maxY - 4 : clip.bounds.minY + 4
        info.draggingLocation = clip.convert(NSPoint(x: row.convert(row.bounds, to: clip).midX, y: bottom), to: nil)
        for _ in 0..<20 { _ = host.draggingUpdated(info); await pause(20) }
        let down = clip.bounds.origin.y
        let top = clip.isFlipped ? clip.bounds.minY + 4 : clip.bounds.maxY - 4
        info.draggingLocation = clip.convert(NSPoint(x: clip.bounds.midX, y: top), to: nil)
        for _ in 0..<20 { _ = host.draggingUpdated(info); await pause(20) }
        check(down > start + 50 && clip.bounds.origin.y < down - 50,
              "\(name) long lists scroll down and up during a held drag")
        host.draggingExited(info)
        TaskReorderSession.shared.end()
        check(store.note(id)!.tasks == saved + extra, "\(name) scrolling a drag does not commit or lose tasks")
        store.editNote(id) { $0.tasks = saved }
        clip.scroll(to: .zero)
        scroll.reflectScrolledClipView(clip)
        await pause(300)
    }
    check(displayed(delegate.window) == original && displayed(desktop) == original,
          "board and desktop show shared native reorder handles in the same order")
    check(grip(delegate.window, original[0])?.canMoveUp == false && grip(desktop, original[3])?.canMoveDown == false,
          "first and last task disable unavailable move actions")
    check(drop(original[3], onto: original[0], below: false, in: delegate.window, host: delegate.window.contentView!),
          "board native drop handler accepts a drop above the first row")
    await pause()
    check(displayed(desktop) == [original[3], original[0], original[1], original[2]],
          "board native drop changes the desktop order")
    check(drop(original[3], onto: original[2], below: true, in: delegate.window, host: delegate.window.contentView!),
          "board native drop handler moves to the end")
    await pause()
    let desktopHost = desktop.contentView!.subviews[0]
    check(drop(original[3], onto: original[0], below: false, in: desktop, host: desktopHost),
          "desktop native drop handler accepts a drop above the first row")
    await pause()
    check(displayed(delegate.window).first == original[3], "desktop native drop updates the full app")
    check(drop(original[3], onto: original[2], below: true, in: desktop, host: desktopHost),
          "desktop native drop handler moves to the end")
    await pause()
    await checkEveryPosition(in: delegate.window, host: delegate.window.contentView!, name: "board")
    await checkEveryPosition(in: desktop, host: desktopHost, name: "desktop")
    await checkWrapped(in: delegate.window, host: delegate.window.contentView!, name: "board")
    await checkWrapped(in: desktop, host: desktopHost, name: "desktop")
    checkDropRejection(in: delegate.window, host: delegate.window.contentView!, name: "board")
    checkDropRejection(in: desktop, host: desktopHost, name: "desktop")
    await checkScrolling(in: delegate.window, host: delegate.window.contentView!, name: "board")
    await checkScrolling(in: desktop, host: desktopHost, name: "desktop")
    check(grip(delegate.window, original[2])?.moveTaskUp() == true, "board handle moves a task up")
    await pause()
    let afterBoard = [original[0], original[2], original[1], original[3]]
    check(displayed(delegate.window) == afterBoard && displayed(desktop) == afterBoard,
          "board reorder immediately updates the desktop presentation")
    check(grip(desktop, original[0])?.moveTaskDown() == true, "desktop handle moves a task down")
    await pause()
    let expected = [original[2], original[0], original[1], original[3]]
    check(displayed(delegate.window) == expected && displayed(desktop) == expected,
          "desktop reorder immediately updates the full app")
    check(grip(desktop, original[0])?.accessibilityCustomActions()?.map(\.name) == ["Move Up", "Move Down"],
          "task handles expose both VoiceOver move actions")
    let session = TaskReorderSession.shared
    let before = store.board
    _ = session.begin(task: original[0], note: id, store: store, window: desktop)
    check(session.accepts(note: id, store: store) && !session.accepts(note: store.board.notes.first(where: { $0.id != id })!.id, store: store),
          "active drag accepts only the same note")
    session.end()
    check(store.board == before && session.active == nil, "cancelled drag leaves the complete board unchanged")
    NSApp.activate(ignoringOtherApps: true)
    await pause(350)
    delegate.toggleQuick()
    await pause(450)
    if let panel = delegate.popover.contentViewController?.view, let panelWindow = panel.window,
       let handle = reorderGrips(in: panel).first(where: { $0.taskID == original[3] }) {
        check(true, "quick panel exposes the same task reorder controls")
        await checkEveryPosition(in: panelWindow, host: panel, name: "quick panel")
        await checkWrapped(in: panelWindow, host: panel, name: "quick panel")
        checkDropRejection(in: panelWindow, host: panel, name: "quick panel")
        await checkScrolling(in: panelWindow, host: panel, name: "quick panel")
        check(drop(original[3], onto: original[2], below: false, in: panelWindow, host: panel),
              "quick panel native drop handler accepts a drop at the beginning")
        await pause()
        check(displayed(desktop).first == original[3], "quick panel native drop updates desktop order")
        check(drop(original[3], onto: original[1], below: true, in: panelWindow, host: panel),
              "quick panel native drop handler moves to the end")
        await pause()
        _ = session.begin(task: original[3], note: id, store: store, window: panelWindow)
        check(delegate.popover.isShown && delegate.popover.behavior == .applicationDefined, "quick panel stays open for its native drag")
        session.end()
        check(delegate.popover.behavior == .transient, "quick panel restores normal dismissal after cancellation")
        check(handle.moveTaskUp(), "quick panel handle reorders tasks")
        await pause()
        check(displayed(desktop).last == original[1], "quick panel reorder propagates to the desktop")
        _ = handle.moveTaskDown()
    } else { check(false, "quick panel opens with reorder controls") }
    delegate.popover.performClose(nil)
    check(store.flushPendingSave(), "reordering flushes successfully")
    check(BoardStore(file: store.file).note(id)?.tasks.map(\.id) == expected, "all views persist the same task order")
    snapshot(delegate.window, directory.appendingPathComponent("reorder-board.png"))
    snapshot(desktop, directory.appendingPathComponent("reorder-desktop.png"))
    let savedAppearance = NSApp.appearance
    let savedGlass = AppearanceSettings.shared.glassEnabled
    for (style, glass) in [("paper", false), ("glass", true)] {
        AppearanceSettings.shared.glassEnabled = glass
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            await pause(300)
            for (name, window) in [("board", delegate.window!), ("desktop", desktop)] {
                if let handle = grip(window, original[0]) { window.makeFirstResponder(handle); handle.needsDisplay = true }
                snapshot(window, directory.appendingPathComponent("reorder-\(name)-\(style)-\(theme).png"))
            }
        }
    }
    AppearanceSettings.shared.glassEnabled = savedGlass
    NSApp.appearance = savedAppearance
    _ = session.begin(task: original[0], note: id, store: store, window: desktop)
    desktop.performClose(nil)
    check(session.active == nil, "closing the source window cancels its drag session")
    delegate.minimalWindows.showNote(id)
    let transient = store.addNote()
    store.editNote(transient) { $0.tasks = [ChecklistItem(text: "Temporary drag source")] }
    let removed = store.note(transient)!.tasks[0].id
    _ = session.begin(task: removed, note: transient, store: store, window: delegate.window)
    store.deleteNote(transient)
    check(session.active == nil, "deleting a source note cancels the drag without stale references")
    store.flushPendingSave()
}

import AppKit

@MainActor
@discardableResult
func prepareRemindersPreview(_ delegate: AppDelegate) -> UUID {
    let id = delegate.store.board.notes.first!.id
    delegate.store.editNote(id) {
        $0.title = "Tasks"; $0.color = .blue; $0.body = "A little space for today's ideas."
        $0.tasks = [ChecklistItem(text: "Sketch a new idea"), ChecklistItem(text: "Share the draft"), ChecklistItem(text: "Plan the next steps")]
        $0.draft = ""
    }
    delegate.store.flushPendingSave()
    delegate.remindersClient.loadSample()
    delegate.reminders.prepareConnection()
    delegate.reminders.connect(noteID: id, list: delegate.remindersClient.availableLists[0])
    delegate.reminders.setSelectedTab("reminders", noteID: id, presentation: "board")
    delegate.reminders.setSelectedTab("reminders", noteID: id, presentation: "desktop")
    delegate.navigation.minimalMode = true
    delegate.minimalWindows.showNote(id)
    let screen = NSScreen.main!.visibleFrame
    delegate.minimalWindows.windows[id]?.setFrame(NSRect(x: screen.minX + 890, y: screen.maxY - 665, width: 330, height: 550), display: true)
    delegate.showWindow()
    delegate.window.setFrame(NSRect(x: screen.minX + 30, y: screen.maxY - 760, width: 820, height: 710), display: true)
    return id
}

// Controller/window checks complement the separate real UI interaction pass.
@MainActor
func checkRemindersWindows(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
        delegate.remindersClient.loadSample()
        delegate.reminders.refresh()
        check(delegate.reminders.state.connection?.listID == "fixture-main", "relaunch restores connected list identifier")
        check(delegate.store.pendingCount == 3 && delegate.store.board.archive.isEmpty, "relaunch preserves separate local tasks and archive")
        return
    }
    let id = prepareRemindersPreview(delegate)
    await pause(400)
    let board = delegate.window!
    let desktop = delegate.minimalWindows.windows[id]!
    check((board.contentView as? TaskReorderHostingView<BoardView>)?.rootView.reminders === delegate.reminders,
          "full board consumes the app's shared Reminders store")
    check(reorderGrips(in: board.contentView!).isEmpty && reorderGrips(in: desktop.contentView!).isEmpty,
          "reminder tabs do not expose local task dragging")
    check(delegate.statusItem.button?.title.contains("8") == true, "menu-bar count combines three local tasks and five reminders")
    delegate.navigation.showsNextTask = true
    check(delegate.statusItem.button?.title.contains("Sketch a new idea") == true, "menu-bar next title keeps local tasks first")
    for (name, scheme, glass) in [("paper-light", NSAppearance.Name.aqua, false), ("paper-dark", .darkAqua, false),
                                  ("glass-light", .aqua, true), ("glass-dark", .darkAqua, true)] {
        NSApp.appearance = NSAppearance(named: scheme)
        AppearanceSettings.shared.glassEnabled = glass
        await pause(300)
        snapshot(board, directory.appendingPathComponent("reminders-board-\(name).png"))
        snapshot(desktop, directory.appendingPathComponent("reminders-desktop-\(name).png"))
        check(desktop.contentView!.bounds.width == 330 && desktop.contentView!.bounds.height == 550,
              "\(name) reminder content preserves the independently sized desktop window")
    }
    NSApp.appearance = NSAppearance(named: .aqua)
    delegate.reminders.setSelectedTab("tasks", noteID: id, presentation: "board")
    board.close()
    await pause(150)
    delegate.showWindow()
    await pause(300)
    check(reorderGrips(in: board.contentView!).count == 3 && reorderGrips(in: desktop.contentView!).isEmpty,
          "recreated board restores Tasks tab while desktop keeps its Reminders tab")
    check(delegate.reminders.selectedTab(noteID: id, presentation: "board") == "tasks"
          && delegate.reminders.selectedTab(noteID: id, presentation: "desktop") == "reminders",
          "tab selections persist independently")
    delegate.navigation.query = "sketches"
    await pause(250)
    check(reorderGrips(in: board.contentView!).isEmpty && delegate.reminders.matches("sketches", noteID: id),
          "reminder-only note search reveals Reminders tab")
    delegate.navigation.query = ""
    desktop.setContentSize(NSSize(width: 200, height: 330))
    await pause(250)
    snapshot(desktop, directory.appendingPathComponent("reminders-desktop-compact.png"))
    check(desktop.contentView!.bounds.width == 200, "minimum-width desktop supports compact reminder layout")
    desktop.setContentSize(NSSize(width: 330, height: 550))
    delegate.toggleQuick()
    await pause(250)
    if let panel = delegate.popover.contentViewController as? TaskReorderHostingController<QuickPanel> {
        snapshot(panel.view.window!, directory.appendingPathComponent("reminders-quick-panel.png"))
        check((panel.view as? TaskReorderHostingView<QuickPanel>)?.rootView.reminders === delegate.reminders, "quick panel consumes the same shared reminder snapshots")
    } else { check(false, "quick panel opens") }
    delegate.popover.performClose(nil)
    await pause(150)
    check(delegate.popover.contentViewController == nil, "closing quick panel releases its reminder view hierarchy")
    delegate.remindersClient.holdCompletion = true
    delegate.reminders.complete(delegate.reminders.state.items.first { $0.id == "sample-overdue" }!)
    await pause(200)
    check(delegate.remindersClient.completions == 1 && delegate.reminders.state.completing.contains("sample-overdue"),
          "shared reminder completion enters the saving state once")
    if !delegate.remindersClient.completionReplies.isEmpty {
        delegate.remindersClient.items.removeAll { $0.id == "sample-overdue" }
        delegate.remindersClient.completionReplies.removeFirst()(.success(()))
    }
    await pause(250)
    check(delegate.reminders.state.items.count == 4 && delegate.statusItem.button?.title.contains("7") == true,
          "successful completion updates shared content and menu-bar total")
    check(delegate.store.pendingCount == 3 && delegate.store.board.archive.isEmpty,
          "Apple completion never changes local tasks or Paperpin archive")
    delegate.remindersClient.holdCompletion = false
    delegate.remindersClient.loadSample()
    delegate.reminders.refresh()
    await pause(150)
    check(delegate.reminders.state.items.count == 5, "externally restored reminder returns to shared view content")
    let localTasks = delegate.store.note(id)!.tasks
    delegate.store.editNote(id) { $0.tasks = [] }
    await pause(100)
    check(delegate.statusItem.button?.title.contains("Send the project update") == true,
          "menu-bar title falls back to the first sorted reminder when local tasks are empty")
    delegate.store.editNote(id) { $0.tasks = localTasks }
    delegate.navigation.showsNextTask = false
    delegate.store.flushPendingSave()
}

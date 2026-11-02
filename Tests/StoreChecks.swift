import Foundation

@main
enum StoreChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = root.appendingPathComponent("Board.json")
        let store = BoardStore(file: file)
        func check(_ result: @autoclosure () -> Bool, _ name: String) {
            guard result() else { fatalError(name) }
            print("PASS \(name)")
        }
        check(store.board.notes.count == 1 && store.pendingCount == 0 && store.diskIssue == nil, "empty first run")
        let first = store.board.notes[0].id
        let other = store.addNote()
        store.editNote(first) { $0.pinned = true }
        store.editNote(other) { $0.title = "आज"; $0.body = "Notes\nLine two – 🌱"; $0.color = .lilac }
        check(store.sortedNotes.first?.id == first, "pin ordering")
        for text in ["  \n ", "First", " Second ✓ ", "Third"] {
            store.editNote(other) { $0.draft = text }
            store.addDraft(on: other)
        }
        check(store.note(other)?.tasks.map(\.text) == ["First", "Second ✓", "Third"], "trim and reject blank checklist items")
        let task = store.note(other)!.tasks[1]
        store.editTask(task.id, on: other, text: "Edited ✓")
        store.finish(task.id, on: other)
        store.finish(task.id, on: other)
        check(store.pendingCount == 2 && store.board.archive.count == 1 && store.board.archive[0].task.text == "Edited ✓", "idempotent completion and counts")
        store.editNote(other) { $0.title = "Renamed"; $0.draft = "unfinished checkbox" }
        store.setDestination(other)
        store.setQuickDraft("unfinished quick capture")
        check(store.flushPendingSave(), "pending text edits flush before reopening")
        let reopened = BoardStore(file: file)
        check(reopened.board == store.board, "round-trip notes, unicode, colors, pinning, drafts, destination, and archive")
        reopened.restore(task.id)
        reopened.restore(task.id)
        check(reopened.board.archive.isEmpty && reopened.note(other)?.tasks.map(\.text) == ["First", "Edited ✓", "Third"], "restore original note and position once")
        reopened.addQuickTask()
        check(reopened.note(other)?.tasks.last?.text == "unfinished quick capture" && reopened.board.quickDraft.isEmpty, "quick capture to chosen note")
        reopened.finish(task.id, on: other)
        reopened.deleteNote(other)
        check(reopened.board.archive.count == 1 && reopened.captureNote?.id == first, "deleting a note preserves archive and repairs capture destination")
        reopened.restore(task.id)
        check(reopened.note(other)?.title == "Renamed" && reopened.note(other)?.color == .lilac && reopened.note(other)?.tasks.first?.id == task.id, "restore after original sticky was deleted")
        for note in reopened.board.notes { reopened.deleteNote(note.id) }
        reopened.setQuickDraft("  ")
        reopened.addQuickTask()
        check(reopened.board.notes.isEmpty, "whitespace capture leaves empty board alone")
        reopened.setQuickDraft("Fresh start")
        reopened.addQuickTask()
        check(reopened.board.notes.first?.title == "Inbox" && reopened.pendingCount == 1, "capture with no remaining stickies")
        check(reopened.flushPendingSave(), "structural changes finish before inspecting disk")
        let earlier = try Data(contentsOf: file)
        var invalid = try JSONSerialization.jsonObject(with: earlier) as! [String: Any]
        invalid["version"] = 2
        let unsupported = try JSONSerialization.data(withJSONObject: invalid)
        try unsupported.write(to: file)
        let newer = BoardStore(file: file)
        newer.setQuickDraft("should not overwrite")
        newer.retrySave()
        let preserved = try Data(contentsOf: file)
        check(newer.diskIssue != nil && preserved == unsupported, "unsupported document protected on disk")
        try Data("unreadable".utf8).write(to: file)
        let damaged = BoardStore(file: file)
        _ = damaged.addNote()
        let untouched = try String(contentsOf: file, encoding: .utf8)
        check(damaged.diskIssue != nil && untouched == "unreadable", "damaged document preserved")
        try earlier.write(to: file)
        let retry = BoardStore(file: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        retry.setQuickDraft("kept in memory")
        _ = retry.flushPendingSave()
        check(retry.diskIssue != nil && retry.board.quickDraft == "kept in memory", "write failure keeps current edits")
        try FileManager.default.removeItem(at: file)
        retry.retrySave()
        check(retry.diskIssue == nil && BoardStore(file: file).board == retry.board, "retry persists after disk failure")
        try FileManager.default.removeItem(at: root)
    }
}

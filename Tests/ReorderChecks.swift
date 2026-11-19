import Foundation

private final class ReorderWrites {
    private let lock = NSLock()
    private var attempts = 0
    var fail = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return attempts }
    func write(_ data: Data, to file: URL) throws {
        lock.lock(); attempts += 1; lock.unlock()
        if fail { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: file, options: .atomic)
    }
}

@main
enum ReorderChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writes = ReorderWrites()
        let store = BoardStore(file: root.appendingPathComponent("Board.json"), writeData: writes.write)
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            guard value() else { fatalError(name) }
            print("PASS \(name)")
        }
        let noteID = store.board.notes[0].id
        let otherID = store.addNote()
        let tasks = [ChecklistItem(text: "Same title"), ChecklistItem(text: "Same title"),
                     ChecklistItem(text: "A wrapped task\nwith a second line"), ChecklistItem(text: "Last 🌱")]
        let ids = tasks.map(\.id)
        store.editNote(noteID) { $0.tasks = tasks; $0.body = "Keep my note"; $0.draft = "Unfinished draft" }
        store.editNote(otherID) { $0.tasks = [ChecklistItem(text: "Another note")] }
        check(store.flushPendingSave(), "reorder fixture saves")
        let initial = store.board
        let count = writes.count
        check(store.moveTask(ids[3], on: noteID, before: ids[1]), "last task moves upward by ID")
        check(store.note(noteID)?.tasks.map(\.id) == [ids[0], ids[3], ids[1], ids[2]], "upward insertion order is exact")
        check(store.flushPendingSave() && writes.count == count + 1, "one committed move produces one structural write")
        check(store.moveTask(ids[0], on: noteID, before: ids[2]), "first task moves downward before a target")
        check(store.note(noteID)?.tasks.map(\.id) == [ids[3], ids[1], ids[0], ids[2]], "downward insertion adjusts after removal")
        check(store.moveTask(ids[3], on: noteID, before: nil), "nil destination moves to the end")
        check(store.note(noteID)?.tasks.map(\.id) == [ids[1], ids[0], ids[2], ids[3]], "duplicate titles remain distinct tasks")
        check(store.flushPendingSave(), "all moves drain before restart")
        let noOpWrites = writes.count
        check(!store.moveTask(ids[3], on: noteID, before: nil)
              && !store.moveTask(ids[0], on: noteID, before: ids[2])
              && !store.moveTask(ids[0], on: noteID, before: ids[0]), "end adjacent and self moves are no-ops")
        check(!store.moveTask(UUID(), on: noteID, before: nil)
              && !store.moveTask(ids[0], on: UUID(), before: nil)
              && !store.moveTask(ids[0], on: noteID, before: UUID())
              && !store.moveTask(ids[0], on: otherID, before: nil), "stale IDs and cross-note moves are rejected")
        check(store.flushPendingSave() && writes.count == noOpWrites, "invalid and unchanged drops do not write")
        let reopened = BoardStore(file: store.file)
        check(reopened.board == store.board && reopened.board.version == 1, "version-one files retain order after reload without migration")
        check(store.note(noteID)?.body == "Keep my note" && store.note(noteID)?.draft == "Unfinished draft"
              && store.note(otherID) == initial.notes.first(where: { $0.id == otherID })
              && store.pendingCount == initial.pendingCount && store.board.archive == initial.archive,
              "reordering preserves other notes drafts bodies archive and counts")
        store.editTask(ids[0], on: noteID, text: "Latest edit survives drop")
        check(store.moveTask(ids[0], on: noteID, before: ids[1]) && store.flushPendingSave(), "drop includes preceding unsaved text")
        check(BoardStore(file: store.file).note(noteID)?.tasks.first?.text == "Latest edit survives drop",
              "moving resolves against the latest task content")
        store.finish(ids[2], on: noteID)
        check(store.board.archive.first?.position == 2, "completion records the reordered position")
        store.restore(ids[2])
        check(store.note(noteID)?.tasks.map(\.id) == ids, "archive restoration uses the reordered position")
        check(store.flushPendingSave(), "archive round trip drains")
        writes.fail = true
        check(store.moveTask(ids[3], on: noteID, before: ids[0]) && !store.flushPendingSave(), "failed reorder save keeps the new order in memory")
        check(store.saveState == .failed && store.note(noteID)?.tasks.first?.id == ids[3], "failed reorder reports save trouble without losing tasks")
        writes.fail = false
        store.retrySave()
        check(store.saveState == .saved && BoardStore(file: store.file).board == store.board, "retry persists the most recent order")
        let settled = writes.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        check(writes.count == settled, "settled reordering schedules no recurring writes")
        try Data("not readable".utf8).write(to: store.file)
        let damaged = BoardStore(file: store.file)
        let preserved = try String(contentsOf: store.file)
        check(!damaged.moveTask(ids[0], on: noteID, before: nil)
              && preserved == "not readable", "reordering cannot overwrite an unreadable legacy file")
    }
}

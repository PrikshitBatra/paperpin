import Foundation

private final class Writes {
    private let lock = NSLock()
    private var snapshots: [Board] = []
    private var shouldFail = false

    var count: Int { lock.lock(); defer { lock.unlock() }; return snapshots.count }
    var last: Board? { lock.lock(); defer { lock.unlock() }; return snapshots.last }
    func failing(_ value: Bool) { lock.lock(); shouldFail = value; lock.unlock() }
    func write(_ data: Data, to file: URL) throws {
        let snapshot = try JSONDecoder().decode(Board.self, from: data)
        lock.lock()
        snapshots.append(snapshot)
        let fail = shouldFail
        lock.unlock()
        if fail { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: file, options: .atomic)
    }
}

@main
enum PersistenceChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ result: @autoclosure () -> Bool, _ name: String) {
            guard result() else { fatalError(name) }
            print("PASS \(name)")
        }
        func pump(_ duration: TimeInterval) {
            RunLoop.current.run(until: Date().addingTimeInterval(duration))
        }
        func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 1) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() && Date() < deadline { pump(0.01) }
            return condition()
        }
        func make(_ name: String, writes: Writes) -> BoardStore {
            BoardStore(file: root.appendingPathComponent(name).appendingPathComponent("Board.json"),
                       writeData: writes.write)
        }

        let batchWrites = Writes()
        let batch = make("batch", writes: batchWrites)
        let initial = batchWrites.count
        let note = batch.board.notes[0].id
        for index in 1...100 { batch.editNote(note) { $0.body = "Typed \(index)" } }
        check(batchWrites.count == initial && batch.saveState == .pending, "typing publishes immediately without writing every keystroke")
        check(batch.note(note)?.body == "Typed 100", "in-memory edits are immediate")
        check(waitFor({ batch.saveState == .saved }), "350 ms debounce saves without a lifecycle flush")
        check(batchWrites.count == initial + 1 && batchWrites.last == batch.board, "one typing burst writes only its latest snapshot")
        pump(0.7)
        check(batchWrites.count == initial + 1, "settled app has no periodic saves")
        batch.editNote(note) { $0.body = "Typed 100" }
        check(batch.saveState == .saved && batchWrites.count == initial + 1, "unchanged edits stay clean")

        let continuousWrites = Writes()
        let continuous = make("continuous", writes: continuousWrites)
        let started = Date()
        var index = 0
        while Date().timeIntervalSince(started) < 2.25 {
            index += 1
            continuous.setQuickDraft("Continuous typing \(index)")
            pump(0.06)
        }
        check(continuousWrites.count >= 2, "continuous typing saves at the two-second maximum delay")
        check(continuousWrites.count <= 3, "continuous typing stays coalesced")
        check(continuous.flushPendingSave(), "lifecycle flush drains the latest snapshot synchronously")
        let flushedBoard = try JSONDecoder().decode(Board.self, from: Data(contentsOf: continuous.file))
        check(flushedBoard == continuous.board,
              "flush persists the last keystroke before quit or sleep")

        let structuralWrites = Writes()
        let structural = make("structural", writes: structuralWrites)
        structural.setQuickDraft("Commit immediately")
        structural.addQuickTask()
        check(waitFor({ structuralWrites.count == 2 }, timeout: 0.2), "task commit submits a save before the text debounce")
        check(structural.flushPendingSave() && structuralWrites.last?.pendingCount == 1,
              "structural save includes preceding unsaved drafts")

        let oldStarted = DispatchSemaphore(value: 0)
        let releaseOld = DispatchSemaphore(value: 0)
        let orderedWrites = Writes()
        let ordered = BoardStore(file: root.appendingPathComponent("ordered/Board.json")) { data, file in
            let snapshot = try JSONDecoder().decode(Board.self, from: data)
            if snapshot.quickDraft == "older" {
                oldStarted.signal()
                _ = releaseOld.wait(timeout: .now() + 3)
                throw CocoaError(.fileWriteNoPermission)
            }
            try orderedWrites.write(data, to: file)
        }
        ordered.setQuickDraft("older")
        pump(0.4)
        check(oldStarted.wait(timeout: .now() + 1) == .success, "earlier snapshot is in flight")
        ordered.setQuickDraft("newest")
        _ = ordered.addNote()
        releaseOld.signal()
        check(ordered.flushPendingSave(), "later successful write wins over an earlier failed snapshot")
        pump(0.1)
        check(ordered.saveState == .saved && ordered.diskIssue == nil && orderedWrites.last == ordered.board,
              "stale queued callbacks cannot overwrite a synchronous flush result")

        let failureWrites = Writes()
        let failing = make("failure", writes: failureWrites)
        failureWrites.failing(true)
        failing.setQuickDraft("Keep this draft")
        check(!failing.flushPendingSave() && failing.saveState == .failed && failing.diskIssue != nil,
              "failed flush preserves edits and reports save failure")
        let attempts = failureWrites.count
        pump(0.5)
        check(failureWrites.count == attempts, "save failure does not start a retry polling loop")
        failureWrites.failing(false)
        failing.retrySave()
        check(failing.saveState == .saved && failing.diskIssue == nil && failureWrites.last == failing.board,
              "explicit retry saves the latest edits and clears the error")

        let removedDirectory = failing.file.deletingLastPathComponent()
        try FileManager.default.removeItem(at: removedDirectory)
        failing.setQuickDraft("Directory restored")
        check(failing.flushPendingSave() && FileManager.default.fileExists(atPath: failing.file.path),
              "save recreates an Application Support directory removed while running")
    }
}

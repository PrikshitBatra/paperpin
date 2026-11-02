import Foundation

// Compile the same harness with the old/new BoardStore. The baseline has no
// flush API: pass -D PAPERPIN_BASELINE when compiling the historical source.
// Atomic replacements are counted by observing the file identity and mtime
// after every edit and run-loop slice; no instrumentation alters either store.
@main
enum TypingBenchmark {
    struct Signature: Equatable {
        let inode: UInt64
        let modified: Date
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Board.json")
        var board = Board()
        board.notes = (0..<20).map { number in
            Sticky(title: "Note \(number)", body: String(repeating: "Baseline text. ", count: 20),
                   tasks: (0..<10).map { ChecklistItem(text: "Task \($0)") })
        }
        try JSONEncoder().encode(board).write(to: file, options: .atomic)
        let store = BoardStore(file: file)
        let id = store.board.notes[0].id
        func signature() throws -> Signature {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            return Signature(inode: (attributes[.systemFileNumber] as! NSNumber).uint64Value,
                             modified: attributes[.modificationDate] as! Date)
        }
        var last = try signature()
        var replacements = 0
        func sample() throws {
            let current = try signature()
            if current != last { replacements += 1; last = current }
        }
        let start = ProcessInfo.processInfo.systemUptime
        for index in 1...300 {
            store.editNote(id) { $0.body = String(repeating: "x", count: index) }
            try sample()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            try sample()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        #if !PAPERPIN_BASELINE
        guard store.flushPendingSave() else { fatalError("Benchmark save failed") }
        #endif
        try sample()
        let restored = try JSONDecoder().decode(Board.self, from: Data(contentsOf: file))
        guard restored == store.board else { fatalError("Final content mismatch") }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("300 keystrokes; 20 notes; 200 tasks; atomic writes observed: \(replacements); elapsed: \(String(format: "%.2f", elapsed)) s")
    }
}

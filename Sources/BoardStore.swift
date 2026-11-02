import Foundation
import Combine

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case butter, sage, rose, blue, lilac
    var id: Self { self }
    var name: String {
        switch self {
        case .butter: return "Butter"
        case .sage: return "Sage"
        case .rose: return "Rose"
        case .blue: return "Sky"
        case .lilac: return "Lilac"
        }
    }
}

struct ChecklistItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
}

struct Sticky: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""
    var color: PaperColor = .butter
    var pinned = false
    var tasks: [ChecklistItem] = []
    var draft = ""

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled sticky" : trimmed
    }
}

struct FinishedTask: Identifiable, Codable, Equatable {
    var task: ChecklistItem
    var noteID: UUID
    var noteTitle: String
    var color: PaperColor
    var position: Int
    var completedAt: Date
    var id: UUID { task.id }
}

struct Board: Codable, Equatable {
    var version = 1
    var notes = [Sticky(title: "Inbox")]
    var archive: [FinishedTask] = []
    var quickDraft = ""
    var destination: UUID?
    var nextColorIndex = 1

    var sortedNotes: [Sticky] { notes.filter(\.pinned) + notes.filter { !$0.pinned } }
    var pendingCount: Int { notes.reduce(0) { $0 + $1.tasks.count } }
}

final class BoardStore: ObservableObject {
    @Published private(set) var board: Board
    @Published private(set) var diskIssue: String?

    let file: URL
    private var fileNeedsRecovery = false
    private let encoder = JSONEncoder()

    static var standardFile: URL {
        #if PAPERPIN_QA
        guard let directory = ProcessInfo.processInfo.environment["PAPERPIN_TEST_DIRECTORY"] else {
            preconditionFailure("An isolated test directory is required for the QA build")
        }
        return URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("Board.json")
        #else
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paperpin", isDirectory: true).appendingPathComponent("Board.json")
        #endif
    }

    init(file: URL = BoardStore.standardFile) {
        self.file = file
        board = Board()
        do {
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode(Board.self, from: data)
            guard decoded.version == 1 else {
                throw CocoaError(.fileReadUnknown)
            }
            board = decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            save()
        } catch {
            fileNeedsRecovery = true
            diskIssue = "Paperpin couldn’t read the saved board. Your original file is preserved. Reopen Paperpin after recovering the file in Finder."
        }
    }

    var sortedNotes: [Sticky] { board.sortedNotes }
    var pendingCount: Int { board.pendingCount }

    var captureNote: Sticky? {
        board.notes.first { $0.id == board.destination } ?? board.notes.first { $0.title == "Inbox" } ?? sortedNotes.first
    }

    func note(_ id: UUID) -> Sticky? { board.notes.first { $0.id == id } }

    private func save() {
        guard !fileNeedsRecovery else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(board)
            try data.write(to: file, options: [.atomic])
            if diskIssue != nil { diskIssue = nil }
        } catch {
            diskIssue = "Your latest edits are in memory. Paperpin couldn’t save them to this Mac. \(error.localizedDescription)"
        }
    }

    func retrySave() { save() }

    private func change(_ action: (inout Board) -> Void) {
        guard !fileNeedsRecovery else { return }
        var updated = board
        action(&updated)
        guard updated != board else { return }
        board = updated
        save()
    }

    @discardableResult
    func addNote() -> UUID {
        let id = UUID()
        change { board in
            let palette = PaperColor.allCases
            board.notes.insert(Sticky(id: id, color: palette[board.nextColorIndex % palette.count]), at: 0)
            board.nextColorIndex = (board.nextColorIndex + 1) % palette.count
        }
        return id
    }

    func editNote(_ id: UUID, _ action: (inout Sticky) -> Void) {
        change { board in
            guard let index = board.notes.firstIndex(where: { $0.id == id }) else { return }
            action(&board.notes[index])
        }
    }

    func editTask(_ id: UUID, on noteID: UUID, text: String) {
        editNote(noteID) { note in
            guard let index = note.tasks.firstIndex(where: { $0.id == id }) else { return }
            note.tasks[index].text = text
        }
    }

    func addDraft(on noteID: UUID) {
        editNote(noteID) { note in
            let text = note.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            note.tasks.append(ChecklistItem(text: text))
            note.draft = ""
        }
    }

    func setQuickDraft(_ value: String) { change { $0.quickDraft = value } }
    func setDestination(_ id: UUID) { change { $0.destination = id } }

    func addQuickTask() {
        let id = captureNote?.id
        change { board in
            let text = board.quickDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let index: Int
            if let found = board.notes.firstIndex(where: { $0.id == id }) {
                index = found
            } else {
                board.notes.insert(Sticky(title: "Inbox"), at: 0)
                index = 0
            }
            board.notes[index].tasks.append(ChecklistItem(text: text))
            board.destination = board.notes[index].id
            board.quickDraft = ""
        }
    }

    func finish(_ taskID: UUID, on noteID: UUID, at date: Date = Date()) {
        change { board in
            guard let n = board.notes.firstIndex(where: { $0.id == noteID }),
                  let t = board.notes[n].tasks.firstIndex(where: { $0.id == taskID }) else { return }
            let note = board.notes[n]
            let task = board.notes[n].tasks.remove(at: t)
            board.archive.insert(FinishedTask(task: task, noteID: noteID, noteTitle: note.displayTitle,
                                             color: note.color, position: t, completedAt: date), at: 0)
        }
    }

    func restore(_ taskID: UUID) {
        change { board in
            guard let index = board.archive.firstIndex(where: { $0.id == taskID }) else { return }
            let item = board.archive.remove(at: index)
            let n: Int
            if let existing = board.notes.firstIndex(where: { $0.id == item.noteID }) {
                n = existing
            } else {
                board.notes.insert(Sticky(id: item.noteID, title: item.noteTitle, color: item.color), at: 0)
                n = 0
            }
            board.notes[n].tasks.insert(item.task, at: min(max(0, item.position), board.notes[n].tasks.count))
        }
    }

    func deleteNote(_ id: UUID) {
        change { board in
            board.notes.removeAll { $0.id == id }
            if board.destination == id { board.destination = nil }
        }
    }
}

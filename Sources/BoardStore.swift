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

enum BoardSaveState: Equatable {
    case saved, pending, saving, failed

    var statusText: String {
        switch self {
        case .saved: return "Saved on this Mac"
        case .pending: return "Unsaved changes"
        case .saving: return "Saving…"
        case .failed: return "Save needs attention"
        }
    }
}

// This queue owns all encoding and file work. It never waits for the main queue,
// so a lifecycle flush can safely drain it before the app sleeps or terminates.
private final class BoardWriter {
    struct Result {
        let attempt: UInt64
        let revision: UInt64
        let error: String?
    }

    private let queue = DispatchQueue(label: "Paperpin.board-writer", qos: .utility)
    private let file: URL
    private let writeData: (Data, URL) throws -> Void
    private var directoryReady = false
    private var latestResult: Result?

    init(file: URL, writeData: @escaping (Data, URL) throws -> Void) {
        self.file = file
        self.writeData = writeData
    }

    func submit(_ snapshot: Board, revision: UInt64, attempt: UInt64,
                completion: @escaping (Result) -> Void) {
        queue.async { [self] in
            let error: String?
            do {
                let data = try JSONEncoder().encode(snapshot)
                try prepareDirectory()
                do {
                    try writeData(data, file)
                } catch let issue as CocoaError where issue.code == .fileNoSuchFile || issue.code == .fileReadNoSuchFile {
                    // The user may have moved the Application Support directory.
                    directoryReady = false
                    try prepareDirectory()
                    try writeData(data, file)
                }
                error = nil
            } catch let issue {
                error = issue.localizedDescription
            }
            let result = Result(attempt: attempt, revision: revision, error: error)
            latestResult = result
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func prepareDirectory() throws {
        if !directoryReady {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            directoryReady = true
        }
    }

    func drain() -> Result? { queue.sync { latestResult } }
}

final class BoardStore: ObservableObject {
    @Published private(set) var board: Board
    @Published private(set) var diskIssue: String?
    @Published private(set) var saveState: BoardSaveState = .saved

    let file: URL
    private var fileNeedsRecovery = false
    private let writer: BoardWriter
    private var revision: UInt64 = 0
    private var savedRevision: UInt64 = 0
    private var submittedRevision: UInt64?
    private var attempt: UInt64 = 0
    private var handledAttempt: UInt64 = 0
    private var debounceSave: DispatchWorkItem?
    private var maximumDelaySave: DispatchWorkItem?

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

    init(file: URL = BoardStore.standardFile,
         writeData: @escaping (Data, URL) throws -> Void = { data, file in
             try data.write(to: file, options: [.atomic])
         }) {
        self.file = file
        writer = BoardWriter(file: file, writeData: writeData)
        board = Board()
        do {
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode(Board.self, from: data)
            guard decoded.version == 1 else {
                throw CocoaError(.fileReadUnknown)
            }
            board = decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            revision = 1
            flushPendingSave()
        } catch {
            fileNeedsRecovery = true
            diskIssue = "Paperpin couldn’t read the saved board. Your original file is preserved. Reopen Paperpin after recovering the file in Finder."
            saveState = .failed
        }
    }

    deinit {
        debounceSave?.cancel()
        maximumDelaySave?.cancel()
    }

    var statusText: String { saveState.statusText }
    var requiresFileRecovery: Bool { fileNeedsRecovery }

    var sortedNotes: [Sticky] { board.sortedNotes }
    var pendingCount: Int { board.pendingCount }

    var captureNote: Sticky? {
        board.notes.first { $0.id == board.destination } ?? board.notes.first { $0.title == "Inbox" } ?? sortedNotes.first
    }

    func note(_ id: UUID) -> Sticky? { board.notes.first { $0.id == id } }

    private func setSaveState(_ value: BoardSaveState) {
        if saveState != value { saveState = value }
    }

    private func scheduleSave() {
        setSaveState(diskIssue == nil ? .pending : .failed)
        debounceSave?.cancel()
        let debounce = DispatchWorkItem { [weak self] in self?.submitSnapshot() }
        debounceSave = debounce
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350), execute: debounce)
        if maximumDelaySave == nil {
            let maximum = DispatchWorkItem { [weak self] in self?.submitSnapshot() }
            maximumDelaySave = maximum
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: maximum)
        }
    }

    private func cancelScheduledSave() {
        debounceSave?.cancel()
        maximumDelaySave?.cancel()
        debounceSave = nil
        maximumDelaySave = nil
    }

    private func submitSnapshot(force: Bool = false) {
        guard !fileNeedsRecovery else { return }
        cancelScheduledSave()
        guard force || (revision > savedRevision && submittedRevision != revision) else { return }
        submittedRevision = revision
        attempt += 1
        setSaveState(.saving)
        writer.submit(board, revision: revision, attempt: attempt) { [weak self] in self?.didSave($0) }
    }

    private func didSave(_ result: BoardWriter.Result) {
        // A synchronous flush may have already acknowledged this completion or a
        // later retry. Older main-queue callbacks must not overwrite that state.
        guard result.attempt > handledAttempt else { return }
        handledAttempt = result.attempt
        if let error = result.error {
            diskIssue = "Your latest edits are in memory. Paperpin couldn’t save them to this Mac. \(error)"
            setSaveState(.failed)
        } else {
            savedRevision = max(savedRevision, result.revision)
            if diskIssue != nil { diskIssue = nil }
            if savedRevision == revision { setSaveState(.saved) }
            else { setSaveState(submittedRevision == revision ? .saving : .pending) }
        }
    }

    /// Call on the main thread before quit, sleep, or discarding an editor.
    /// This waits only for disk work, never for a main-queue completion callback.
    @discardableResult
    func flushPendingSave() -> Bool {
        guard !fileNeedsRecovery else { return false }
        submitSnapshot(force: saveState == .failed)
        if let result = writer.drain() { didSave(result) }
        return savedRevision == revision && diskIssue == nil
    }

    func retrySave() {
        guard !fileNeedsRecovery else { return }
        submitSnapshot(force: true)
        if let result = writer.drain() { didSave(result) }
    }

    private func change(immediate: Bool = true, _ action: (inout Board) -> Void) {
        guard !fileNeedsRecovery else { return }
        var updated = board
        action(&updated)
        guard updated != board else { return }
        revision += 1
        board = updated
        if immediate { submitSnapshot() }
        else { scheduleSave() }
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
        guard !fileNeedsRecovery, let previous = note(id) else { return }
        var updated = previous
        action(&updated)
        let structural = previous.color != updated.color || previous.pinned != updated.pinned
            || previous.tasks.map(\.id) != updated.tasks.map(\.id)
        change(immediate: structural) { board in
            guard let index = board.notes.firstIndex(where: { $0.id == id }) else { return }
            board.notes[index] = updated
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

    func setQuickDraft(_ value: String) { change(immediate: false) { $0.quickDraft = value } }
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

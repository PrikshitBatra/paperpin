import Foundation
import Combine

enum Section: String { case board, archive }
enum BoardField: Hashable { case search, title(UUID), body(UUID), draft(UUID), task(UUID) }

struct FocusRequest: Equatable {
    var field: BoardField
    var noteID: UUID?
    private let nonce = UUID()
    init(_ field: BoardField, note: UUID? = nil) {
        self.field = field
        noteID = note
    }
}

struct Feedback: Identifiable, Equatable {
    var id = UUID()
    var message: String
    var undoTask: UUID?
}

final class Navigation: ObservableObject {
    @Published var section: Section = .board
    @Published var query = ""
    @Published var focusRequest: FocusRequest?
    @Published var feedback: Feedback?
    @Published var floats: Bool {
        didSet { UserDefaults.standard.set(floats, forKey: "FloatBoard") }
    }
    @Published var desktopMode: Bool {
        didSet { UserDefaults.standard.set(desktopMode, forKey: "DesktopMode") }
    }
    @Published var sidebarHidden: Bool {
        didSet { UserDefaults.standard.set(sidebarHidden, forKey: "SidebarHidden") }
    }
    @Published var hotKeyAvailable = false
    @Published var showsNextTask: Bool {
        didSet { UserDefaults.standard.set(showsNextTask, forKey: "ShowNextTask") }
    }

    init() {
        floats = UserDefaults.standard.bool(forKey: "FloatBoard")
        desktopMode = UserDefaults.standard.bool(forKey: "DesktopMode")
        sidebarHidden = UserDefaults.standard.bool(forKey: "SidebarHidden")
        showsNextTask = UserDefaults.standard.bool(forKey: "ShowNextTask")
    }

    func go(_ section: Section) {
        if self.section != section { query = ""; feedback = nil }
        self.section = section
    }

    func reveal(_ id: UUID, editingTitle: Bool) {
        go(.board)
        query = ""
        focusRequest = FocusRequest(editingTitle ? .title(id) : .draft(id), note: id)
    }

    func notify(_ message: String, undoTask: UUID? = nil) {
        let next = Feedback(message: message, undoTask: undoTask)
        feedback = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.feedback?.id == next.id { self?.feedback = nil }
        }
    }
}

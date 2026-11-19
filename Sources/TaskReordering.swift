import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// One native drag at a time. Nothing is observed or scheduled while idle.
final class TaskReorderSession: ObservableObject {
    static let shared = TaskReorderSession()
    static let contentType = UTType(exportedAs: "local.paperpin.task-reorder", conformingTo: .data)
    static let pasteboardType = NSPasteboard.PasteboardType(contentType.identifier)
    struct Item {
        let token = UUID()
        let taskID: UUID
        let noteID: UUID
        let windowNumber: Int
    }
    @Published private(set) var active: Item?
    private weak var store: BoardStore?
    private var changes: AnyCancellable?
    private var closing: NSObjectProtocol?
    weak var target: TaskRowTargetView?
    weak var scrolling: NSScrollView?

    func begin(task: UUID, note: UUID, store: BoardStore, window: NSWindow) -> Item? {
        end()
        guard !store.requiresFileRecovery, store.note(note)?.tasks.contains(where: { $0.id == task }) == true else { return nil }
        self.store = store
        let item = Item(taskID: task, noteID: note, windowNumber: window.windowNumber)
        active = item
        changes = store.$board.sink { [weak self] board in
            guard let self, let active = self.active else { return }
            if board.notes.first(where: { $0.id == active.noteID })?.tasks.contains(where: { $0.id == active.taskID }) != true {
                self.end()
            }
        }
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                         object: window, queue: .main) { [weak self] _ in self?.end() }
        return item
    }

    func accepts(note: UUID, store: BoardStore) -> Bool {
        active?.noteID == note && self.store === store && !store.requiresFileRecovery
    }

    func end(window: NSWindow? = nil) {
        if let window, active?.windowNumber != window.windowNumber { return }
        target?.setMarker(nil)
        target = nil
        scrolling = nil
        changes = nil
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
        store = nil
        if active != nil { active = nil }
    }
}

/// Keep the editable row and its checkbox outside the drag source's hit region.
struct TaskReorderRow<Content: View>: View {
    let task: ChecklistItem
    let noteID: UUID
    let store: BoardStore
    @ViewBuilder let content: Content
    @State private var hovering = false
    @State private var below: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            TaskGrip(task: task, noteID: noteID, store: store, visible: hovering)
                .frame(width: 18, height: 23)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
        }
        .contentShape(Rectangle())
        .background(TaskRowGeometry(taskID: task.id, noteID: noteID, store: store, marker: $below))
        .overlay(alignment: below == true ? .bottom : .top) {
            if below != nil {
                Rectangle().fill(Ink.accent).frame(height: 2)
                    .offset(y: below == true ? 1 : -1).allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onHover { hovering = $0 }
    }
}

/// Geometry only; native editable fields keep all normal mouse hit testing.
final class TaskRowTargetView: NSView {
    static let rows = NSHashTable<TaskRowTargetView>.weakObjects()
    var taskID = UUID()
    var noteID = UUID()
    weak var store: BoardStore?
    var marker: Bool?
    var changed: ((Bool?) -> Void)?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { Self.rows.add(self) }
    }
    func setMarker(_ value: Bool?) {
        guard marker != value else { return }
        marker = value
        changed?(value)
    }
}

private struct TaskRowGeometry: NSViewRepresentable {
    let taskID: UUID
    let noteID: UUID
    let store: BoardStore
    @Binding var marker: Bool?
    func makeNSView(context: Context) -> TaskRowTargetView { TaskRowTargetView() }
    func updateNSView(_ view: TaskRowTargetView, context: Context) {
        view.taskID = taskID; view.noteID = noteID; view.store = store
        view.changed = { marker = $0 }
        view.setAccessibilityElement(false)
    }
}

/// Handling the private type at the hosting boundary lets drops work over both
/// native text fields and SwiftUI labels on macOS 13+, without intercepting edits.
final class TaskReorderHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([TaskReorderSession.pasteboardType])
    }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        let session = TaskReorderSession.shared
        guard let active = session.active, sender.draggingSource is TaskGripView else { return false }
        return sender.draggingPasteboard.string(forType: TaskReorderSession.pasteboardType) == active.token.uuidString
    }
    private func row(at point: NSPoint) -> TaskRowTargetView? {
        TaskRowTargetView.rows.allObjects.first { row in
            // Non-clipping SwiftUI bridges can report a visibleRect as large as
            // their entire scroll view. Always constrain it to this row's bounds.
            row.window === window && !row.isHiddenOrHasHiddenAncestor
                && row.bounds.insetBy(dx: 0, dy: -1.5).intersection(row.visibleRect)
                    .contains(row.convert(point, from: nil))
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        let session = TaskReorderSession.shared
        let candidate = row(at: sender.draggingLocation)
        let valid = candidate.flatMap { row -> TaskRowTargetView? in
            guard let store = row.store, session.accepts(note: row.noteID, store: store),
                  store.note(row.noteID)?.tasks.contains(where: { $0.id == row.taskID }) == true else { return nil }
            return row
        }
        if session.target !== valid { session.target?.setMarker(nil); session.target = valid }
        if let valid {
            let point = valid.convert(sender.draggingLocation, from: nil)
            valid.setMarker(valid.taskID == session.active?.taskID ? nil : point.y > valid.bounds.midY)
            session.scrolling = valid.enclosingScrollView
        }
        // AppKit calls draggingUpdated while a drag is active, even with a
        // stationary pointer. Native clip scrolling needs no application timer.
        if let scroll = session.scrolling, scroll.window === window {
            let clip = scroll.contentView
            let point = clip.convert(sender.draggingLocation, from: nil)
            if clip.bounds.contains(point) {
                let delta: CGFloat = point.y < clip.bounds.minY + 22 ? -10 : (point.y > clip.bounds.maxY - 22 ? 10 : 0)
                if delta != 0 {
                    let next = clip.constrainBoundsRect(clip.bounds.offsetBy(dx: 0, dy: delta))
                    clip.scroll(to: next.origin)
                    scroll.reflectScrolledClipView(clip)
                }
            }
        }
        return valid == nil ? [] : .move
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        TaskReorderSession.shared.target?.setMarker(nil)
        TaskReorderSession.shared.target = nil
        TaskReorderSession.shared.scrolling = nil
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { TaskReorderSession.shared.end() }
        let session = TaskReorderSession.shared
        guard accepts(sender), let source = session.active,
              let row = row(at: sender.draggingLocation), let store = row.store,
              session.accepts(note: row.noteID, store: store),
              let tasks = store.note(row.noteID)?.tasks,
              let index = tasks.firstIndex(where: { $0.id == row.taskID }) else { return false }
        guard source.taskID != row.taskID else { return true }
        let below = row.convert(sender.draggingLocation, from: nil).y > row.bounds.midY
        let destination = below ? tasks.dropFirst(index + 1).first?.id : row.taskID
        _ = store.moveTask(source.taskID, on: row.noteID, before: destination)
        return true
    }
}

final class TaskReorderHostingController<Content: View>: NSViewController {
    private let rootView: Content
    init(rootView: Content) { self.rootView = rootView; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { view = TaskReorderHostingView(rootView: rootView) }
}

private struct TaskGrip: NSViewRepresentable {
    let task: ChecklistItem
    let noteID: UUID
    let store: BoardStore
    let visible: Bool
    func makeNSView(context: Context) -> TaskGripView { TaskGripView() }
    func updateNSView(_ view: TaskGripView, context: Context) {
        view.taskID = task.id
        view.noteID = noteID
        view.store = store
        view.title = task.displayText
        view.shown = visible
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        view.needsDisplay = true
        view.setAccessibilityLabel("Reorder \(task.displayText)")
        view.setAccessibilityHelp("Drag to reorder within this note. Right-click or press Return for Move Up and Move Down.")
        view.setAccessibilityIdentifier("TaskGrip-\(task.id.uuidString)")
        view.setAccessibilityElement(view.canMoveUp || view.canMoveDown)
    }
}

/// Only this narrow handle starts a native drag; editors retain their gestures.
final class TaskGripView: NSView, NSDraggingSource {
    var taskID = UUID()
    var noteID = UUID()
    weak var store: BoardStore?
    var title = ""
    var shown = false
    private var token: UUID?
    override var acceptsFirstResponder: Bool { canMoveUp || canMoveDown }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var index: Int? { store?.note(noteID)?.tasks.firstIndex { $0.id == taskID } }
    var canMoveUp: Bool { !((store?.requiresFileRecovery) ?? true) && (index ?? 0) > 0 }
    var canMoveDown: Bool {
        guard let index, let store, !store.requiresFileRecovery else { return false }
        return index + 1 < (store.note(noteID)?.tasks.count ?? 0)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard (shown || window?.firstResponder === self), canMoveUp || canMoveDown else { return }
        NSColor.secondaryLabelColor.setFill()
        for x: CGFloat in [6, 11] {
            for y: CGFloat in [7, 11, 15] {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2)).fill()
            }
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).stroke()
        }
    }
    override func resetCursorRects() { if canMoveUp || canMoveDown { addCursorRect(bounds, cursor: .openHand) } }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) {
        guard canMoveUp || canMoveDown, let store, let window,
              let item = TaskReorderSession.shared.begin(task: taskID, note: noteID, store: store, window: window) else { return }
        window.makeFirstResponder(self)
        token = item.token
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(item.token.uuidString, forType: TaskReorderSession.pasteboardType)
        let drag = NSDraggingItem(pasteboardWriter: pasteboard)
        let size = NSSize(width: 240, height: 32)
        let previewTitle = title
        let preview = NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            (previewTitle as NSString).draw(in: rect.insetBy(dx: 10, dy: 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
            return true
        }
        let point = convert(event.locationInWindow, from: nil)
        drag.setDraggingFrame(NSRect(x: point.x - 220, y: point.y - 16, width: size.width, height: size.height), contents: preview)
        let session = beginDraggingSession(with: [drag], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = AppearanceSettings.shared.policy.animationsAllowed
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication && TaskReorderSession.shared.active?.token == token ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if TaskReorderSession.shared.active?.token == token { TaskReorderSession.shared.end() }
        token = nil
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let token, TaskReorderSession.shared.active?.token == token { TaskReorderSession.shared.end() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func rightMouseDown(with event: NSEvent) { showMenu() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: showMenu()
        case 126: _ = moveTaskUp()
        case 125: _ = moveTaskDown()
        default: super.keyDown(with: event)
        }
    }
    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, selector, enabled) in [("Move Up", #selector(menuMoveUp), canMoveUp),
                                           ("Move Down", #selector(menuMoveDown), canMoveDown)] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; item.isEnabled = enabled; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }
    @objc private func menuMoveUp() { _ = moveTaskUp() }
    @objc private func menuMoveDown() { _ = moveTaskDown() }
    @objc func moveTaskUp() -> Bool {
        guard canMoveUp, let index, let tasks = store?.note(noteID)?.tasks else { return false }
        return store?.moveTask(taskID, on: noteID, before: tasks[index - 1].id) ?? false
    }
    @objc func moveTaskDown() -> Bool {
        guard canMoveDown, let index, let tasks = store?.note(noteID)?.tasks else { return false }
        return store?.moveTask(taskID, on: noteID, before: tasks.dropFirst(index + 2).first?.id) ?? false
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { showMenu(); return true }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if canMoveUp { actions.append(NSAccessibilityCustomAction(name: "Move Up", target: self, selector: #selector(moveTaskUp))) }
        if canMoveDown { actions.append(NSAccessibilityCustomAction(name: "Move Down", target: self, selector: #selector(moveTaskDown))) }
        return actions
    }
}

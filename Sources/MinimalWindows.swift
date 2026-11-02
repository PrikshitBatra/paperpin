import AppKit
import SwiftUI
import Combine

/// Presentation state deliberately lives outside Board.json: every window edits the original sticky.
final class MinimalWindowCoordinator: NSObject, NSWindowDelegate {
    private(set) var windows: [UUID: NSWindow] = [:]
    private(set) var enabled = false
    private(set) var savedOpenNoteIDs: [UUID]
    private let store: BoardStore
    private let navigation: Navigation
    private let openBoard: () -> Void
    private let defaults: UserDefaults
    private var frames: [String: String]
    private var subscriptions: Set<AnyCancellable> = []
    private var windowSubscriptions: [UUID: AnyCancellable] = [:]
    private var screenObserver: NSObjectProtocol?
    private var pendingGeometrySave: DispatchWorkItem?
    private var terminating = false
    private let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    init(store: BoardStore, navigation: Navigation, openBoard: @escaping () -> Void,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.navigation = navigation
        self.openBoard = openBoard
        self.defaults = defaults
        savedOpenNoteIDs = (defaults.stringArray(forKey: "MinimalOpenNotes") ?? []).compactMap(UUID.init(uuidString:))
        frames = defaults.dictionary(forKey: "MinimalWindowFrames") as? [String: String] ?? [:]
        super.init()
        store.$board.map { Set($0.notes.map(\.id)) }.removeDuplicates()
            .sink { [weak self] ids in self?.removeDeletedNotes(existing: ids) }
            .store(in: &subscriptions)
        AppearanceSettings.shared.$glassEnabled
            .combineLatest(AppearanceSettings.shared.$lowPowerMode, AppearanceSettings.shared.$reduceTransparency)
            .map { enabled, lowPower, reduceTransparency in enabled && !lowPower && !reduceTransparency }
            .removeDuplicates()
            .sink { [weak self] glass in self?.updateWindowAppearance(glass: glass) }
            .store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recoverWindowPositions() }
    }

    deinit {
        pendingGeometrySave?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            // A failed load exposes a placeholder board, not the user's notes.
            // Keep their saved window selection untouched until the file is recovered.
            guard !store.requiresFileRecovery else { return }
            if !defaults.bool(forKey: "MinimalModeInitialized") {
                defaults.set(true, forKey: "MinimalModeInitialized")
                let id = store.board.notes.first(where: { $0.title == "Inbox" })?.id
                    ?? store.sortedNotes.first?.id ?? store.addNote()
                savedOpenNoteIDs = store.note(id) == nil ? [] : [id]
                persistPresentation()
            }
            for id in savedOpenNoteIDs { showNote(id, activate: false) }
        } else {
            flushAndPersist()
            // Closing a presentation must not mean the user chose to hide its sticky.
            for window in windows.values {
                window.delegate = nil
                window.close()
                window.contentView = nil
            }
            windows.removeAll()
            windowSubscriptions.removeAll()
        }
    }

    func showNote(_ id: UUID, activate: Bool = true) {
        guard enabled, !store.requiresFileRecovery, let note = store.note(id) else { return }
        if !savedOpenNoteIDs.contains(id) {
            savedOpenNoteIDs.append(id)
            persistPresentation()
        }
        let window: NSWindow
        if let existing = windows[id] { window = existing }
        else {
            let model = MinimalNoteModel(note: note, store: store)
            let sticky = DesktopStickyWindow(contentRect: initialFrame(for: id),
                styleMask: [.borderless, .resizable, .closable], backing: .buffered, defer: false)
            sticky.title = note.displayTitle
            sticky.setAccessibilityLabel("Desktop sticky: \(note.displayTitle)")
            sticky.isReleasedWhenClosed = false
            sticky.isMovableByWindowBackground = false
            sticky.tabbingMode = .disallowed
            sticky.hasShadow = true
            sticky.canHide = false
            sticky.isExcludedFromWindowsMenu = true
            sticky.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle,
                                         .fullScreenNone, .fullScreenDisallowsTiling]
            sticky.delegate = self
            let hosting = NSHostingView(rootView: MinimalStickyView(
                model: model,
                close: { [weak sticky] in sticky?.performClose(nil) },
                openBoard: { [weak self] in
                    self?.openBoard()
                    self?.navigation.reveal(id, editingTitle: false)
                }))
            // The window owns its resize limits; SwiftUI's inferred fitting size must not replace them.
            hosting.sizingOptions = []
            let content = NSView(frame: NSRect(origin: .zero, size: sticky.frame.size))
            hosting.frame = content.bounds
            hosting.autoresizingMask = [.width, .height]
            content.addSubview(hosting)
            // A direct NSHostingView window root resets AppKit's minimum to its inferred zero size.
            // The plain container keeps sizing ownership in AppKit, including after SwiftUI updates.
            sticky.contentView = content
            sticky.minSize = NSSize(width: 200, height: 160)
            sticky.contentMinSize = NSSize(width: 200, height: 160)
            windows[id] = sticky
            windowSubscriptions[id] = model.$note.map(\.displayTitle).removeDuplicates()
                .sink { [weak sticky] title in
                    sticky?.title = title
                    sticky?.setAccessibilityLabel("Desktop sticky: \(title)")
                }
            applyAppearance(to: sticky, glass: AppearanceSettings.shared.effectiveGlass)
            window = sticky
        }
        window.level = activate ? .normal : desktopLevel
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isKeyWindow, let content = window.contentView else { return }
                content.layoutSubtreeIfNeeded()
                if let editor = Self.bodyEditor(in: content) { window.makeFirstResponder(editor) }
            }
        } else {
            window.orderFrontRegardless()
        }
    }

    private static func bodyEditor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.isEditable, editor.accessibilityLabel() == "Note text" {
            return editor
        }
        for child in view.subviews {
            if let editor = bodyEditor(in: child) { return editor }
        }
        return nil
    }

    func parkOnDesktop() {
        for window in windows.values { window.level = desktopLevel }
    }

    func flushAndPersist() {
        store.flushPendingSave()
        pendingGeometrySave?.cancel()
        pendingGeometrySave = nil
        for (id, window) in windows { frames[id.uuidString] = NSStringFromRect(window.frame) }
        persistPresentation()
    }

    /// Call only after quitting has been accepted, so a cancelled quit keeps normal close behavior.
    func prepareForTermination() {
        flushAndPersist()
        terminating = true
    }

    func windowWillClose(_ notification: Notification) {
        // AppKit closes remaining windows during shutdown; those are still selected for next launch.
        guard !terminating else { return }
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        store.flushPendingSave()
        frames[id.uuidString] = NSStringFromRect(window.frame)
        savedOpenNoteIDs.removeAll { $0 == id }
        windows.removeValue(forKey: id)
        windowSubscriptions.removeValue(forKey: id)
        persistPresentation()
    }

    func windowDidResignKey(_ notification: Notification) {
        store.flushPendingSave()
        (notification.object as? NSWindow)?.level = desktopLevel
    }

    func windowDidMove(_ notification: Notification) { scheduleGeometrySave() }
    func windowDidResize(_ notification: Notification) { scheduleGeometrySave() }
    func windowDidEndLiveResize(_ notification: Notification) { flushAndPersist() }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(200, frameSize.width), height: max(160, frameSize.height))
    }

    private func scheduleGeometrySave() {
        pendingGeometrySave?.cancel()
        let pending = DispatchWorkItem { [weak self] in self?.flushAndPersist() }
        pendingGeometrySave = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: pending)
    }

    private func persistPresentation() {
        let ids = savedOpenNoteIDs.map(\.uuidString)
        if defaults.stringArray(forKey: "MinimalOpenNotes") != ids {
            defaults.set(ids, forKey: "MinimalOpenNotes")
        }
        if defaults.dictionary(forKey: "MinimalWindowFrames") as? [String: String] != frames {
            defaults.set(frames, forKey: "MinimalWindowFrames")
        }
    }

    private func removeDeletedNotes(existing: Set<UUID>) {
        guard !store.requiresFileRecovery else { return }
        let removed = savedOpenNoteIDs.filter { !existing.contains($0) }
        guard !removed.isEmpty else { return }
        for id in removed {
            if let window = windows.removeValue(forKey: id) {
                window.delegate = nil
                window.close()
            }
            windowSubscriptions.removeValue(forKey: id)
            frames.removeValue(forKey: id.uuidString)
        }
        savedOpenNoteIDs.removeAll { !existing.contains($0) }
        persistPresentation()
    }

    private func initialFrame(for id: UUID) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let offset = CGFloat(windows.count % 8) * 28
        let defaultFrame = NSRect(x: screen.minX + 32 + offset, y: screen.maxY - 452 - offset,
                                  width: 320, height: 420)
        let frame = frames[id.uuidString].map(NSRectFromString) ?? defaultFrame
        return Self.constrainedFrame(frame, to: NSScreen.screens.map(\.visibleFrame))
    }

    func recoverWindowPositions() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        for window in windows.values {
            let adjusted = Self.constrainedFrame(window.frame, to: screens)
            if window.frame != adjusted { window.setFrame(adjusted, display: true) }
        }
        flushAndPersist()
    }

    /// Also used by geometry checks, including simulated display disconnection.
    static func constrainedFrame(_ proposed: NSRect, to screens: [NSRect]) -> NSRect {
        let candidates = screens.filter { !$0.isEmpty && !$0.isNull }
        guard !candidates.isEmpty else { return proposed }
        let frame: NSRect
        if [proposed.minX, proposed.minY, proposed.width, proposed.height].allSatisfy({ $0.isFinite }),
           proposed.width > 0, proposed.height > 0 {
            frame = proposed
        } else {
            frame = NSRect(x: candidates[0].minX + 32, y: candidates[0].maxY - 452, width: 320, height: 420)
        }
        func overlap(_ screen: NSRect) -> CGFloat {
            let intersection = frame.intersection(screen)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let screen = candidates.max { lhs, rhs in
            let left = overlap(lhs), right = overlap(rhs)
            if left != right { return left < right }
            let ld = pow(frame.midX - lhs.midX, 2) + pow(frame.midY - lhs.midY, 2)
            let rd = pow(frame.midX - rhs.midX, 2) + pow(frame.midY - rhs.midY, 2)
            return ld > rd
        }!
        let width = min(max(frame.width, 200), screen.width)
        let height = min(max(frame.height, 160), screen.height)
        return NSRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }

    private func updateWindowAppearance(glass: Bool) {
        for window in windows.values { applyAppearance(to: window, glass: glass) }
    }

    private func applyAppearance(to window: NSWindow, glass: Bool) {
        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
        window.appearance = glass ? nil : NSAppearance(named: .aqua)
    }
}

private final class DesktopStickyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            level = .normal
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    override func performClose(_ sender: Any?) { close() }
}

/// Only this note's value and save failures invalidate its editor, not unrelated board changes.
private final class MinimalNoteModel: ObservableObject {
    @Published private(set) var note: Sticky
    @Published private(set) var diskIssue: String?
    let store: BoardStore
    private var subscriptions: Set<AnyCancellable> = []

    init(note: Sticky, store: BoardStore) {
        self.note = note
        self.store = store
        diskIssue = store.diskIssue
        store.$board.compactMap { board in board.notes.first { $0.id == note.id } }.removeDuplicates()
            .sink { [weak self] note in self?.note = note }.store(in: &subscriptions)
        store.$diskIssue.removeDuplicates().sink { [weak self] in self?.diskIssue = $0 }
            .store(in: &subscriptions)
    }

    func binding(_ key: WritableKeyPath<Sticky, String>) -> Binding<String> {
        Binding(get: { self.note[keyPath: key] }, set: { value in
            self.store.editNote(self.note.id) { $0[keyPath: key] = value }
        })
    }
}

enum MinimalNoteLayout {
    static let emptyBodyHeight: CGFloat = 38

    static func bodyHeight(measuredHeight: CGFloat, availableHeight: CGFloat, hasChecklist: Bool) -> CGFloat {
        let available = max(0, availableHeight)
        let minimum = min(emptyBodyHeight, available)
        let maximum = hasChecklist ? max(minimum, available * 0.45) : available
        return min(max(minimum, measuredHeight), maximum)
    }
}

private struct MinimalStickyView: View {
    @ObservedObject var model: MinimalNoteModel
    @ObservedObject private var appearance = AppearanceSettings.shared
    let close: () -> Void
    let openBoard: () -> Void
    @State private var addingTask = false
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var measuredBodyHeight = MinimalNoteLayout.emptyBodyHeight
    @State private var bodyFocusRequest = 0
    @FocusState private var draftFocused: Bool
    @Environment(\.colorScheme) private var systemScheme

    private var note: Sticky { model.note }
    private var hasChecklist: Bool { addingTask || !note.tasks.isEmpty || !note.draft.isEmpty }
    private var stripHeight: CGFloat { appearance.effectiveGlass ? 30 : 20 }
    private var cornerRadius: CGFloat { appearance.effectiveGlass ? GlassStyle.windowCornerRadius : 0 }
    private var contentFontSize: CGFloat { NoteContentStyle.fontSize(glass: appearance.effectiveGlass) }

    var body: some View {
        GeometryReader { geometry in
            let invitation = note.body.isEmpty && !hasChecklist
            let available = max(0, geometry.size.height - stripHeight
                - (model.diskIssue == nil ? 0 : 32) - (invitation ? 30 : 0))
            let bodyHeight = MinimalNoteLayout.bodyHeight(measuredHeight: measuredBodyHeight,
                                                         availableHeight: available,
                                                         hasChecklist: hasChecklist)
            VStack(spacing: 0) {
                dragStrip
                if let issue = model.diskIssue {
                    Button { openBoard() } label: {
                        Label("Save needs attention", systemImage: "exclamationmark.circle")
                            .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Ink.warning).padding(.horizontal, 10)
                        .frame(height: 32).help(issue)
                }
                MinimalBodyEditor(text: model.binding(\.body), fontSize: contentFontSize,
                                  focusRequest: bodyFocusRequest, measuredHeight: $measuredBodyHeight)
                    .frame(maxWidth: .infinity).frame(height: bodyHeight)
                    .overlay(alignment: .topLeading) {
                        if note.body.isEmpty {
                            Text("Write a note…").font(.system(size: contentFontSize))
                                .foregroundStyle(Ink.secondary).padding(.leading, 15).padding(.top, 8)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                if hasChecklist {
                    checklist.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    if invitation {
                        Button(action: beginTask) {
                            Label("Add a task", systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
                            .padding(.horizontal, 15).frame(height: 30)
                            .accessibilityLabel("Add first task")
                    }
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { bodyFocusRequest += 1 }
                }
            }
        }
        .foregroundStyle(Ink.text)
        .background {
            if appearance.effectiveGlass {
                GlassCardBackground(cornerRadius: cornerRadius)
            }
        }
        .paperSurface(color: note.color.paper, cornerRadius: cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(appearance.effectiveGlass ? GlassStyle.line : Ink.text.opacity(0.2), lineWidth: 1)
            .allowsHitTesting(false))
        .environment(\.colorScheme, appearance.effectiveGlass ? systemScheme : .light)
        .alert("Rename sticky", isPresented: $renaming) {
            TextField("Title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { model.store.editNote(note.id) { $0.title = titleDraft } }
        }
    }

    private var dragStrip: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                    .frame(width: appearance.effectiveGlass ? 17 : 23, height: appearance.effectiveGlass ? 17 : 20)
                    .background(Circle().fill(appearance.effectiveGlass ? GlassStyle.controlFill : .clear))
                    .frame(width: appearance.effectiveGlass ? 30 : 23, height: stripHeight)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help("Hide this sticky")
                .accessibilityLabel("Hide desktop sticky \(note.displayTitle)")
            WindowDragStrip().overlay {
                HStack(spacing: 6) {
                    if appearance.effectiveGlass { Circle().fill(note.color.glassAccent).frame(width: 5, height: 5) }
                    Text(note.title).font(.system(size: appearance.effectiveGlass ? 11 : 10, weight: .medium)).lineLimit(1)
                }.padding(.horizontal, 4).allowsHitTesting(false)
            }
            Menu {
                Button("Add Task", action: beginTask)
                Button("Rename…") { titleDraft = note.title; renaming = true }
                Menu("Paper Color") {
                    ForEach(PaperColor.allCases) { color in
                        Button {
                            model.store.editNote(note.id) { $0.color = color }
                        } label: {
                            if note.color == color { Label(color.name, systemImage: "checkmark") }
                            else { Text(color.name) }
                        }
                    }
                }
                Divider()
                Button("Open in Board", action: openBoard)
                Button("Hide Sticky", action: close)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                    .frame(width: appearance.effectiveGlass ? 17 : 23, height: appearance.effectiveGlass ? 17 : 20)
                    .background(Circle().fill(appearance.effectiveGlass ? GlassStyle.controlFill : .clear))
                    .frame(width: appearance.effectiveGlass ? 30 : 23, height: stripHeight)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Desktop sticky options")
        }
        .frame(height: stripHeight)
        .background(appearance.effectiveGlass ? GlassStyle.chromeFill : note.color.marker.opacity(0.25))
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 0.5) }
    }

    private func beginTask() {
        addingTask = true
        DispatchQueue.main.async { draftFocused = true }
    }

    private func commitDraft() {
        model.store.addDraft(on: note.id)
        draftFocused = true
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Ink.text.opacity(0.13)).frame(height: 1).padding(.horizontal, 15)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NoteContentStyle.rowSpacing) {
                    ForEach(note.tasks) { task in
                        ChecklistRow(label: task.displayText, complete: {
                            model.store.finish(task.id, on: note.id)
                        }) {
                            TextField("", text: Binding(get: {
                                model.note.tasks.first { $0.id == task.id }?.text ?? ""
                            }, set: { model.store.editTask(task.id, on: note.id, text: $0) }),
                                      prompt: Text("Untitled task"), axis: .vertical)
                                .accessibilityLabel("Task text")
                        }
                    }
                    TaskDraftRow(draft: note.draft, commit: commitDraft) {
                        TextField("", text: model.binding(\.draft))
                            .focused($draftFocused)
                            .accessibilityLabel("Add a task to \(note.displayTitle)")
                            .onSubmit { commitDraft() }
                    }
                }.padding(.horizontal, 15).padding(.top, 8).padding(.bottom, 7)
            }
        }
        .accessibilityIdentifier("MinimalChecklistRegion")
    }
}

private struct WindowDragStrip: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// Native text editing preserves selection, IME composition, and undo across store publications.
private struct MinimalBodyEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let focusRequest: Int
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MeasuringTextScrollView {
        let scroll = MeasuringTextScrollView()
        scroll.identifier = NSUserInterfaceItemIdentifier("MinimalBodyEditorScroll")
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let editor = NSTextView()
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: fontSize)
        editor.textContainerInset = NSSize(width: 10, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Note text")
        editor.identifier = NSUserInterfaceItemIdentifier("MinimalBodyEditorText")
        editor.string = text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        context.coordinator.scroll = scroll
        scroll.onMeasuredHeight = { [weak coordinator = context.coordinator] height in
            coordinator?.queueMeasuredHeight(height)
        }
        return scroll
    }

    func updateNSView(_ scroll: MeasuringTextScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        editor.textColor = NSColor(Ink.text)
        editor.insertionPointColor = NSColor(Ink.text)
        if editor.font?.pointSize != fontSize { editor.font = .systemFont(ofSize: fontSize) }
        if editor.string != text && !editor.hasMarkedText() {
            let range = editor.selectedRange()
            // Undo registrations refer to offsets in the old buffer. Applying
            // a board/other-window edit must not let those operations corrupt it.
            editor.undoManager?.removeAllActions()
            editor.string = text
            let length = (text as NSString).length
            let start = min(range.location, length)
            editor.setSelectedRange(NSRange(location: start, length: min(range.length, length - start)))
        }
        scroll.measureContentHeight()
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window?.isKeyWindow == true else { return }
                editor.window?.makeFirstResponder(editor)
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                editor.scrollRangeToVisible(editor.selectedRange())
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MinimalBodyEditor
        weak var scroll: MeasuringTextScrollView?
        var lastFocusRequest = 0
        private var latestMeasuredHeight: CGFloat?
        private var heightUpdateQueued = false
        init(_ parent: MinimalBodyEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            scroll?.measureContentHeight()
        }

        func queueMeasuredHeight(_ height: CGFloat) {
            latestMeasuredHeight = height
            guard !heightUpdateQueued else { return }
            heightUpdateQueued = true
            // Native layout may run while SwiftUI is updating. Commit once after this layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.heightUpdateQueued = false
                if let height = self.latestMeasuredHeight, abs(self.parent.measuredHeight - height) > 0.5 {
                    self.parent.measuredHeight = height
                }
            }
        }
    }

    final class MeasuringTextScrollView: NSScrollView {
        var onMeasuredHeight: ((CGFloat) -> Void)?
        private var previousHeight: CGFloat?

        override func layout() {
            super.layout()
            measureContentHeight()
        }

        func measureContentHeight() {
            guard contentSize.width > 20, let editor = documentView as? NSTextView,
                  let container = editor.textContainer, let manager = editor.layoutManager else { return }
            // TextKit lays out against the editor's current viewport width, including wrapped lines.
            if abs(editor.frame.width - contentSize.width) > 0.5 {
                editor.setFrameSize(NSSize(width: contentSize.width, height: editor.frame.height))
            }
            manager.ensureLayout(for: container)
            var used = manager.usedRect(for: container).maxY
            if manager.extraLineFragmentTextContainer === container {
                used = max(used, manager.extraLineFragmentRect.maxY)
            }
            let lineHeight = manager.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: 18))
            let height = max(MinimalNoteLayout.emptyBodyHeight,
                             ceil(max(lineHeight, used) + editor.textContainerInset.height * 2))
            guard previousHeight == nil || abs(previousHeight! - height) > 0.5 else { return }
            previousHeight = height
            onMeasuredHeight?(height)
        }
    }
}

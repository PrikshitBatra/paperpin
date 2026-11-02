import AppKit

private func taskField(in view: NSView, text: String) -> NSTextField? {
    if let field = view as? NSTextField, field.stringValue == text { return field }
    for child in view.subviews {
        if let field = taskField(in: child, text: text) { return field }
    }
    return nil
}

private func checkboxFrame(in root: NSView, task: String) -> NSRect? {
    var visited: Set<ObjectIdentifier> = []
    func find(_ object: AnyObject) -> NSRect? {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
        if let element = object as? NSAccessibilityProtocol {
            if element.accessibilityLabel() == "Complete \(task)" {
                let frame = element.accessibilityFrame()
                if !frame.isEmpty { return frame }
            }
            for child in element.accessibilityChildren() ?? [] {
                if let frame = find(child as AnyObject) { return frame }
            }
        }
        if let view = object as? NSView {
            for child in view.subviews {
                if let frame = find(child) { return frame }
            }
        }
        return nil
    }
    return find(root)
}

private func firstBaselineY(_ field: NSTextField) -> CGFloat {
    let localY = field.isFlipped ? field.bounds.minY + field.firstBaselineOffsetFromTop
        : field.bounds.maxY - field.firstBaselineOffsetFromTop
    let point = field.convert(NSPoint(x: field.bounds.midX, y: localY), to: nil)
    return field.window!.convertToScreen(NSRect(origin: point, size: .zero)).minY
}

@MainActor
private func checkChecklistParity(board: NSWindow, desktop: NSWindow, titles: [String],
                                  directory: URL, check: (Bool, String) -> Void) async {
    for (name, glass) in [("paper", false), ("glass", true)] {
        AppearanceSettings.shared.glassEnabled = glass
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(400)
        guard let boardView = board.contentView, let desktopView = desktop.contentView,
              let boardFirst = taskField(in: boardView, text: titles[0]),
              let boardSecond = taskField(in: boardView, text: titles[1]),
              let boardWrapped = taskField(in: boardView, text: titles[2]),
              let desktopFirst = taskField(in: desktopView, text: titles[0]),
              let desktopSecond = taskField(in: desktopView, text: titles[1]),
              let desktopWrapped = taskField(in: desktopView, text: titles[2]),
              let boardFont = boardFirst.font, let desktopFont = desktopFirst.font else {
            check(false, "\(name) native board and desktop checklist editors are available"); continue
        }
        check(abs(boardFont.pointSize - desktopFont.pointSize) < 0.1
              && boardFont.fontName == desktopFont.fontName
              && boardSecond.font == desktopSecond.font && boardWrapped.font == desktopWrapped.font,
              "\(name) desktop task typography matches the board's native task fields")
        let boardPitch = firstBaselineY(boardFirst) - firstBaselineY(boardSecond)
        let desktopPitch = firstBaselineY(desktopFirst) - firstBaselineY(desktopSecond)
        check(boardPitch > boardFont.pointSize && abs(boardPitch - desktopPitch) <= 1.5,
              "\(name) desktop task rows use the board's line spacing")

        if let boardBox = checkboxFrame(in: boardView, task: titles[0]),
           let desktopBox = checkboxFrame(in: desktopView, task: titles[0]) {
            let boardOffset = boardBox.midY - firstBaselineY(boardFirst)
            let desktopOffset = desktopBox.midY - firstBaselineY(desktopFirst)
            check(abs(boardOffset - desktopOffset) <= 1.5
                  && abs(desktopOffset - desktopFont.xHeight / 2) <= 3.5,
                  "\(name) desktop checkbox aligns with the first text line like the board")
        } else {
            print("UNAVAILABLE \(name) virtual checkbox bounds; alignment captured in paired screenshots")
        }
        if let boardBox = checkboxFrame(in: boardView, task: titles[2]),
           let desktopBox = checkboxFrame(in: desktopView, task: titles[2]) {
            let boardOffset = boardBox.midY - firstBaselineY(boardWrapped)
            let desktopOffset = desktopBox.midY - firstBaselineY(desktopWrapped)
            check(boardWrapped.bounds.height > boardFont.pointSize * 1.8
                  && desktopWrapped.bounds.height > desktopFont.pointSize * 1.8
                  && abs(boardOffset - desktopOffset) <= 1.5
                  && abs(desktopOffset - desktopFont.xHeight / 2) <= 3.5,
                  "\(name) wrapped tasks keep their checkbox beside the first line")
        } else {
            check(boardWrapped.bounds.height > boardFont.pointSize * 1.8
                  && desktopWrapped.bounds.height > desktopFont.pointSize * 1.8,
                  "\(name) paired screenshots include genuinely wrapped task text")
        }
        snapshot(board, directory.appendingPathComponent("checklist-board-\(name).png"))
        snapshot(desktop, directory.appendingPathComponent("checklist-desktop-\(name).png"))
    }
}

@MainActor
func checkPolish(_ delegate: AppDelegate, directory: URL, check: (Bool, String) -> Void) async {
    let store = delegate.store
    let coordinator = delegate.minimalWindows!
    if ProcessInfo.processInfo.environment["PAPERPIN_VERIFY_RELAUNCH"] == "1" {
        check(delegate.navigation.minimalMode && coordinator.windows.count == 1, "polished note presentation restores")
        if let window = coordinator.windows.values.first, let editor = nativeEditor(in: window.contentView!) {
            check(editor.string.isEmpty && (editor.enclosingScrollView?.contentView.bounds.height ?? 999) <= 52,
                  "task-only note stays compact after relaunch")
        } else { check(false, "restored editor exists") }
        return
    }

    let noteID = store.board.notes[0].id
    let taskTitles = ["Sketch the first idea", "Review the details",
                      "Gather the sketches and feedback into one clear draft before sharing the next version with the team.",
                      "Make room for a break", "Plan tomorrow"]
    store.editNote(noteID) { note in
        note.title = "Today"
        note.body = ""
        note.color = .blue
        note.tasks = taskTitles.map { ChecklistItem(text: $0) }
    }
    delegate.navigation.minimalMode = true
    coordinator.showNote(noteID)
    await pause(400)
    guard let window = coordinator.windows[noteID], let content = window.contentView,
          let editor = nativeEditor(in: content), let scroll = editor.enclosingScrollView else {
        check(false, "native body editor is mounted"); return
    }
    window.setContentSize(NSSize(width: 340, height: 440))
    await pause(250)
    let emptyHeight = scroll.contentView.bounds.height
    check(emptyHeight <= 52 && emptyHeight >= 28, "empty note is a slim usable input")
    if let task = taskField(in: content, text: taskTitles[0]) {
        let top = window.convertToScreen(content.convert(content.bounds, to: nil)).maxY
        let offset = top - window.convertToScreen(task.convert(task.bounds, to: nil)).maxY
        check(offset < 110, "task-only note starts tasks directly below the note hint")
    } else { check(false, "first task editor exists") }
    snapshot(window, directory.appendingPathComponent("polish-tasks-paper.png"))

    store.editNote(noteID) { $0.body = "A small note." }
    await pause(250)
    let shortHeight = scroll.contentView.bounds.height
    check(shortHeight <= 60, "one-line body uses only its required space")
    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    editor.insertText(" A next step.", replacementRange: NSRange(location: NSNotFound, length: 0))
    await pause(250)
    let editedText = editor.string
    let selection = editor.selectedRange()
    store.flushPendingSave()
    AppearanceSettings.shared.glassEnabled = true
    window.setContentSize(NSSize(width: 360, height: 460))
    await pause(300)
    check(nativeEditor(in: content) === editor && window.firstResponder === editor,
          "layout and glass changes retain the native editor and keyboard focus")
    check(editor.selectedRange() == selection && editor.undoManager?.canUndo == true,
          "layout and glass changes preserve selection and undo history")
    check(store.note(noteID)?.body == editedText && store.saveState == .saved,
          "layout does not rewrite or dirty the note")
    AppearanceSettings.shared.glassEnabled = false
    window.setContentSize(NSSize(width: 340, height: 440))
    store.editNote(noteID) { $0.body = "One idea.\nOne clear next step.\nA little space to think." }
    await pause(250)
    let multilineHeight = scroll.contentView.bounds.height
    check(multilineHeight > shortHeight + 20, "body grows for additional lines")

    store.editNote(noteID) { $0.body = "A thoughtful sentence that wraps naturally as the desktop note becomes narrower." }
    window.setContentSize(NSSize(width: 460, height: 560))
    await pause(250)
    let wideHeight = scroll.contentView.bounds.height
    window.setContentSize(NSSize(width: 240, height: 560))
    await pause(250)
    check(scroll.contentView.bounds.height > wideHeight, "body remeasures when narrower text wraps")
    window.setContentSize(NSSize(width: 460, height: 560))
    await pause(250)
    check(abs(scroll.contentView.bounds.height - wideHeight) < 2, "widening the window shrinks wrapped body again")

    window.setContentSize(NSSize(width: 340, height: 440))
    store.editNote(noteID) { $0.body = Array(repeating: "Long notes remain editable and scroll without pushing away tasks.", count: 35).joined(separator: "\n") }
    await pause(250)
    check(scroll.contentView.bounds.height < window.frame.height * 0.60, "long body leaves room for checklist")
    check(editor.frame.height > scroll.contentView.bounds.height, "long body remains independently scrollable")
    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    editor.insertText("\nA last thought.", replacementRange: NSRange(location: NSNotFound, length: 0))
    await pause(250)
    check(store.note(noteID)?.body.hasSuffix("A last thought.") == true, "native editing still reaches long-note content")

    editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
    editor.insertText("", replacementRange: editor.selectedRange())
    await pause(250)
    check(store.note(noteID)?.body.isEmpty == true && scroll.contentView.bounds.height <= 52,
          "deleting text shrinks editor back to its hint")
    editor.undoManager?.undo()
    await pause(250)
    check(store.note(noteID)?.body.isEmpty == false && scroll.contentView.bounds.height > 52,
          "undo restores body text and its layout")
    store.editNote(noteID) { $0.body = "" }

    let mixedID = store.addNote()
    store.editNote(mixedID) {
        $0.title = "Make something good"
        $0.color = .lilac
        $0.body = "Less noise. More room for the ideas that matter."
        $0.tasks = [ChecklistItem(text: "Explore a fresh direction"), ChecklistItem(text: "Keep the details simple")]
    }
    let ideaID = store.addNote()
    store.editNote(ideaID) {
        $0.title = "Little reminders"
        $0.color = .rose
        $0.body = "Finish one thing before starting the next.\n\nLeave some space for a good idea."
    }
    delegate.showWindow()
    delegate.window.setContentSize(NSSize(width: 1120, height: 700))
    await pause(250)
    await checkChecklistParity(board: delegate.window, desktop: window, titles: taskTitles,
                               directory: directory, check: check)
    AppearanceSettings.shared.glassEnabled = true
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
        NSApp.appearance = NSAppearance(named: appearance)
        await pause(450)
        snapshot(delegate.window, directory.appendingPathComponent("polish-board-\(name).png"))
        snapshot(window, directory.appendingPathComponent("polish-tasks-\(name).png"))
        check(window.isOpaque == !AppearanceSettings.shared.effectiveGlass, "\(name) glass window retains correct compositing")
    }
    coordinator.showNote(mixedID)
    await pause(250)
    if let mixed = coordinator.windows[mixedID] {
        snapshot(mixed, directory.appendingPathComponent("polish-mixed-dark.png"))
        mixed.performClose(nil)
    }
    AppearanceSettings.shared.glassEnabled = false
    NSApp.appearance = nil
    window.setContentSize(NSSize(width: 200, height: 160))
    await pause(250)
    check(scroll.contentView.bounds.height <= 52 && window.frame.size == NSSize(width: 200, height: 160),
          "compact task-only window remains usable")
    snapshot(window, directory.appendingPathComponent("polish-compact.png"))
    window.setContentSize(NSSize(width: 340, height: 440))
    coordinator.flushAndPersist()
}

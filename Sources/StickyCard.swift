import SwiftUI

extension ChecklistItem {
    var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled task" : text
    }
}

struct StickyCard: View {
    let note: Sticky
    @ObservedObject var store: BoardStore
    @ObservedObject var navigation: Navigation
    let focus: FocusState<BoardField?>.Binding
    let delete: () -> Void

    private func binding(_ key: WritableKeyPath<Sticky, String>) -> Binding<String> {
        Binding(get: { store.note(note.id)?[keyPath: key] ?? "" },
                set: { value in store.editNote(note.id) { $0[keyPath: key] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Capsule().fill(note.color.marker).frame(width: 23, height: 4)
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Ink.secondary)
                        .accessibilityLabel("Pinned")
                }
                Spacer()
                Menu {
                    Button {
                        store.editNote(note.id) { $0.pinned.toggle() }
                    } label: { Label(note.pinned ? "Unpin sticky" : "Pin to top", systemImage: "pin") }
                    Menu("Paper color") {
                        ForEach(PaperColor.allCases) { color in
                            Button {
                                store.editNote(note.id) { $0.color = color }
                            } label: {
                                if note.color == color { Label(color.name, systemImage: "checkmark") }
                                else { Text(color.name) }
                            }
                        }
                    }
                    Divider()
                    Button("Delete sticky…", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 20).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(Ink.secondary)
                .accessibilityLabel("Options for \(note.displayTitle)").help("Sticky options")
            }
            .padding(.bottom, 9)

            TextField("", text: binding(\.title))
                .legiblePrompt("Untitled sticky", visible: note.title.isEmpty)
                .textFieldStyle(.plain).font(.custom("Georgia", size: 24)).foregroundStyle(Ink.text)
                .focused(focus, equals: .title(note.id)).accessibilityLabel("Sticky title")
                .onSubmit { focus.wrappedValue = .body(note.id) }

            // Let the paper grow with the text. Longer notes scroll in their editor.
            Text(verbatim: note.body + "\u{200B}")
                .font(.system(size: 13)).lineLimit(16).fixedSize(horizontal: false, vertical: true)
                .hidden().accessibilityHidden(true)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
                .overlay {
                    TextEditor(text: binding(\.body))
                        .font(.system(size: 13)).foregroundStyle(Ink.text)
                        .scrollContentBackground(.hidden).padding(.horizontal, -5)
                        .focused(focus, equals: .body(note.id)).accessibilityLabel("Note text")
                }
                .legiblePrompt("Write a note…", visible: note.body.isEmpty)
                .font(.system(size: 13)).padding(.top, 8)

            Rectangle().fill(Ink.text.opacity(0.13)).frame(height: 1).padding(.top, 15).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(note.tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TaskCheck(label: task.displayText) {
                            store.finish(task.id, on: note.id)
                            navigation.notify("Task archived", undoTask: task.id)
                        }.alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4.5 }
                        TextField("", text: Binding(get: {
                            store.note(note.id)?.tasks.first { $0.id == task.id }?.text ?? ""
                        }, set: { store.editTask(task.id, on: note.id, text: $0) }),
                                  prompt: Text("Untitled task"), axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Ink.text)
                            .lineLimit(1...12).fixedSize(horizontal: false, vertical: true)
                            .focused(focus, equals: .task(task.id))
                            .accessibilityLabel("Task text")
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        .frame(width: 21).foregroundStyle(Ink.secondary)
                    TextField("", text: binding(\.draft))
                        .legiblePrompt("Add a task…", visible: note.draft.isEmpty)
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Ink.text)
                        .focused(focus, equals: .draft(note.id)).accessibilityLabel("Add a task to \(note.displayTitle)")
                        .onSubmit { commitDraft() }
                    if !note.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: commitDraft) {
                            Image(systemName: "return").font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 19).background(RoundedRectangle(cornerRadius: 4).fill(Ink.text.opacity(0.09)))
                        }.buttonStyle(.plain).accessibilityLabel("Add task").help("Add task (Return)")
                    }
                }.frame(minHeight: 25)
            }
            Spacer(minLength: 20)
            Text("\(note.tasks.count) pending")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.secondary)
                .accessibilityLabel("\(note.tasks.count) pending tasks")
        }
        .padding(.horizontal, 19).padding(.top, 14).padding(.bottom, 15)
        .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                PaperShape().fill(note.color.paper)
                PaperShape().stroke(note.color.marker.opacity(0.3), lineWidth: 0.8)
                PaperFold().fill(note.color.fold).frame(width: 19, height: 19)
            }
            .shadow(color: .black.opacity(0.055), radius: 3, x: 0, y: 2)
        }
        .environment(\.colorScheme, .light)
    }

    private func commitDraft() {
        store.addDraft(on: note.id)
        focus.wrappedValue = .draft(note.id)
    }
}

struct NewStickyTile: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).stroke(Ink.faint.opacity(0.5), lineWidth: 1.15)
                        .frame(width: 25, height: 28).rotationEffect(.degrees(-10)).offset(x: -3, y: 1)
                    RoundedRectangle(cornerRadius: 3).fill(Ink.canvas).frame(width: 25, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.faint, lineWidth: 1.15))
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.secondary)
                }.frame(width: 40, height: 38)
                Text("New sticky").font(.system(size: 13, weight: .medium))
                Text("⌘ N").font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Ink.line, lineWidth: 1))
            }
            .foregroundStyle(Ink.faint).frame(maxWidth: .infinity, minHeight: 212)
            .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Ink.sidebar : Ink.canvas))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.faint.opacity(0.36),
                    style: StrokeStyle(lineWidth: 1, dash: [4,4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel("Create a new sticky")
    }
}

import SwiftUI

struct QuickPanel: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var navigation: Navigation
    @ObservedObject private var appearance = AppearanceSettings.shared
    let openBoard: (UUID?) -> Void
    let openArchive: () -> Void
    let close: () -> Void
    @FocusState private var entering: Bool
    private var notesWithTasks: [Sticky] { store.sortedNotes.filter { !$0.tasks.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(nsImage: PaperArt.mark).resizable().frame(width: 26, height: 26)
                Text("Paperpin").font(appearance.effectiveGlass
                    ? .system(size: 17, weight: .semibold, design: .rounded) : .custom("Georgia-Bold", size: 17))
                Spacer()
                Menu {
                    BoardLayoutOptions(navigation: navigation)
                    Divider()
                    Toggle("Show next task in menu bar", isOn: $navigation.showsNextTask)
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 24, height: 26)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Board and menu bar options").help("Board and menu bar options")
                Button(action: openArchive) {
                    Image(systemName: "archivebox").frame(width: 26, height: 26)
                }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
                    .accessibilityLabel("Open archive").help("Open archive")
            }.padding(.horizontal, 17).padding(.top, 12)
            HStack(spacing: 8) {
                Text("Pending tasks").font(appearance.effectiveGlass
                    ? .system(size: 25, weight: .semibold, design: .rounded) : .custom("Georgia", size: 26))
                CountBadge(count: store.pendingCount)
                Spacer()
            }.padding(.horizontal, 19).padding(.top, 14).padding(.bottom, 12)
            Rectangle().fill(Ink.line).frame(height: 1)
            if store.pendingCount == 0 {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle").font(.system(size: 25, weight: .light))
                        .foregroundStyle(Ink.greenDot)
                    Text("All caught up").font(appearance.effectiveGlass
                        ? .system(size: 20, weight: .medium, design: .rounded) : .custom("Georgia", size: 20))
                    Text("Add your next task below.").font(.system(size: 12)).foregroundStyle(Ink.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(notesWithTasks) { note in
                            Button { openBoard(note.id) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(appearance.effectiveGlass ? note.color.glassAccent : note.color.marker).frame(width: 7, height: 7)
                                    Text(note.displayTitle).lineLimit(1).font(.system(size: 11, weight: .semibold))
                                    Image(systemName: "arrow.up.right").font(.system(size: 8))
                                }
                            }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
                                .help("Open \(note.displayTitle) on the board").padding(.top, 12).padding(.bottom, 5)
                            ForEach(note.tasks) { task in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    TaskCheck(label: task.displayText) {
                                        store.finish(task.id, on: note.id)
                                        navigation.notify("Task archived", undoTask: task.id)
                                    }.alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4.5 }
                                    Text(task.displayText).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 1)
                            }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Ink.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Add to").font(.system(size: 11)).foregroundStyle(Ink.secondary)
                    Menu {
                        ForEach(store.sortedNotes) { note in
                            Button {
                                store.setDestination(note.id)
                                entering = true
                            } label: {
                                if store.captureNote?.id == note.id { Label(note.displayTitle, systemImage: "checkmark") }
                                else { Text(note.displayTitle) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(appearance.effectiveGlass ? (store.captureNote?.color ?? .butter).glassAccent : (store.captureNote?.color ?? .butter).marker)
                                .frame(width: 6, height: 6)
                            Text(store.captureNote?.displayTitle ?? "Inbox").lineLimit(1)
                        }
                    }.menuStyle(.borderlessButton).fixedSize().frame(maxWidth: 193, alignment: .leading)
                        .font(.system(size: 11, weight: .semibold)).accessibilityLabel("Destination sticky")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    TextField("", text: Binding(get: { store.board.quickDraft }, set: store.setQuickDraft))
                        .legiblePrompt("Add a task…", visible: store.board.quickDraft.isEmpty, color: Ink.faint)
                        .textFieldStyle(.plain).font(.system(size: 13)).focused($entering)
                        .accessibilityLabel("Quick task").onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                            .frame(width: 27, height: 24).foregroundStyle(Ink.onAccent)
                            .background(RoundedRectangle(cornerRadius: 5).fill(appearance.effectiveGlass ? GlassStyle.actionFill : Ink.accent))
                    }.buttonStyle(.plain).disabled(store.board.quickDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Add quick task").help("Add task (Return)")
                }.padding(.leading, 10).padding(.trailing, 4).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: appearance.effectiveGlass ? 10 : 7, style: .continuous).fill(Ink.surface))
                    .overlay(RoundedRectangle(cornerRadius: appearance.effectiveGlass ? 10 : 7, style: .continuous)
                        .stroke(entering ? Ink.accent : Ink.line, lineWidth: 1))
            }.padding(.horizontal, 17).padding(.vertical, 12)
            HStack {
                Button { openBoard(nil) } label: {
                    Label("Open board", systemImage: "macwindow")
                        .font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.plain).foregroundStyle(Ink.accent)
                Spacer()
                if store.diskIssue != nil {
                    Button("Save issue") { openBoard(nil) }.buttonStyle(.plain).foregroundColor(Ink.warning)
                } else if let id = navigation.feedback?.undoTask, store.board.archive.contains(where: { $0.id == id }) {
                    Button("Undo check-off") { store.restore(id); navigation.feedback = nil }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Ink.accent)
                } else if navigation.hotKeyAvailable {
                    Text("⌃⌥Space").font(.system(size: 10)).foregroundStyle(Ink.faint)
                        .help("Toggle this panel from any app")
                }
            }.padding(.horizontal, 18).frame(height: 36).background(Ink.sidebar.opacity(appearance.effectiveGlass ? 0.65 : 1))
        }
        .frame(width: 348, height: 412).foregroundStyle(Ink.text)
        .paperSurface(color: Ink.canvas, cornerRadius: appearance.effectiveGlass ? GlassStyle.windowCornerRadius : 10)
        .onExitCommand(perform: close)
        .onAppear { DispatchQueue.main.async { entering = true } }
    }

    private func add() {
        store.addQuickTask()
        entering = true
    }
}

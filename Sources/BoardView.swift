import SwiftUI

struct BoardView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var navigation: Navigation
    let openQuick: () -> Void
    @FocusState private var focus: BoardField?
    @State private var deleting: Sticky?

    private var isBoard: Bool { navigation.section == .board }
    private var search: String { navigation.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [Sticky] {
        guard !search.isEmpty else { return store.sortedNotes }
        return store.sortedNotes.filter { note in
            ([note.displayTitle, note.body] + note.tasks.map(\.text)).contains { $0.localizedStandardContains(search) }
        }
    }
    private var archiveMatches: [FinishedTask] {
        guard !search.isEmpty else { return store.board.archive }
        return store.board.archive.filter {
            $0.task.displayText.localizedStandardContains(search) ||
                (store.note($0.noteID)?.displayTitle ?? $0.noteTitle).localizedStandardContains(search)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if !navigation.sidebarHidden {
                sidebar.frame(width: 192)
                Rectangle().fill(Ink.line).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(Ink.line).frame(height: 1)
                if let issue = store.diskIssue { diskNotice(issue) }
                content
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Ink.canvas)
        }
        .foregroundStyle(Ink.text).tint(Ink.accent)
        .ignoresSafeArea()
        .alert(item: $deleting) { note in
            Alert(title: Text("Delete “\(note.displayTitle)”?"),
                  message: Text("This removes the sticky and its pending tasks. Completed tasks stay in the archive."),
                  primaryButton: .destructive(Text("Delete sticky")) { store.deleteNote(note.id) },
                  secondaryButton: .cancel())
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(nsImage: PaperArt.mark).resizable().frame(width: 34, height: 34)
                Text("Paperpin").font(.custom("Georgia-Bold", size: 22))
            }.padding(.leading, 17).padding(.top, navigation.desktopMode ? 24 : 48)
            Eyebrow(text: "Library").padding(.leading, 22).padding(.top, 39).padding(.bottom, 10)
            navRow(.board, title: "Sticky board", symbol: "square.grid.2x2", count: store.board.notes.count)
            navRow(.archive, title: "Archive", symbol: "archivebox", count: store.board.archive.count)
            Spacer()
            Button(action: openQuick) {
                HStack(spacing: 7) {
                    Image(systemName: "menubar.rectangle").frame(width: 17)
                    Text("Quick panel")
                    Spacer(minLength: 1)
                    if navigation.hotKeyAvailable {
                        Text("⌃⌥Space").font(.system(size: 9, weight: .medium))
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                .padding(.horizontal, 18).frame(height: 30)
                .help("Show pending tasks and add a task from the menu bar")
            if navigation.desktopMode {
                Label("On desktop", systemImage: "desktopcomputer")
                    .font(.system(size: 12)).foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 18).frame(height: 30)
            } else {
                Toggle(isOn: $navigation.floats) {
                    HStack(spacing: 7) {
                        Image(systemName: "macwindow.on.rectangle").frame(width: 17)
                        Text("Keep on top")
                    }
                }.toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 18).frame(height: 30)
                    .help("Keep the board above other windows")
            }
            Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, 18).padding(.top, 13)
            HStack(spacing: 7) {
                Circle().fill(store.diskIssue == nil ? Ink.greenDot : Ink.warning).frame(width: 6, height: 6)
                Text(store.diskIssue == nil ? "Saved on this Mac" : "Save needs attention")
                    .font(.system(size: 11))
            }.foregroundStyle(Ink.secondary).padding(.horizontal, 21).padding(.vertical, 17)
        }.frame(maxHeight: .infinity).background(Ink.sidebar)
    }

    private func navRow(_ section: Section, title: String, symbol: String, count: Int) -> some View {
        Button {
            focus = nil
            navigation.go(section)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 17)
                Text(title).font(.system(size: 13, weight: navigation.section == section ? .semibold : .regular))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                CountBadge(count: count).fixedSize()
            }
            .padding(.horizontal, 10).frame(height: 35)
            .background(RoundedRectangle(cornerRadius: 7).fill(navigation.section == section ? Ink.selected : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
            .accessibilityLabel(title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            Eyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            HStack(spacing: 12) {
                Text(isBoard ? "Sticky board" : "Archive").font(.custom("Georgia", size: 40))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Menu {
                    BoardLayoutOptions(navigation: navigation)
                    if navigation.sidebarHidden {
                        Divider()
                        Button(isBoard ? "Open archive" : "Open sticky board") {
                            navigation.go(isBoard ? .archive : .board)
                        }
                    }
                } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 15))
                        .frame(width: 25, height: 26)
                }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(Ink.secondary)
                    .accessibilityLabel("Board layout").help("Board layout")
                Button(action: newNote) { Label("New sticky", systemImage: "plus") }.buttonStyle(ActionStyle())
                    .help("Create a sticky (⌘N)")
            }
            HStack(spacing: 10) {
                Text(isBoard
                     ? "\(plural(store.board.notes.count, "sticky", "stickies"))  ·  \(store.pendingCount) pending"
                     : plural(store.board.archive.count, "completed task", "completed tasks"))
                    .font(.system(size: 13)).foregroundStyle(Ink.secondary).fixedSize()
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                    TextField("", text: $navigation.query)
                        .legiblePrompt(isBoard ? "Search board" : "Search archive", visible: navigation.query.isEmpty, color: Ink.faint)
                        .textFieldStyle(.plain).font(.system(size: 12)).focused($focus, equals: .search)
                        .accessibilityLabel(isBoard ? "Search board" : "Search archive")
                        .onExitCommand { navigation.query = ""; focus = nil }
                    if !navigation.query.isEmpty {
                        Button { navigation.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    } else {
                        Text("⌘F").font(.system(size: 10))
                    }
                }.foregroundStyle(Ink.faint).padding(.horizontal, 9).frame(maxWidth: 171).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Ink.surface))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(focus == .search ? Ink.accent : Ink.line, lineWidth: 1))
            }
        }.padding(.horizontal, 30).padding(.top, navigation.desktopMode ? 21 : 45).padding(.bottom, 20)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isBoard {
                    if matches.isEmpty && !search.isEmpty {
                        EmptyViewMessage(symbol: "magnifyingglass", title: "No matching stickies",
                                         detail: "Try a different word from a title, note, or task.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 246, maximum: 440), spacing: 18, alignment: .top)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(matches) { note in
                                StickyCard(note: note, store: store, navigation: navigation, focus: $focus,
                                           delete: { deleting = note }).id(note.id)
                            }
                            if search.isEmpty { NewStickyTile(action: newNote) }
                        }.padding(.horizontal, 30).padding(.top, 25).padding(.bottom, 56)
                    }
                } else {
                    ArchiveView(entries: archiveMatches, filtering: !search.isEmpty, store: store, navigation: navigation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: navigation.focusRequest) { request in
                guard let request else { return }
                // Wait for the new grid contents and any previously offscreen card.
                DispatchQueue.main.async {
                    if let id = request.noteID { proxy.scrollTo(id, anchor: .top) }
                    DispatchQueue.main.async { focus = request.field }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback = navigation.feedback {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.circle").font(.system(size: 13))
                    Text(feedback.message).font(.system(size: 12, weight: .medium))
                    if let task = feedback.undoTask, store.board.archive.contains(where: { $0.id == task }) {
                        Button("Undo") { store.restore(task); navigation.feedback = nil }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .bold)).underline()
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10).background(Capsule().fill(Ink.accent))
                    .foregroundStyle(Ink.onAccent).shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.bottom, 16)
            }
        }
    }

    private func diskNotice(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle")
            Text(message).font(.system(size: 12))
            Spacer()
            Button("Show file") { NSWorkspace.shared.activateFileViewerSelecting([store.file]) }
            Button("Retry save") { store.retrySave() }
        }.padding(10).foregroundStyle(Ink.warning).background(Ink.surface)
    }

    private func newNote() {
        let id = store.addNote()
        navigation.reveal(id, editingTitle: true)
    }
}

struct BoardLayoutOptions: View {
    @ObservedObject var navigation: Navigation

    var body: some View {
        Toggle("Desktop mode", isOn: $navigation.desktopMode)
        Button(navigation.sidebarHidden ? "Show sidebar" : "Hide sidebar") {
            navigation.sidebarHidden.toggle()
        }
    }
}

struct EmptyViewMessage: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(Ink.accent)
                .frame(width: 54, height: 54).background(Circle().fill(Ink.selected))
            Text(title).font(.custom("Georgia", size: 24)).foregroundStyle(Ink.text)
            Text(detail).font(.system(size: 13)).foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 32).padding(.vertical, 60).frame(maxWidth: .infinity)
    }
}

struct ArchiveView: View {
    let entries: [FinishedTask]
    let filtering: Bool
    @ObservedObject var store: BoardStore
    @ObservedObject var navigation: Navigation

    var body: some View {
        if entries.isEmpty {
            EmptyViewMessage(symbol: filtering ? "magnifyingglass" : "archivebox",
                             title: filtering ? "No matching tasks" : "No completed tasks yet",
                             detail: filtering ? "Try another task or sticky name." : "Check off a task on your board and you’ll find it here.")
        } else {
            let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.completedAt) }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Eyebrow(text: dayLabel(day)).padding(.top, 11).padding(.bottom, 3)
                    ForEach(groups[day] ?? []) { entry in
                        let source = store.note(entry.noteID)
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.greenDot)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.task.displayText).font(.system(size: 14, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 5) {
                                    Circle().fill((source?.color ?? entry.color).marker).frame(width: 6, height: 6)
                                    Text(source?.displayTitle ?? entry.noteTitle).lineLimit(1)
                                    Text("·")
                                    Text(entry.completedAt.formatted(date: .omitted, time: .shortened))
                                }.font(.system(size: 11)).foregroundStyle(Ink.secondary)
                            }
                            Spacer()
                            Button {
                                store.restore(entry.id)
                                navigation.notify("Restored to \(store.note(entry.noteID)?.displayTitle ?? entry.noteTitle)")
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward").font(.system(size: 12, weight: .medium))
                            }.buttonStyle(.plain).foregroundStyle(Ink.accent)
                                .help("Return this task to its sticky")
                        }.padding(.horizontal, 15).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Ink.surface))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.line, lineWidth: 1))
                    }
                }
            }.padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 56)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .long, time: .omitted)
    }
}

import SwiftUI

struct RemindersNoteMenu: View {
    @ObservedObject var reminders: RemindersStore
    let noteID: UUID
    @Binding var showingConnection: Bool
    var body: some View {
        if reminders.connected(to: noteID) {
            Menu("Apple Reminders") {
                Button("Refresh") { reminders.refresh() }
                Button("Change List…") { showingConnection = true }
                Button("Open Apple Reminders") { RemindersActions.openApp() }
                Divider()
                Button("Disconnect") { reminders.disconnect() }
            }
        } else {
            Button("Connect Apple Reminders…") { showingConnection = true }
        }
    }
}

enum RemindersActions {
    static func openApp() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app")) }
    static func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") { NSWorkspace.shared.open(url) }
    }
}

struct RemindersConnectionSheet: View {
    @ObservedObject var reminders: RemindersStore
    let noteID: UUID
    let noteTitle: String
    var presentation: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect Apple Reminders", systemImage: "checklist")
                .font(.system(size: 20, weight: .semibold))
            Text("View and complete a list in “\(noteTitle)”. Your Paperpin tasks stay separate. Editing and recurring schedules stay in Apple Reminders.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let existing = reminders.state.connection, existing.noteID != noteID {
                Text("This will move the existing Reminders connection to this note.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if reminders.state.authorization == .allowed {
                if reminders.state.lists.isEmpty && !reminders.state.refreshing {
                    Text("No Reminders lists are available on this Mac.").font(.system(size: 13))
                } else {
                    Picker("List", selection: $selectedID) {
                        Text("Choose a list…").tag("")
                        ForEach(reminders.state.lists) { list in
                            Text("\(list.title) · \(list.account)\(list.writable ? "" : " (read-only)")").tag(list.id)
                        }
                    }.accessibilityLabel("Apple Reminders list")
                }
            } else if !reminders.state.refreshing {
                Text(reminders.state.problem?.localizedDescription ?? "Allow Reminders access to choose a list.")
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings", action: RemindersActions.openPrivacy)
            }
            if reminders.state.refreshing { Text("Loading available lists…").font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack {
                Button("Refresh") { reminders.prepareConnection() }.disabled(reminders.state.refreshing)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") {
                    guard let list = reminders.state.lists.first(where: { $0.id == selectedID }) else { return }
                    reminders.connect(noteID: noteID, list: list)
                    if let presentation { reminders.setSelectedTab("reminders", noteID: noteID, presentation: presentation) }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
                    .disabled(reminders.state.authorization != .allowed || !reminders.state.lists.contains(where: { $0.id == selectedID }))
            }
        }.padding(24).frame(width: 420)
            .onAppear { selectedID = reminders.state.connection?.listID ?? ""; reminders.prepareConnection() }
            .onChange(of: reminders.state.lists) { lists in
                if !lists.contains(where: { $0.id == selectedID }) {
                    // A name is a suggestion in this explicit picker, never an automatic reconnection.
                    selectedID = lists.first(where: { $0.title.caseInsensitiveCompare("Main Work") == .orderedSame })?.id ?? ""
                }
            }
    }
}

/// Tab state is keyed by presentation, so a desktop tab never changes the board's tab.
struct ConnectedNoteContent<Local: View>: View {
    let reminders: RemindersStore
    @StateObject private var host: ReminderHostObservation
    let noteID: UUID
    let presentation: String
    var reminderSearchMatch = false
    var scrollingReminders = false
    var contentInset: CGFloat = 0
    var localFocusRequest = 0
    @ViewBuilder let local: Local
    @State private var selection = "tasks"

    init(reminders: RemindersStore, noteID: UUID, presentation: String, reminderSearchMatch: Bool = false,
         scrollingReminders: Bool = false, contentInset: CGFloat = 0, localFocusRequest: Int = 0,
         @ViewBuilder local: () -> Local) {
        self.reminders = reminders; self.noteID = noteID; self.presentation = presentation
        self.reminderSearchMatch = reminderSearchMatch; self.scrollingReminders = scrollingReminders
        self.contentInset = contentInset; self.localFocusRequest = localFocusRequest; self.local = local()
        _host = StateObject(wrappedValue: ReminderHostObservation(store: reminders, noteID: noteID))
    }

    private var tabBinding: Binding<String> {
        Binding(get: { selection }, set: {
            selection = $0
            reminders.setSelectedTab($0, noteID: noteID, presentation: presentation)
        })
    }
    var body: some View {
        if host.connected {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    Picker("Note tasks", selection: tabBinding) {
                        Text("Tasks").tag("tasks")
                        Text("Apple Reminders Tasks").tag("reminders")
                    }.labelsHidden().pickerStyle(.segmented).controlSize(.small)
                        .font(.system(size: 11)).fixedSize(horizontal: true, vertical: false)
                    Picker("", selection: tabBinding) {
                        Text("Tasks").tag("tasks")
                        Text("Apple Reminders Tasks").tag("reminders")
                    }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityLabel("Task source").padding(.horizontal, contentInset)
                if selection == "reminders" {
                    if scrollingReminders {
                        ScrollView { RemindersListView(reminders: reminders).padding(.horizontal, contentInset).padding(.bottom, 12) }
                    } else { RemindersListView(reminders: reminders) }
                } else { local }
            }
            .onAppear {
                selection = reminderSearchMatch ? "reminders" : reminders.selectedTab(noteID: noteID, presentation: presentation)
            }
            .onChange(of: reminderSearchMatch) { match in if match { tabBinding.wrappedValue = "reminders" } }
            .onChange(of: localFocusRequest) { _ in tabBinding.wrappedValue = "tasks" }
        } else { local }
    }
}

struct RemindersListView: View {
    @ObservedObject var reminders: RemindersStore
    var compact = false
    @State private var showingConnection = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(compact ? "Apple Reminders · \(reminders.state.connection?.listTitle ?? "List")"
                     : (reminders.state.connection?.listTitle ?? "Apple Reminders"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
                Button { reminders.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(reminders.state.refreshing)
                    .accessibilityLabel("Refresh Apple Reminders").help("Refresh Apple Reminders")
                Menu {
                    Button("Open Apple Reminders", action: RemindersActions.openApp)
                    Button("Change List…") { showingConnection = true }
                    Button("Disconnect") { reminders.disconnect() }
                } label: { Image(systemName: "ellipsis").frame(width: 18) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Apple Reminders options")
            }.foregroundStyle(Ink.secondary)
            if let problem = reminders.state.problem {
                VStack(alignment: .leading, spacing: 6) {
                    Text(problem.localizedDescription).fixedSize(horizontal: false, vertical: true)
                    if problem == .denied { Button("Open Privacy Settings", action: RemindersActions.openPrivacy) }
                    else if problem == .missingList { Button("Choose List…") { showingConnection = true } }
                    else if problem != .restricted && problem != .readOnly { Button("Try Again") { reminders.refresh() } }
                }.font(.system(size: 11)).foregroundStyle(Ink.warning)
            }
            if reminders.state.refreshing {
                Text("Refreshing…").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            }
            if reminders.state.items.isEmpty && !reminders.state.refreshing && reminders.state.problem == nil {
                Text("No pending reminders").font(.system(size: 13)).foregroundStyle(Ink.secondary).padding(.vertical, 10)
            }
            ForEach(ReminderGroup.allCases) { group in
                let items = reminders.state.items.filter { $0.group(at: reminders.state.now, zone: reminders.state.zone) == group }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: NoteContentStyle.rowSpacing) {
                        Text(group.title).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(group == .overdue ? Ink.warning : Ink.secondary)
                            .accessibilityAddTraits(.isHeader).padding(.top, 2).padding(.bottom, 3)
                        ForEach(items) { item in ReminderTaskRow(item: item, reminders: reminders) }
                    }
                }
            }
            Text(reminders.state.locallySaved ? "Saved to Reminders on this Mac. Apple handles iCloud sync." : "Edit tasks and schedules in Apple Reminders.")
                .font(.system(size: 10)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showingConnection) {
            if let connection = reminders.state.connection {
                RemindersConnectionSheet(reminders: reminders, noteID: connection.noteID, noteTitle: "this note")
            }
        }
    }
}

struct ReminderTaskRow: View {
    let item: ReminderSnapshot
    @ObservedObject var reminders: RemindersStore
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var notesExpanded = false
    private var busy: Bool { reminders.state.completing.contains(item.id) }
    private var error: RemindersFailure? { reminders.state.completionErrors[item.id] }
    private var dueText: String? {
        guard let due = item.dueDate(in: reminders.state.zone) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = item.occurrence.due?.timeZone ?? reminders.state.zone
        formatter.dateStyle = .medium
        formatter.timeStyle = item.dateOnly ? .none : .short
        return formatter.string(from: due)
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TaskCheck(label: item.displayTitle, completionHelp: "Complete in Apple Reminders") { reminders.complete(item) }
                .disabled(busy || !reminders.state.writable)
                .opacity(busy || !reminders.state.writable ? 0.45 : 1)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle).font(.system(size: NoteContentStyle.fontSize(glass: appearance.effectiveGlass)))
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if dueText != nil || item.recurring {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let dueText { Text(dueText).fixedSize(horizontal: false, vertical: true) }
                        if item.recurring { Image(systemName: "repeat").accessibilityLabel("Recurring reminder").help("Recurring reminder") }
                    }.font(.system(size: 10)).foregroundStyle(item.group(at: reminders.state.now, zone: reminders.state.zone) == .overdue ? Ink.warning : Ink.secondary)
                }
                if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { notesExpanded.toggle() } label: {
                        Label(notesExpanded ? "Hide notes" : "Show notes", systemImage: notesExpanded ? "chevron.down" : "chevron.right")
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Ink.secondary)
                        .accessibilityLabel("\(notesExpanded ? "Hide" : "Show") notes for \(item.displayTitle)")
                    if notesExpanded { Text(item.notes).font(.system(size: 12)).foregroundStyle(Ink.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                if busy { Text("Saving…").font(.system(size: 10)).foregroundStyle(Ink.secondary) }
                if let error {
                    Text(error.localizedDescription).font(.system(size: 11)).foregroundStyle(Ink.warning).fixedSize(horizontal: false, vertical: true)
                    if error == .staleOccurrence || error == .missingReminder {
                        Button("Refresh") { reminders.refresh() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    } else {
                        Button("Retry") { reminders.complete(item) }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).disabled(busy || !reminders.state.writable)
                    }
                }
            }.padding(.bottom, 5)
        }.foregroundStyle(Ink.text).accessibilityElement(children: .contain)
            .accessibilityIdentifier("ReminderRow-\(item.id)")
    }
}

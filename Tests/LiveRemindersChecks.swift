// Separate, explicitly launched test app. Never compiled into Paperpin or its DMG.
import AppKit
import EventKit

// All mutable EventKit state is confined to queue.
private final class TestDatabase: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.paperpin.live-reminders-tests")
    private lazy var store = EKEventStore()
    private var calendar: EKCalendar?
    private let name = "Paperpin TEMPORARY sync test \(UUID().uuidString.prefix(8))"
    func perform<T>(_ work: @escaping (EKEventStore, EKCalendar?) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work(self.store, self.calendar)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func setup() async throws -> (String, [ReminderSnapshot]) {
        try await perform { store, _ in
            guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })?.source else {
                throw NSError(domain: "PaperpinTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No writable Reminders account"])
            }
            let calendar = EKCalendar(for: .reminder, eventStore: store)
            calendar.title = self.name; calendar.source = source
            try store.saveCalendar(calendar, commit: true)
            self.calendar = calendar
            var snapshots: [ReminderSnapshot] = []
            for (title, frequency) in [("TEMP one-time", Optional<EKRecurrenceFrequency>.none), ("TEMP weekly", .weekly), ("TEMP monthly", .monthly)] {
                let item = EKReminder(eventStore: store)
                item.calendar = calendar; item.title = title; item.notes = "Synthetic test notes — preserve these."
                let due = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                item.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                item.startDateComponents = item.dueDateComponents
                if let frequency { item.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)) }
                try store.save(item, commit: true)
                snapshots.append(EventKitRemindersClient.snapshot(item))
            }
            return (calendar.calendarIdentifier, snapshots)
        }
    }
    func edit(_ id: String, restore: Bool = false) async throws {
        try await perform { store, calendar in
            guard let item = store.calendarItem(withIdentifier: id) as? EKReminder,
                  item.calendar.calendarIdentifier == calendar?.calendarIdentifier else { throw RemindersFailure.missingReminder }
            item.reset(); _ = item.refresh()
            if restore { item.isCompleted = false }
            else { item.notes = "Externally edited synthetic notes" }
            try store.save(item, commit: true)
        }
    }
    func remove(_ id: String) async throws {
        try await perform { store, calendar in
            guard let item = store.calendarItem(withIdentifier: id) as? EKReminder,
                  item.calendar.calendarIdentifier == calendar?.calendarIdentifier else { throw RemindersFailure.missingReminder }
            try store.remove(item, commit: true)
        }
    }
    func completed(_ id: String) async throws -> (Bool, String) {
        try await perform { store, calendar in
            guard let item = store.calendarItem(withIdentifier: id) as? EKReminder,
                  item.calendar.calendarIdentifier == calendar?.calendarIdentifier else { throw RemindersFailure.missingReminder }
            item.reset(); _ = item.refresh()
            return (item.isCompleted, item.notes ?? "")
        }
    }
    func cleanup() async throws {
        try await perform { store, calendar in
            guard let calendar, calendar.title == self.name else { return }
            try store.removeCalendar(calendar, commit: true)
            self.calendar = nil
        }
    }
}

@main
private final class LiveRemindersChecks: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    static func main() {
        let delegate = LiveRemindersChecks()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Paperpin Reminders Check"
        let text = NSTextField(wrappingLabelWithString: "Allow Reminders access to validate a temporary test list.\n\nYour Main Work tasks will not be changed. The temporary list is removed after the checks.")
        text.frame = NSRect(x: 24, y: 20, width: 402, height: 110)
        window.contentView?.addSubview(text); window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in await run() }
    }
    @MainActor
    private func run() async {
        let client = EventKitRemindersClient()
        let db = TestDatabase()
        var failures = 0
        func check(_ ok: Bool, _ message: String) {
            print("\(ok ? "PASS" : "FAIL") \(message)"); fflush(stdout)
            if !ok { failures += 1 }
        }
        func pending(_ list: String) async throws -> [ReminderSnapshot] {
            try await withCheckedThrowingContinuation { continuation in
                client.fetch(listID: list) { continuation.resume(with: $0.mapError { $0 as Error }) }
            }
        }
        func complete(_ item: ReminderSnapshot) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.complete(item) { continuation.resume(with: $0.mapError { $0 as Error }) }
            }
        }
        let authorization = await withCheckedContinuation { continuation in client.requestAccess { continuation.resume(returning: $0) } }
        guard authorization == .allowed else { print("UNAVAILABLE Reminders permission was not granted"); fflush(stdout); NSApp.terminate(nil); return }
        do {
            let (list, originals) = try await db.setup()
            check(try await pending(list).count == 3, "real EventKit loads only the three temporary test reminders")
            let once = originals[0]
            try await db.edit(once.id)
            try await complete(once)
            let saved = try await db.completed(once.id)
            check(saved.0 && saved.1 == "Externally edited synthetic notes", "one-time completion preserves a concurrent notes edit")
            check(try await pending(list).count == 2, "completed one-time reminder is hidden")
            try await db.edit(once.id, restore: true)
            check(try await pending(list).contains(where: { $0.id == once.id }), "external restoration returns the one-time reminder")
            try await db.remove(once.id)
            check(!(try await pending(list).contains(where: { $0.id == once.id })), "external deletion removes the test reminder")
            for original in originals.dropFirst() {
                try await complete(original)
                var successor: ReminderSnapshot?
                // Bounded wait is a test assertion for Apple's asynchronous recurrence propagation,
                // not part of production sync (which uses EventKit notifications).
                for _ in 0..<20 {
                    successor = try await pending(list).first { $0.title == original.title && $0.recurring }
                    if let successor, successor.dueDate()! > original.dueDate()! { break }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                check(successor != nil && successor!.dueDate()! > original.dueDate()!, "\(original.title) advances to its future occurrence through Apple")
                check(successor?.occurrence.recurrence == original.occurrence.recurrence && successor?.notes == original.notes,
                      "\(original.title) preserves recurrence rules and notes")
                do { try await complete(original); check(false, "stale \(original.title) completion rejected") }
                catch { check(true, "stale \(original.title) completion rejected") }
            }
            try await db.cleanup()
            print("PASS removed the temporary test list without touching Main Work")
        } catch {
            check(false, "live test error: \(error.localizedDescription)")
            do { try await db.cleanup(); print("PASS temporary test list cleaned up after failure") }
            catch { print("FAIL remove the Paperpin TEMPORARY sync test list manually: \(error.localizedDescription)") }
        }
        print("FINISHED \(failures) live Reminders failures"); fflush(stdout)
        NSApp.terminate(nil)
    }
}

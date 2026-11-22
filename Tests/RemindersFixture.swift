import Foundation

/// No EventKit access in automated previews. Controlled callbacks exercise races deterministically.
final class FixtureRemindersClient: RemindersClient {
    var onChange: (() -> Void)?
    var auth: RemindersAuthorization = .allowed
    var permissionResult: RemindersAuthorization = .allowed
    var availableLists = [ReminderList(id: "fixture-main", title: "Main Work", account: "Preview Account", sourceID: "preview", writable: true)]
    var items: [ReminderSnapshot] = []
    var listFailure: RemindersFailure?
    var fetchFailure: RemindersFailure?
    var completeFailure: RemindersFailure?
    var holdFetch = false
    var holdCompletion = false
    var fetchReplies: [(Result<[ReminderSnapshot], RemindersFailure>) -> Void] = []
    var completionReplies: [(Result<Void, RemindersFailure>) -> Void] = []
    var requests = 0
    var fetches = 0
    var completions = 0
    var cancellations = 0
    func authorization(_ completion: @escaping (RemindersAuthorization) -> Void) { completion(auth) }
    func requestAccess(_ completion: @escaping (RemindersAuthorization) -> Void) {
        requests += 1; auth = permissionResult; completion(auth)
    }
    func lists(_ completion: @escaping (Result<[ReminderList], RemindersFailure>) -> Void) {
        if let listFailure { completion(.failure(listFailure)) } else { completion(.success(availableLists)) }
    }
    func fetch(listID: String, completion: @escaping (Result<[ReminderSnapshot], RemindersFailure>) -> Void) {
        fetches += 1
        if holdFetch { fetchReplies.append(completion) }
        else if let fetchFailure { completion(.failure(fetchFailure)) }
        else { completion(.success(items.filter { $0.listID == listID })) }
    }
    func complete(_ reminder: ReminderSnapshot, completion: @escaping (Result<Void, RemindersFailure>) -> Void) {
        completions += 1
        if holdCompletion { completionReplies.append(completion) }
        else if let completeFailure { completion(.failure(completeFailure)) }
        else { items.removeAll { $0.id == reminder.id }; completion(.success(())) }
    }
    func cancelFetches() { cancellations += 1 } // Deliberately allow late replies to test store generation guards.

    static func reminder(_ id: String, title: String? = nil, due: DateComponents? = nil,
                         recurring: Bool = false, notes: String = "", list: String = "fixture-main", created: Date? = nil) -> ReminderSnapshot {
        ReminderSnapshot(id: id, listID: list, title: title ?? id, notes: notes,
                         occurrence: ReminderOccurrence(due: due, start: nil, recurrence: recurring ? "weekly" : "", created: created))
    }
    func loadSample() {
        let calendar = Calendar.current
        func due(_ days: Int, hour: Int? = nil) -> DateComponents {
            var result = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: days, to: Date())!)
            result.hour = hour
            result.minute = hour == nil ? nil : 30
            return result
        }
        items = [
            Self.reminder("sample-overdue", title: "Send the project update", due: due(-2, hour: 10), notes: "Include the latest sketches and next steps."),
            Self.reminder("sample-overdue-recurring", title: "Weekly team check-in", due: due(-1, hour: 15), recurring: true),
            Self.reminder("sample-upcoming", title: "Review launch checklist", due: due(2), notes: "Confirm the handover with the team."),
            Self.reminder("sample-undated", title: "Explore ideas for the studio", notes: "Natural light\nA quiet reading corner\nPlants by the window"),
            Self.reminder("sample-recurring", title: "Monthly workspace review", due: due(9, hour: 11), recurring: true)
        ]
    }
}

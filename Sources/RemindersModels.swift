import Foundation

enum RemindersAuthorization: Equatable { case notDetermined, allowed, denied, restricted }

struct ReminderList: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
    let sourceID: String
    let writable: Bool
}

struct RemindersConnection: Codable, Equatable {
    let noteID: UUID
    let listID: String
    var listTitle: String
    var account: String
}

/// These values identify the occurrence the user actually saw, not just its series.
/// Title/notes/lastModified are intentionally excluded: a completion must preserve external edits.
struct ReminderOccurrence: Equatable {
    var due: DateComponents?
    var start: DateComponents?
    var recurrence: String
    var created: Date?
}

struct ReminderSnapshot: Identifiable, Equatable {
    let id: String
    let listID: String
    let title: String
    let notes: String
    let occurrence: ReminderOccurrence
    var recurring: Bool { !occurrence.recurrence.isEmpty }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled reminder" : title }
    var dateOnly: Bool { occurrence.due?.hour == nil }

    func dueDate(in zone: TimeZone = .current) -> Date? {
        guard var components = occurrence.due else { return nil }
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? zone
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)
    }

    /// All-day items become overdue at the *following* local midnight, including DST changes.
    func overdueBoundary(in zone: TimeZone = .current) -> Date? {
        guard let due = dueDate(in: zone) else { return nil }
        guard dateOnly else { return due }
        var calendar = occurrence.due?.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = occurrence.due?.timeZone ?? zone
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due))
    }

    func group(at now: Date, zone: TimeZone = .current) -> ReminderGroup {
        if let boundary = overdueBoundary(in: zone), now >= boundary { return .overdue }
        if recurring { return .recurring }
        return dueDate(in: zone) == nil ? .undated : .upcoming
    }
}

enum ReminderGroup: Int, CaseIterable, Identifiable {
    case overdue, upcoming, undated, recurring
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .upcoming: return "Upcoming"
        case .undated: return "Undated"
        case .recurring: return "Recurring"
        }
    }
}

enum ReminderOrdering {
    static func sorted(_ items: [ReminderSnapshot], now: Date, zone: TimeZone = .current) -> [ReminderSnapshot] {
        items.sorted { a, b in
            let ag = a.group(at: now, zone: zone), bg = b.group(at: now, zone: zone)
            if ag != bg { return ag.rawValue < bg.rawValue }
            let ad = a.dueDate(in: zone) ?? .distantFuture, bd = b.dueDate(in: zone) ?? .distantFuture
            if ad != bd { return ad < bd }
            let ac = a.occurrence.created ?? .distantFuture, bc = b.occurrence.created ?? .distantFuture
            if ac != bc { return ac < bc }
            let titleOrder = a.displayTitle.compare(b.displayTitle, options: [.caseInsensitive, .literal])
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return a.id < b.id
        }
    }
}

enum ReminderCompletionValidation {
    static func validate(clicked: ReminderSnapshot, current: ReminderSnapshot, completed: Bool, writable: Bool) throws {
        guard writable else { throw RemindersFailure.readOnly }
        guard !completed, clicked.id == current.id, clicked.listID == current.listID else { throw RemindersFailure.missingReminder }
        guard clicked.occurrence == current.occurrence else { throw RemindersFailure.staleOccurrence }
    }
}

enum RemindersFailure: Error, LocalizedError, Equatable {
    case denied, restricted, missingList, readOnly, staleOccurrence, missingReminder, fetch, save(String)
    var errorDescription: String? {
        switch self {
        case .denied: return "Reminders access is off. Allow Paperpin in System Settings → Privacy & Security → Reminders."
        case .restricted: return "Reminders access is restricted on this Mac."
        case .missingList: return "This list is no longer available. Choose a list to reconnect."
        case .readOnly: return "This list is read-only. Complete its reminders in Apple Reminders."
        case .staleOccurrence: return "This reminder changed. Refresh and review its current occurrence before completing it."
        case .missingReminder: return "This reminder is no longer pending. Refresh to update the list."
        case .fetch: return "Couldn’t load reminders. Your last loaded tasks are still shown. Try refreshing."
        case .save(let message): return "Couldn’t complete this reminder. \(message)"
        }
    }
}

protocol RemindersClient: AnyObject {
    var onChange: (() -> Void)? { get set }
    func authorization(_ completion: @escaping (RemindersAuthorization) -> Void)
    func requestAccess(_ completion: @escaping (RemindersAuthorization) -> Void)
    func lists(_ completion: @escaping (Result<[ReminderList], RemindersFailure>) -> Void)
    func fetch(listID: String, completion: @escaping (Result<[ReminderSnapshot], RemindersFailure>) -> Void)
    func complete(_ reminder: ReminderSnapshot, completion: @escaping (Result<Void, RemindersFailure>) -> Void)
    func cancelFetches()
}

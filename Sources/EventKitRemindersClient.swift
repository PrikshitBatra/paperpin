import EventKit

/// No EventKit objects escape this adapter. Every operation uses the same serial worker/store.
final class EventKitRemindersClient: RemindersClient {
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "local.paperpin.reminders", qos: .utility)
    private lazy var store = EKEventStore()
    private var requests: [UUID: Any] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: nil) { [weak self] _ in
            // The store's handler hops to the main thread and coalesces notification bursts.
            self?.onChange?()
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func status() -> RemindersAuthorization {
        let value = EKEventStore.authorizationStatus(for: .reminder)
        if value == .notDetermined { return .notDetermined }
        if value == .restricted { return .restricted }
        if #available(macOS 14, *), value == .fullAccess { return .allowed }
        if value.rawValue == 3 { return .allowed } // Legacy authorized, same raw value as fullAccess.
        return .denied
    }
    func authorization(_ completion: @escaping (RemindersAuthorization) -> Void) {
        queue.async { completion(self.status()) }
    }
    func requestAccess(_ completion: @escaping (RemindersAuthorization) -> Void) {
        queue.async {
            let reply: (Bool, Error?) -> Void = { _, _ in self.queue.async { completion(self.status()) } }
            if #available(macOS 14, *) { self.store.requestFullAccessToReminders(completion: reply) }
            else { self.store.requestAccess(to: .reminder, completion: reply) }
        }
    }
    private func checkAccess() throws {
        switch status() {
        case .allowed: return
        case .restricted: throw RemindersFailure.restricted
        default: throw RemindersFailure.denied
        }
    }
    private func list(_ id: String) throws -> EKCalendar {
        try checkAccess()
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) else {
            throw RemindersFailure.missingList
        }
        return calendar
    }
    func lists(_ completion: @escaping (Result<[ReminderList], RemindersFailure>) -> Void) {
        queue.async {
            do {
                try self.checkAccess()
                let values = self.store.calendars(for: .reminder).map {
                    ReminderList(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title,
                                 sourceID: $0.source.sourceIdentifier, writable: $0.allowsContentModifications)
                }.sorted { ($0.title, $0.account, $0.id) < ($1.title, $1.account, $1.id) }
                completion(.success(values))
            } catch { completion(.failure(error as? RemindersFailure ?? .fetch)) }
        }
    }
    func fetch(listID: String, completion: @escaping (Result<[ReminderSnapshot], RemindersFailure>) -> Void) {
        queue.async { [self] in
            do {
                let list = try self.list(listID)
                let predicate = self.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
                let requestID = UUID()
                let request = self.store.fetchReminders(matching: predicate) { [weak self] records in
                    guard let self else { return }
                    self.queue.async {
                        guard self.requests.removeValue(forKey: requestID) != nil else { return }
                        do {
                            try self.checkAccess()
                            guard let records else { completion(.failure(.fetch)); return }
                            completion(.success(records.filter { !$0.isCompleted && $0.calendar.calendarIdentifier == listID }.map(Self.snapshot)))
                        } catch { completion(.failure(error as? RemindersFailure ?? .fetch)) }
                    }
                }
                self.requests[requestID] = request
            } catch { completion(.failure(error as? RemindersFailure ?? .fetch)) }
        }
    }
    func cancelFetches() {
        queue.async {
            for request in self.requests.values { self.store.cancelFetchRequest(request) }
            self.requests.removeAll()
        }
    }
    func complete(_ reminder: ReminderSnapshot, completion: @escaping (Result<Void, RemindersFailure>) -> Void) {
        queue.async {
            do {
                let list = try self.list(reminder.listID)
                guard list.allowsContentModifications else { throw RemindersFailure.readOnly }
                guard let current = self.store.calendarItem(withIdentifier: reminder.id) as? EKReminder else {
                    throw RemindersFailure.missingReminder
                }
                current.reset()
                guard current.refresh() else { throw RemindersFailure.missingReminder }
                try ReminderCompletionValidation.validate(clicked: reminder, current: Self.snapshot(current),
                                                           completed: current.isCompleted, writable: list.allowsContentModifications)
                // Never replace a record from a snapshot: preserve all other current fields and let
                // EventKit advance recurrence. The same record must still represent the clicked occurrence.
                current.isCompleted = true
                do { try self.store.save(current, commit: true) }
                catch { current.rollback(); throw error }
                completion(.success(()))
            } catch { completion(.failure(error as? RemindersFailure ?? .save(error.localizedDescription))) }
        }
    }

    static func snapshot(_ item: EKReminder) -> ReminderSnapshot {
        func components(_ value: DateComponents?) -> DateComponents? {
            guard var value else { return nil }
            if value.timeZone == nil { value.timeZone = item.timeZone }
            return value
        }
        let recurrence = (item.recurrenceRules ?? []).map { rule -> String in
            let days = (rule.daysOfTheWeek ?? []).map { "\($0.dayOfTheWeek.rawValue):\($0.weekNumber)" }.joined(separator: ",")
            let numbers = [rule.daysOfTheMonth, rule.daysOfTheYear, rule.weeksOfTheYear, rule.monthsOfTheYear, rule.setPositions]
                .map { ($0 ?? []).map(\.stringValue).joined(separator: ",") }.joined(separator: ";")
            return "\(rule.frequency.rawValue)|\(rule.interval)|\(rule.firstDayOfTheWeek)|\(days)|\(numbers)|\(rule.recurrenceEnd?.endDate?.timeIntervalSinceReferenceDate.description ?? "")|\(rule.recurrenceEnd?.occurrenceCount ?? 0)"
        }.joined(separator: " / ")
        return ReminderSnapshot(id: item.calendarItemIdentifier, listID: item.calendar.calendarIdentifier,
                                title: item.title ?? "", notes: item.notes ?? "",
                                occurrence: ReminderOccurrence(due: components(item.dueDateComponents),
                                    start: components(item.startDateComponents), recurrence: recurrence, created: item.creationDate))
    }
}

import AppKit
import Combine

struct RemindersState: Equatable {
    var connection: RemindersConnection?
    var authorization: RemindersAuthorization = .notDetermined
    var lists: [ReminderList] = []
    var items: [ReminderSnapshot] = []
    var refreshing = false
    var problem: RemindersFailure?
    var completing: Set<String> = []
    var completionErrors: [String: RemindersFailure] = [:]
    var now = Date()
    var zone = TimeZone.current
    var locallySaved = false
    var writable: Bool {
        guard authorization == .allowed, let connection,
              let list = lists.first(where: { $0.id == connection.listID }) else { return false }
        return list.writable && problem != .missingList
    }
}

/// Main-thread presentation model. In-memory snapshots are shared by every presentation;
/// only connection/tab preferences are persisted, never a second copy of Apple reminders.
final class RemindersStore: ObservableObject {
    @Published private(set) var state: RemindersState
    private let client: RemindersClient
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let timeZone: () -> TimeZone
    private let schedulesBoundaries: Bool
    private var generation = 0
    private var connectionGeneration = 0
    private var scheduledRefresh: DispatchWorkItem?
    private var dueTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var boardSubscription: AnyCancellable?
    private var requestingAccess = false
    private var activeCompletions: Set<UUID> = []
    private var finishHandlers: [() -> Void] = []
    private(set) var fetchCount = 0
    private(set) var preferenceWriteCount = 0
    var hasPendingCompletions: Bool { !activeCompletions.isEmpty }

    init(client: RemindersClient, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current },
         observeLifecycle: Bool = true) {
        self.client = client
        self.defaults = defaults
        self.clock = clock
        self.timeZone = timeZone
        schedulesBoundaries = observeLifecycle
        let connection = defaults.data(forKey: "RemindersConnection").flatMap { try? JSONDecoder().decode(RemindersConnection.self, from: $0) }
        state = RemindersState(connection: connection, now: clock(), zone: timeZone())
        client.onChange = { [weak self] in self?.onMain { $0.scheduleRefresh() } }
        if observeLifecycle {
            for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.recalculateDates()
                })
            }
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.recalculateDates()
                    self?.refresh()
                })
        }
    }
    deinit {
        scheduledRefresh?.cancel()
        dueTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }
    private func onMain(_ work: @escaping (RemindersStore) -> Void) {
        if Thread.isMainThread { work(self) }
        else { DispatchQueue.main.async { [weak self] in if let self { work(self) } } }
    }
    func start(board: BoardStore) {
        boardSubscription = board.$board.map { Set($0.notes.map(\.id)) }.removeDuplicates().sink { [weak self, weak board] ids in
            guard let self, board?.requiresFileRecovery == false, let id = self.state.connection?.noteID else { return }
            if !ids.contains(id) { self.disconnect() }
        }
        refresh()
    }
    func connected(to noteID: UUID) -> Bool { state.connection?.noteID == noteID }
    func matches(_ query: String, noteID: UUID) -> Bool {
        connected(to: noteID) && !query.isEmpty && state.items.contains {
            $0.title.localizedStandardContains(query) || $0.notes.localizedStandardContains(query)
        }
    }
    func selectedTab(noteID: UUID, presentation: String) -> String {
        defaults.string(forKey: "ReminderTab.\(presentation).\(noteID.uuidString)") ?? "tasks"
    }
    func setSelectedTab(_ value: String, noteID: UUID, presentation: String) {
        let key = "ReminderTab.\(presentation).\(noteID.uuidString)"
        if defaults.string(forKey: key) != value { defaults.set(value, forKey: key); preferenceWriteCount += 1 }
    }
    private func persistConnection() {
        let existing = defaults.data(forKey: "RemindersConnection").flatMap { try? JSONDecoder().decode(RemindersConnection.self, from: $0) }
        guard existing != state.connection else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let value = state.connection.flatMap { try? encoder.encode($0) }
        if defaults.data(forKey: "RemindersConnection") != value {
            defaults.set(value, forKey: "RemindersConnection")
            preferenceWriteCount += 1
        }
    }
    func connect(noteID: UUID, list: ReminderList) {
        guard state.authorization == .allowed, state.lists.contains(where: { $0.id == list.id }) else { return }
        invalidate()
        connectionGeneration += 1
        state.connection = RemindersConnection(noteID: noteID, listID: list.id, listTitle: list.title, account: list.account)
        state.items = []
        state.completing = []
        state.completionErrors = [:]
        state.locallySaved = false
        persistConnection()
        refresh()
    }
    func disconnect() {
        invalidate()
        connectionGeneration += 1
        state = RemindersState(authorization: state.authorization, now: clock(), zone: timeZone())
        persistConnection()
    }
    private func invalidate() {
        generation += 1
        scheduledRefresh?.cancel(); scheduledRefresh = nil
        dueTimer?.invalidate(); dueTimer = nil
        client.cancelFetches()
    }
    /// Called solely by the explicit Connect/Change List sheet. Ordinary refreshes never prompt.
    func prepareConnection() { refresh(allowPermissionRequest: true) }
    func refresh() { refresh(allowPermissionRequest: false) }
    private func refresh(allowPermissionRequest: Bool) {
        guard !requestingAccess, state.connection != nil || allowPermissionRequest else { return }
        invalidate()
        let token = generation
        state.refreshing = true
        client.authorization { [weak self] auth in
            self?.onMain { owner in
                guard owner.generation == token else { return }
                if auth == .notDetermined && allowPermissionRequest {
                    owner.requestingAccess = true
                    owner.client.requestAccess { [weak owner] result in
                        owner?.onMain { current in
                            current.requestingAccess = false
                            guard current.generation == token else { return }
                            current.acceptAuthorization(result, token: token)
                        }
                    }
                } else { owner.acceptAuthorization(auth, token: token) }
            }
        }
    }
    private func acceptAuthorization(_ auth: RemindersAuthorization, token: Int) {
        state.authorization = auth
        guard auth == .allowed else {
            state.items = []
            state.lists = []
            state.completionErrors = [:]
            state.problem = auth == .restricted ? .restricted : .denied
            state.refreshing = false
            return
        }
        client.lists { [weak self] result in
            self?.onMain { owner in
                guard owner.generation == token else { return }
                switch result {
                case .failure(let error): owner.handleFailure(error)
                case .success(let lists):
                    owner.state.lists = lists
                    owner.state.problem = nil
                    guard var connection = owner.state.connection else { owner.state.refreshing = false; return }
                    guard let selected = lists.first(where: { $0.id == connection.listID }) else {
                        owner.state.items = []
                        owner.handleFailure(.missingList)
                        return
                    }
                    connection.listTitle = selected.title
                    connection.account = selected.account
                    owner.state.connection = connection
                    owner.persistConnection()
                    owner.fetchCount += 1
                    owner.client.fetch(listID: selected.id) { [weak owner] response in
                        owner?.onMain { current in
                            guard current.generation == token else { return }
                            switch response {
                            case .failure(let error): current.handleFailure(error)
                            case .success(let values):
                                current.state.refreshing = false
                                current.state.problem = selected.writable ? nil : .readOnly
                                // Defend against an adapter accidentally returning another list or duplicate IDs.
                                var seen: Set<String> = []
                                current.state.items = values.filter { $0.listID == selected.id && seen.insert($0.id).inserted }
                                current.state.completionErrors = current.state.completionErrors.filter { id, _ in seen.contains(id) }
                                current.recalculateDates()
                            }
                        }
                    }
                }
            }
        }
    }
    private func handleFailure(_ error: RemindersFailure) {
        state.refreshing = false
        state.problem = error
        if error == .denied || error == .restricted {
            state.authorization = error == .denied ? .denied : .restricted
            state.items = []; state.lists = []; state.completionErrors = [:]
        }
        if error == .missingList { state.items = [] }
        recalculateDates()
    }
    private func scheduleRefresh() {
        guard state.connection != nil, !requestingAccess else { return }
        scheduledRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        scheduledRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func recalculateDates() {
        state.now = clock()
        state.zone = timeZone()
        state.items = ReminderOrdering.sorted(state.items, now: state.now, zone: state.zone)
        dueTimer?.invalidate(); dueTimer = nil
        guard schedulesBoundaries,
              let next = state.items.compactMap({ $0.overdueBoundary(in: state.zone) }).filter({ $0 > state.now }).min() else { return }
        // One scheduled boundary, never an idle polling timer or network refresh.
        let timer = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in self?.recalculateDates() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        dueTimer = timer
    }
    func complete(_ reminder: ReminderSnapshot) {
        guard state.writable, state.connection?.listID == reminder.listID,
              state.items.contains(reminder), !state.completing.contains(reminder.id) else { return }
        state.completing.insert(reminder.id)
        state.completionErrors[reminder.id] = nil
        let connectionToken = connectionGeneration
        let operation = UUID()
        activeCompletions.insert(operation)
        client.complete(reminder) { [weak self] result in
            self?.onMain { owner in
                owner.activeCompletions.remove(operation)
                if owner.connectionGeneration == connectionToken {
                    owner.state.completing.remove(reminder.id)
                    switch result {
                    case .success:
                        // Only remove the clicked occurrence if a notification already fetched its successor.
                        owner.state.items.removeAll { $0.id == reminder.id && $0.occurrence == reminder.occurrence }
                        owner.state.locallySaved = true
                        owner.refresh()
                    case .failure(let error):
                        owner.state.completionErrors[reminder.id] = error
                        if error == .denied || error == .restricted { owner.handleFailure(error) }
                    }
                }
                if owner.activeCompletions.isEmpty {
                    let callbacks = owner.finishHandlers; owner.finishHandlers = []
                    callbacks.forEach { $0() }
                }
            }
        }
    }
    func afterCompletions(_ completion: @escaping () -> Void) {
        if activeCompletions.isEmpty { completion() } else { finishHandlers.append(completion) }
    }
}

/// Unconnected desktop editors do not subscribe to reminder item changes.
final class ReminderHostObservation: ObservableObject {
    @Published private(set) var connected: Bool
    private var subscription: AnyCancellable?
    init(store: RemindersStore, noteID: UUID) {
        connected = store.connected(to: noteID)
        subscription = store.$state.map { $0.connection?.noteID == noteID }.removeDuplicates()
            .sink { [weak self] in self?.connected = $0 }
    }
}

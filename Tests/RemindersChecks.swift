import Foundation
import Combine

@main
enum RemindersChecks {
    static func main() throws {
        var checks = 0
        func check(_ ok: @autoclosure () -> Bool, _ name: String) {
            guard ok() else { fatalError(name) }
            checks += 1; print("PASS \(name)")
        }
        let utc = TimeZone(secondsFromGMT: 0)!
        let india = TimeZone(identifier: "Asia/Kolkata")!
        func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
        func due(_ day: Int, hour: Int? = nil, zone: TimeZone? = nil) -> DateComponents {
            DateComponents(timeZone: zone, year: 2026, month: 11, day: day, hour: hour)
        }
        let now = date("2026-11-23T12:00:00Z")
        let make = FixtureRemindersClient.reminder
        let values = [
            make("recurring-undated", nil, nil, true, "", "fixture-main", nil),
            make("upcoming", nil, due(24), false, "", "fixture-main", nil),
            make("undated", nil, nil, false, "", "fixture-main", nil),
            make("overdue", nil, due(21, hour: 10), false, "", "fixture-main", nil),
            make("recurring-dated", nil, due(24), true, "", "fixture-main", nil),
            make("overdue-recurring", nil, due(20), true, "", "fixture-main", nil)
        ]
        check(ReminderOrdering.sorted(values, now: now, zone: utc).map(\.id) ==
              ["overdue-recurring", "overdue", "upcoming", "undated", "recurring-dated", "recurring-undated"],
              "overdue recurring first; upcoming, undated, then remaining recurring")
        let allDay = FixtureRemindersClient.reminder("all-day", due: due(23))
        check(allDay.group(at: date("2026-11-23T23:59:59Z"), zone: utc) == .upcoming, "date-only item remains upcoming through its entire due day")
        check(allDay.group(at: date("2026-11-24T00:00:00Z"), zone: utc) == .overdue, "date-only item becomes overdue at next midnight")
        check(allDay.group(at: date("2026-11-23T19:00:00Z"), zone: india) == .overdue, "floating due day follows local time zone")
        let explicit = FixtureRemindersClient.reminder("explicit", due: due(23, zone: india))
        check(explicit.overdueBoundary(in: utc) == date("2026-11-23T18:30:00Z"), "explicit time zone takes priority over system time zone")
        let dst = FixtureRemindersClient.reminder("dst", due: DateComponents(timeZone: TimeZone(identifier: "America/New_York"), year: 2026, month: 3, day: 8))
        check(dst.overdueBoundary(in: utc)!.timeIntervalSince(dst.dueDate(in: utc)!) == 23 * 3600, "all-day boundary respects the spring DST transition")
        let timed = FixtureRemindersClient.reminder("timed", due: due(23, hour: 12))
        check(timed.group(at: now, zone: utc) == .overdue, "timed item crosses at its exact due time")
        let older = date("2026-01-01T00:00:00Z"), newer = older.addingTimeInterval(1)
        let ties = [FixtureRemindersClient.reminder("z", title: "Beta", created: older),
                    FixtureRemindersClient.reminder("a", title: "Alpha", created: newer),
                    FixtureRemindersClient.reminder("b", title: "Alpha", created: older),
                    FixtureRemindersClient.reminder("a-old", title: "Alpha", created: older)]
        check(ReminderOrdering.sorted(ties.reversed(), now: now).map(\.id) == ["a-old", "b", "z", "a"], "equal-date ties use creation, title, then identifier")

        func rejected(_ clicked: ReminderSnapshot, _ current: ReminderSnapshot, completed: Bool = false,
                      writable: Bool = true) -> RemindersFailure? {
            do {
                try ReminderCompletionValidation.validate(clicked: clicked, current: current, completed: completed, writable: writable)
                return nil
            } catch { return error as? RemindersFailure }
        }
        let recurring = FixtureRemindersClient.reminder("series", due: due(23), recurring: true)
        let successor = FixtureRemindersClient.reminder("series", due: due(30), recurring: true)
        check(rejected(recurring, successor) == .staleOccurrence, "stale recurring row cannot complete its next occurrence")
        let edited = FixtureRemindersClient.reminder("series", title: "Externally edited title", due: due(23), recurring: true, notes: "New notes")
        check(rejected(recurring, edited) == nil, "external title and note edits do not require overwriting those fields")
        check(rejected(recurring, recurring, completed: true) == .missingReminder, "already completed occurrence is rejected")
        let moved = FixtureRemindersClient.reminder("series", due: due(23), recurring: true, list: "another-list")
        check(rejected(recurring, moved) == .missingReminder, "reminder moved to another list is rejected")
        check(rejected(recurring, recurring, writable: false) == .readOnly, "completion rechecks list write access")

        let suite = "local.paperpin.reminders-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FixtureRemindersClient()
        var currentTime = now
        var currentZone = utc
        let store = RemindersStore(client: client, defaults: defaults, clock: { currentTime }, timeZone: { currentZone }, observeLifecycle: false)
        let noteID = UUID()
        store.refresh()
        check(client.requests == 0 && client.fetches == 0, "unconnected launch does not ask for access or fetch reminders")
        client.auth = .notDetermined
        store.prepareConnection()
        check(client.requests == 1 && store.state.authorization == .allowed, "explicit connection alone requests permission")
        client.items = values
        store.connect(noteID: noteID, list: client.availableLists[0])
        check(store.state.items.count == values.count && store.connected(to: noteID), "connection shares one selected-list snapshot")
        check(defaults.data(forKey: "RemindersConnection") != nil, "connection identifiers persist outside board content")
        store.setSelectedTab("reminders", noteID: noteID, presentation: "board")
        check(store.selectedTab(noteID: noteID, presentation: "desktop") == "tasks", "board and desktop remember separate tab choices")
        check(store.selectedTab(noteID: noteID, presentation: "board") == "reminders", "selected tab survives view recreation")
        let savedCount = store.preferenceWriteCount
        store.refresh(); store.refresh()
        check(store.preferenceWriteCount == savedCount, "unchanged refreshes do not rewrite connection preferences")
        client.availableLists[0] = ReminderList(id: "fixture-main", title: "Renamed Work", account: "Preview Account", sourceID: "preview", writable: true)
        store.refresh()
        check(store.state.connection?.listTitle == "Renamed Work" && store.state.items.count == values.count, "renamed list remains connected by its identifier")
        client.availableLists = [ReminderList(id: "replacement", title: "Renamed Work", account: "Preview Account", sourceID: "preview", writable: true)]
        store.refresh()
        check(store.state.problem == .missingList && store.state.items.isEmpty && store.state.connection?.listID == "fixture-main", "same-name replacement requires explicit reselection")
        client.availableLists = [ReminderList(id: "fixture-main", title: "Main Work", account: "Preview Account", sourceID: "preview", writable: false)]
        store.refresh()
        let beforeReadOnly = client.completions
        store.complete(store.state.items[0])
        check(!store.state.writable && store.state.problem == .readOnly && client.completions == beforeReadOnly, "read-only list remains visible and cannot be completed")
        client.availableLists[0] = ReminderList(id: "fixture-main", title: "Main Work", account: "Preview Account", sourceID: "preview", writable: true)
        store.refresh()
        client.fetchFailure = .fetch
        store.refresh()
        check(store.state.problem == .fetch && store.state.items.count == values.count, "fetch failure retains previous snapshot and is distinct from empty")
        client.fetchFailure = nil
        client.auth = .denied
        store.refresh()
        check(store.state.items.isEmpty && store.state.lists.isEmpty && store.state.problem == .denied, "revoked access clears displayed reminder data")
        check(client.requests == 1, "refresh never prompts again after denial")
        client.auth = .allowed
        store.refresh()
        check(store.state.items.count == values.count && store.state.problem == nil, "restored permission reloads the existing connection")
        client.holdFetch = true
        store.refresh()
        let oldReply = client.fetchReplies.removeFirst()
        store.disconnect()
        oldReply(.success(values))
        check(store.state.connection == nil && store.state.items.isEmpty, "late fetch cannot repopulate a disconnected connection")
        store.prepareConnection()
        client.holdFetch = false
        store.connect(noteID: noteID, list: client.availableLists[0])
        client.holdFetch = true
        store.refresh()
        let oldListReply = client.fetchReplies.removeFirst()
        let secondList = ReminderList(id: "second-list", title: "Second", account: "Preview", sourceID: "preview", writable: true)
        client.availableLists.append(secondList)
        store.prepareConnection()
        _ = client.fetchReplies.removeFirst()
        store.connect(noteID: noteID, list: secondList)
        let newListReply = client.fetchReplies.removeFirst()
        let secondItem = FixtureRemindersClient.reminder("second-item", list: "second-list")
        newListReply(.success([secondItem]))
        oldListReply(.success(values))
        check(store.state.connection?.listID == "second-list" && store.state.items == [secondItem], "old-list reply cannot replace the newly selected list")
        client.holdFetch = false
        store.connect(noteID: noteID, list: client.availableLists[0])
        client.holdFetch = true
        store.refresh()
        let olderReply = client.fetchReplies.removeFirst()
        store.refresh()
        let latestReply = client.fetchReplies.removeFirst()
        latestReply(.success([allDay]))
        olderReply(.success(values))
        check(store.state.items == [allDay], "out-of-order fetches cannot overwrite the latest snapshot")
        client.holdFetch = false
        client.items = [allDay]
        client.holdCompletion = true
        var boardSnapshots: [RemindersState] = [], desktopSnapshots: [RemindersState] = []
        let boardObservation = store.$state.sink { boardSnapshots.append($0) }
        let desktopObservation = store.$state.sink { desktopSnapshots.append($0) }
        store.complete(allDay); store.complete(allDay)
        check(client.completions == 1 && store.state.completing.contains(allDay.id), "duplicate clicks produce one save and disable the shared checkbox")
        check(boardSnapshots.last?.completing == desktopSnapshots.last?.completing, "board and desktop observe the same pending completion")
        var drained = false
        store.afterCompletions { drained = true }
        check(!drained, "orderly termination waits for completion writes")
        client.completionReplies.removeFirst()(.failure(.save("Temporary test failure")))
        check(drained && store.state.items.contains(allDay) && store.state.completionErrors[allDay.id] != nil, "failed save remains visible, supports retry, and drains lifecycle waiters")
        client.holdCompletion = true
        store.complete(allDay)
        client.availableLists[0] = ReminderList(id: "fixture-main", title: "Renamed during save", account: "Preview", sourceID: "preview", writable: true)
        store.refresh()
        client.completionReplies.removeFirst()(.failure(.save("Rename test failure")))
        check(!store.state.completing.contains(allDay.id) && store.state.completionErrors[allDay.id] != nil,
              "list rename during completion still resolves the shared saving state")
        client.holdCompletion = false
        store.complete(allDay)
        check(store.state.items.isEmpty && store.state.locallySaved && client.completions == 3, "successful retry removes reminder after local save")
        check(boardSnapshots.last?.items == desktopSnapshots.last?.items, "successful completion updates every observer")
        withExtendedLifetime([boardObservation, desktopObservation]) {}
        client.items = [timed]
        store.refresh()
        currentTime = now.addingTimeInterval(-1)
        store.recalculateDates()
        check(store.state.items[0].group(at: store.state.now, zone: store.state.zone) == .upcoming, "ordering recalculates before the due boundary")
        currentTime = now
        let fetchesBeforeBoundary = client.fetches
        store.recalculateDates()
        check(store.state.items[0].group(at: store.state.now, zone: store.state.zone) == .overdue && client.fetches == fetchesBeforeBoundary, "due-boundary reorder needs no database fetch")
        client.items = [allDay]
        currentTime = date("2026-11-23T19:00:00Z")
        store.refresh(); currentZone = india; store.recalculateDates()
        check(store.state.items[0].group(at: store.state.now, zone: store.state.zone) == .overdue, "system time-zone change recalculates floating due dates")
        client.items = [FixtureRemindersClient.reminder("search", title: "Planning", notes: "Unique sketch detail")]
        store.refresh()
        check(store.matches("sketch", noteID: noteID) && !store.matches("sketch", noteID: UUID()), "reminder notes participate only in their host note's search")
        let beforeBurst = client.fetches
        for _ in 0..<20 { client.onChange?() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        check(client.fetches == beforeBurst + 1, "notification bursts coalesce to one database fetch")
        let settledFetches = client.fetches, settledWrites = store.preferenceWriteCount
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        check(client.fetches == settledFetches && store.preferenceWriteCount == settledWrites, "settled connection performs no recurring fetches or preference writes")
        let relaunched = RemindersStore(client: client, defaults: defaults, observeLifecycle: false)
        relaunched.refresh()
        check(relaunched.state.connection?.noteID == noteID && relaunched.state.items.count == 1, "relaunch restores connection by identifiers and reloads local database")
        client.items = []
        store.refresh()
        check(store.state.items.isEmpty, "external deletion removes a reminder")
        client.items = [allDay]
        store.refresh()
        check(store.state.items == [allDay], "external restoration reappears without a local archive entry")
        client.holdFetch = true
        store.refresh()
        let deniedLateReply = client.fetchReplies.removeFirst()
        client.auth = .denied
        store.refresh()
        deniedLateReply(.success(values))
        check(store.state.items.isEmpty && store.state.authorization == .denied, "late authorized fetch cannot reveal data after permission revocation")
        client.holdFetch = false; client.auth = .allowed
        store.refresh()
        store.disconnect()
        check(client.items.count == 1, "disconnect never deletes or completes Apple reminders")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let boardStore = BoardStore(file: temp.appendingPathComponent("Board.json"))
        let host = boardStore.board.notes[0].id
        store.prepareConnection()
        store.connect(noteID: host, list: client.availableLists[0])
        store.start(board: boardStore)
        boardStore.deleteNote(host)
        check(store.state.connection == nil && client.items.count == 1, "deleting the host note disconnects without touching Apple reminders")

        print("FINISHED \(checks) Reminders checks")
    }
}

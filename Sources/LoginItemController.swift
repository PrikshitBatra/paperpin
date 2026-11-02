import AppKit
import Combine
import ServiceManagement

protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

final class LoginItemController: ObservableObject {
    static let shared = LoginItemController()
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?
    private let service: LoginItemServicing
    private let allowsChanges: Bool
    private var activationObserver: NSObjectProtocol?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }
    var message: String? {
        if let lastError { return lastError }
        switch status {
        case .enabled, .notRegistered: return nil
        case .requiresApproval: return "Launch at login needs approval in System Settings."
        case .notFound: return "Launch at login is unavailable. Open the installed copy of Paperpin and retry."
        @unknown default: return "Unable to determine launch at login status."
        }
    }

    init(service: LoginItemServicing = SMAppService.mainApp,
         allowsChanges: Bool? = nil, observeActivation: Bool = true) {
        self.service = service
        self.status = service.status
        #if PAPERPIN_QA
        self.allowsChanges = allowsChanges ?? false
        #else
        self.allowsChanges = allowsChanges ?? true
        #endif
        if observeActivation {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
    }

    func refresh() {
        let current = service.status
        if status != current {
            status = current
            if current == .enabled { lastError = nil }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard allowsChanges else { return }
        refresh()
        lastError = nil
        if enabled && status == .enabled { return }
        if !enabled && status == .notRegistered { return }
        // System Settings revocations need the user's approval, not repeated registration.
        if enabled && status == .requiresApproval {
            openSettings()
            return
        }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            lastError = "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        refresh()
        if status == .requiresApproval { lastError = nil }
    }

    func openSettings() {
        guard allowsChanges else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}

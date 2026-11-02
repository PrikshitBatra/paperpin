import Foundation
import ServiceManagement

private final class FakeLoginService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var registrationResult: SMAppService.Status = .enabled
    var failure: Error?
    var registerCount = 0
    var unregisterCount = 0
    func register() throws {
        registerCount += 1
        if let failure { throw failure }
        status = registrationResult
    }
    func unregister() throws {
        unregisterCount += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

@main
enum AppearanceChecks {
    static func main() {
        for enabled in [false, true] {
            for power in [false, true] {
                for transparency in [false, true] {
                    for motion in [false, true] {
                        let policy = AppearancePolicy(glassEnabled: enabled, lowPowerMode: power,
                                                      reduceTransparency: transparency, reduceMotion: motion)
                        precondition(policy.effectiveGlass == (enabled && !power && !transparency))
                        precondition(policy.animationsAllowed == (!power && !motion))
                    }
                }
            }
        }
        print("PASS glass and animation policies honor accessibility and Low Power Mode")

        let service = FakeLoginService()
        let controller = LoginItemController(service: service, allowsChanges: true, observeActivation: false)
        precondition(!controller.isEnabled)
        controller.setEnabled(true)
        precondition(controller.isEnabled && service.registerCount == 1)
        controller.setEnabled(true)
        precondition(service.registerCount == 1)
        controller.setEnabled(false)
        precondition(!controller.isEnabled && service.unregisterCount == 1)
        controller.setEnabled(false)
        precondition(service.unregisterCount == 1)
        print("PASS login registration is idempotent and based on system state")

        service.status = .requiresApproval
        controller.refresh()
        precondition(!controller.isEnabled && controller.needsApproval && controller.message != nil)
        precondition(service.registerCount == 1)
        service.status = .notFound
        controller.refresh()
        precondition(!controller.isEnabled && controller.message != nil)
        service.status = .enabled
        controller.refresh()
        service.failure = NSError(domain: "AppearanceChecks", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Test failure"])
        controller.setEnabled(false)
        precondition(controller.isEnabled && controller.lastError != nil)
        print("PASS revoked, missing, and failed login operations show honest state")

        let isolatedService = FakeLoginService()
        let isolated = LoginItemController(service: isolatedService, allowsChanges: false, observeActivation: false)
        isolated.setEnabled(true)
        isolated.setEnabled(false)
        precondition(isolatedService.registerCount == 0 && isolatedService.unregisterCount == 0)
        print("PASS QA registration guard prevents login item changes")
    }
}

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
                        for available in [false, true] {
                            let policy = AppearancePolicy(glassEnabled: enabled, lowPowerMode: power,
                                                          reduceTransparency: transparency, reduceMotion: motion,
                                                          nativeGlassAvailable: available)
                            precondition(policy.effectiveGlass == (available && enabled && !power && !transparency))
                            precondition(policy.animationsAllowed == (!power && !motion))
                        }
                    }
                }
            }
        }
        print("PASS all 32 glass policy combinations honor native support accessibility and Low Power Mode")

        let suite = "local.paperpin.appearance-check.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "LiquidGlassEnabled")
        let unsupported = AppearanceSettings(defaults: preferences, observeSystem: false, nativeGlassAvailable: false)
        precondition(unsupported.glassEnabled && !unsupported.effectiveGlass && unsupported.glassStatus?.isEmpty == false)
        unsupported.setGlassEnabled(false)
        precondition(unsupported.glassEnabled && preferences.bool(forKey: "LiquidGlassEnabled"))
        print("PASS unsupported native glass uses paper and guarded actions preserve the saved enabled preference")

        let supported = AppearanceSettings(defaults: preferences, observeSystem: false, nativeGlassAvailable: true)
        precondition(supported.nativeGlassAvailable && supported.glassEnabled)
        precondition(supported.effectiveGlass == (!supported.lowPowerMode && !supported.reduceTransparency))
        print("PASS a supported environment reuses the saved glass preference")

        preferences.set(false, forKey: "LiquidGlassEnabled")
        let unavailableOff = AppearanceSettings(defaults: preferences, observeSystem: false, nativeGlassAvailable: false)
        precondition(!unavailableOff.glassEnabled && unavailableOff.glassStatus?.isEmpty == false)
        unavailableOff.setGlassEnabled(true)
        precondition(!unavailableOff.glassEnabled && !preferences.bool(forKey: "LiquidGlassEnabled"))
        print("PASS unsupported glass explains availability even when disabled and cannot be enabled by an action")

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

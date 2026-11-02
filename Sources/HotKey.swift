import Carbon

final class HotKey {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static let signature: OSType = 0x50504E31  // PPN1

    init(action: @escaping () -> Void) { self.action = action }

    func register() -> Bool {
        unregister()
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, raw in
            guard let raw, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == HotKey.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKey>.fromOpaque(raw).takeUnretainedValue()
            owner.action()
            return noErr
        }, 1, &kind, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return false }
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                                            EventHotKeyID(signature: Self.signature, id: 1),
                                            GetApplicationEventTarget(), 0, &key)
        if registered != noErr { unregister(); return false }
        return true
    }

    func unregister() {
        if let key { UnregisterEventHotKey(key); self.key = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    deinit { unregister() }
}

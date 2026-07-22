import Carbon.HIToolbox
import Foundation

enum HotKeyRegistrationError: LocalizedError {
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable(let status):
            return "无法注册全局快捷键（错误码 \(status)）"
        }
    }
}

@MainActor
final class GlobalHotKeyManager {
    var onPressed: (() -> Void)?

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    func register(_ hotKey: HotKey) throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var eventID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventID
                )
                guard result == noErr, eventID.id == 1 else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.onPressed?() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            throw HotKeyRegistrationError.unavailable(handlerStatus)
        }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        guard status == noErr else {
            if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
            self.eventHandlerReference = nil
            throw HotKeyRegistrationError.unavailable(status)
        }
        hotKeyReference = reference
    }

    func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
        hotKeyReference = nil
        eventHandlerReference = nil
    }

    private static let signature: OSType = {
        let bytes = Array("CUTS".utf8)
        return bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }()
}

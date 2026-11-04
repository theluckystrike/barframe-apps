import AppKit
import Carbon.HIToolbox
import CallCore

/// Global shortcut via Carbon RegisterEventHotKey. Works inside the App Sandbox
/// without Accessibility permissions. Press = fire action; release = PTT re-mute.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onFire: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Tracks key-down state so release can be distinguished (Carbon hot keys
    /// report both keyDown and keyUp for the same registered ref).
    private var isDown = false
    /// False when the Carbon event handler could not be installed. Then no shortcut can fire.
    private(set) var handlerInstalled = false

    init() {
        var eventTypes = Self.eventKinds.map { EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: $0) }
        let handler: EventHandlerUPP = { _, event, _ in
            HotKeyCenter.shared.handle(event: event)
            return noErr
        }
        handlerInstalled = InstallEventHandler(GetApplicationEventTarget(), handler, eventTypes.count, &eventTypes, nil, &eventHandler) == noErr
    }

    /// Registers the shortcut; returns false when the OS rejected it (e.g. conflict).
    @discardableResult
    func register(config: HotKeyConfig, action: @escaping () -> Void) -> Bool {
        unregister()
        onFire = action
        let hotID = EventHotKeyID(signature: OSType(0x4352_4459) /* 'CRDY' */, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotID,
            GetApplicationEventTarget(),
            0,
            &ref)
        hotKeyRef = ref
        return status == noErr && handlerInstalled
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        isDown = false
    }

    static let eventKinds = [UInt32(kEventHotKeyPressed), UInt32(kEventHotKeyReleased)]

    private func handle(event: EventRef?) {
        guard let event else { return }
        handle(kind: GetEventKind(event))
    }

    func handle(kind: UInt32) {
        switch kind {
        case UInt32(kEventHotKeyPressed):
            if !isDown {
                isDown = true
                onFire?()
            }
        case UInt32(kEventHotKeyReleased):
            if isDown {
                isDown = false
                onRelease?()
            }
        default:
            break
        }
    }
}

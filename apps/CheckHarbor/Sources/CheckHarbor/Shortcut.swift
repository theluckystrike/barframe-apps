import AppKit
import Carbon
@MainActor final class Shortcut {
    static let shared=Shortcut()
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var action: (() -> Void)?
    var error=""
    func register(choice: Int, action: @escaping () -> Void) {
        self.action=action; error=""
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey=nil }
        if handler == nil {
            var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _,_,_ in
                Task { @MainActor in Shortcut.shared.action?() }; return noErr
            },1,&spec,nil,&handler)
        }
        if choice == 2 { return }
        let code=choice == 0 ? UInt32(kVK_ANSI_H) : UInt32(kVK_ANSI_J)
        let result=RegisterEventHotKey(code,UInt32(cmdKey | shiftKey),EventHotKeyID(signature:0x43484252,id:1),GetApplicationEventTarget(),0,&hotkey)
        if result != noErr { error=L("Shortcut unavailable. Use the menu bar or choose another shortcut.","Atajo no disponible. Usa la barra de menús o elige otro atajo.") }
    }
}

import Foundation
import IOKit
import IOKit.ps

enum HardwareEvent: Sendable { case power, battery, usb }

private let powerChanged: IOPowerSourceCallbackType = { context in
    guard let context else { return }
    Unmanaged<SystemNotifications>.fromOpaque(context).takeUnretainedValue().deliver(.power)
}
private let batteryChanged: IOServiceInterestCallback = { context, _, _, _ in
    guard let context else { return }
    Unmanaged<SystemNotifications>.fromOpaque(context).takeUnretainedValue().deliver(.battery)
}
private let usbChanged: IOServiceMatchingCallback = { context, iterator in
    while true {
        let entry = IOIteratorNext(iterator)
        if entry == 0 { break }
        IOObjectRelease(entry)
    }
    guard let context else { return }
    Unmanaged<SystemNotifications>.fromOpaque(context).takeUnretainedValue().deliver(.usb)
}

/// Notifications only schedule background reads; callbacks never enumerate hardware.
final class SystemNotifications {
    let onChange: @Sendable (HardwareEvent) -> Void
    private var powerSource: CFRunLoopSource?
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var battery: io_object_t = 0
    private(set) var errors: [String] = []
    private var started = false
    init(onChange: @escaping @Sendable (HardwareEvent) -> Void) { self.onChange = onChange }
    func deliver(_ event: HardwareEvent) { if started { onChange(event) } }
    func start() {
        guard !started else { return }
        started = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource(powerChanged, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        else { errors.append("Power notifications unavailable; polling continues.") }
        port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port, let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            errors.append("Hardware notifications unavailable; polling continues."); return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if IOServiceAddInterestNotification(port, service, kIOGeneralInterest, batteryChanged, context, &battery) != KERN_SUCCESS {
                errors.append("Battery notifications unavailable; polling continues.")
            }
        }
        let add = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"), usbChanged, context, &added)
        let remove = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"), usbChanged, context, &removed)
        // Drain the initial iterators to arm delivery. The normal initial refresh supplies data.
        for iterator in [added, removed] where iterator != 0 {
            while true { let entry = IOIteratorNext(iterator); if entry == 0 { break }; IOObjectRelease(entry) }
        }
        if add != KERN_SUCCESS || remove != KERN_SUCCESS { errors.append("USB notifications unavailable; polling continues.") }
    }
    func stop() {
        started = false
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        for object in [added, removed, battery] where object != 0 { IOObjectRelease(object) }
        added = 0; removed = 0; battery = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        errors = []
    }
    deinit { stop() }
}

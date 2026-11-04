// Inspect only this worktree’s normally launched app. No network or helper is used by the app.
import AppKit
import ApplicationServices
let name = "PortSense"
let expectedURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/PortSense.app").standardizedFileURL
func attr(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success ? value : nil
}
func dump(_ item: AXUIElement, _ depth: Int = 0) {
    guard depth < 15 else { return }
    let keys = ["AXRole", "AXTitle", "AXDescription", "AXHelp", "AXIdentifier"]
    print(String(repeating: " ", count: depth) + keys.compactMap { key in attr(item, key).map { "\(key)=\($0)" } }.joined(separator: "; "))
    if let children = attr(item, "AXChildren") as? [AXUIElement] { for child in children { dump(child, depth + 1) } }
}
func press(_ item: AXUIElement, _ label: String) -> Bool {
    if attr(item, "AXDescription") as? String == label {
        print("PRESS \(label): \(AXUIElementPerformAction(item, "AXPress" as CFString).rawValue)")
        return true
    }
    if let children = attr(item, "AXChildren") as? [AXUIElement] {
        for child in children { if press(child, label) { return true } }
    }
    return false
}
for app in NSWorkspace.shared.runningApplications where app.bundleURL?.standardizedFileURL == expectedURL {
    print("APP \(name); PID \(app.processIdentifier); TRUSTED \(AXIsProcessTrusted())")
    let root = AXUIElementCreateApplication(app.processIdentifier)
    if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--click-status" {
        if let bar = attr(root, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(bar, to: AXUIElement.self)
            if let item = (attr(element, "AXChildren") as? [AXUIElement])?.first,
               let position = attr(item, "AXPosition"), let size = attr(item, "AXSize") {
                var point = CGPoint.zero; var dimensions = CGSize.zero
                AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
                AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions)
                point.x += dimensions.width / 2; point.y += dimensions.height / 2
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
                print("PHYSICAL STATUS CLICK: \(point)")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    } else if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--escape" {
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }
        Thread.sleep(forTimeInterval: 0.5)
    } else if CommandLine.arguments.count > 1 {
        let windows = attr(root, "AXWindows") as? [AXUIElement] ?? []
        print("FOUND CONTROL: \(windows.contains { press($0, CommandLine.arguments[1]) })")
        Thread.sleep(forTimeInterval: 0.5)
    }
    for key in ["AXWindows", "AXExtrasMenuBar"] {
        if let values = attr(root, key) as? [AXUIElement] { print(key); values.forEach { dump($0) } }
        else if let value = attr(root, key), CFGetTypeID(value) == AXUIElementGetTypeID() { print(key); dump(unsafeBitCast(value, to: AXUIElement.self)) }
    }
}

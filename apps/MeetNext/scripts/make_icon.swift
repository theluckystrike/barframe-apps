import AppKit

let args = ProcessInfo.processInfo.arguments
if args.contains("--regen-icon") {
    let size = 1024
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.94, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 200, yRadius: 200).fill()

    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 460, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
    ]
    let str = NSAttributedString(string: "M", attributes: attrs)
    str.draw(in: NSRect(x: 0, y: 60, width: CGFloat(size), height: 620))

    // small clock tick marks under the letter
    NSColor.white.setFill()
    for i in 0..<3 {
        let rect = NSRect(x: 320 + i * 140, y: 130, width: 80, height: 80)
        NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon render failed\n".utf8))
    exit(1)
    }
    let out = args.count > 2 ? args[2] : "icon_1024.png"
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

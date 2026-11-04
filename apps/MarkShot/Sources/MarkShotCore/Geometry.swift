import Foundation
import CoreGraphics

public enum Tool: String, CaseIterable, Codable { case arrow, rectangle, text, highlight, step, blur, pixelate, crop }
public struct Mark: Equatable {
    public var tool: Tool
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    public var number: Int
    public init(_ tool: Tool, _ start: CGPoint, _ end: CGPoint, text: String = "", number: Int = 1) {
        self.tool = tool; self.start = start; self.end = end; self.text = text; self.number = number
    }
    public var rect: CGRect { Geometry.rect(start, end) }
}
public enum Geometry {
    public static func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }
    public static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
    public static func crop(_ rect: CGRect, in size: CGSize) -> CGRect? {
        let result = rect.intersection(CGRect(origin: .zero, size: size)).integral
        guard !result.isNull, result.width >= 2, result.height >= 2 else { return nil }
        return result.intersection(CGRect(origin: .zero, size: size))
    }
    public static func imagePoint(_ point: CGPoint, image: CGSize, view: CGSize) -> CGPoint {
        guard view.width > 0, view.height > 0 else { return .zero }
        return clamp(CGPoint(x: point.x * image.width / view.width, y: point.y * image.height / view.height), to: image)
    }
    public static func arrowHead(start: CGPoint, end: CGPoint, length: CGFloat = 18) -> [CGPoint] {
        let angle = atan2(end.y-start.y,end.x-start.x)
        return [CGPoint(x:end.x-length*cos(angle - .pi/6),y:end.y-length*sin(angle - .pi/6)),end,
                CGPoint(x:end.x-length*cos(angle + .pi/6),y:end.y-length*sin(angle + .pi/6))]
    }
    public static func nextStep(_ marks: [Mark]) -> Int { (marks.filter { $0.tool == .step }.map(\.number).max() ?? 0) + 1 }
    public static func valid(_ mark: Mark) -> Bool {
        if mark.tool == .text { return !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if mark.tool == .step { return true }
        return hypot(mark.end.x-mark.start.x,mark.end.y-mark.start.y) >= 2
    }
    public static func filename(date: Date, id: UUID = UUID()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "MarkShot-\(formatter.string(from: date))-\(id.uuidString.prefix(8)).png"
    }
}
public struct Timeline<Value> {
    public private(set) var current: Value
    public private(set) var undoItems: [Value] = []
    public private(set) var redoItems: [Value] = []
    public init(_ value: Value) { current = value }
    public mutating func commit(_ value: Value) { undoItems.append(current); if undoItems.count > 40 { undoItems.removeFirst() }; current = value; redoItems = [] }
    public mutating func undo() { guard let value = undoItems.popLast() else { return }; redoItems.append(current); current = value }
    public mutating func redo() { guard let value = redoItems.popLast() else { return }; undoItems.append(current); current = value }
}
public enum Recent {
    public static func adding<T: Equatable>(_ value: T, to values: [T], limit: Int = 10) -> [T] {
        guard limit > 0 else { return [] }
        return Array(([value] + values.filter { $0 != value }).prefix(limit))
    }
}

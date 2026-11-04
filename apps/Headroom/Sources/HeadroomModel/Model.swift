import Foundation
import CProbe
public struct Reading: Sendable {
 public var total: Double, available: Double, compressed: Double, swap: Double, resident: Double
 public var pressure: Int, agents: Int, unreadable: Int
 public var memoryOK: Bool, processesOK: Bool
 public init(total: Double = 32, available: Double = 14, compressed: Double = 3, swap: Double = 0, resident: Double = 6, pressure: Int = 1, agents: Int = 3, unreadable: Int = 0, memoryOK: Bool = true, processesOK: Bool = true) {
 self.total=total;self.available=available;self.compressed=compressed;self.swap=swap;self.resident=resident;self.pressure=pressure;self.agents=agents;self.unreadable=unreadable;self.memoryOK=memoryOK;self.processesOK=processesOK
 }
 public static func live() -> Reading {
 let r=hr_read(); let g=1073741824.0
 return Reading(total: Double(r.total)/g, available: Double(r.available)/g, compressed: Double(r.compressed)/g, swap: Double(r.swap)/g, resident: Double(r.resident)/g, pressure:Int(r.pressure),agents:Int(r.agents),unreadable:Int(r.unreadable),memoryOK:r.memoryOK != 0,processesOK:r.processesOK != 0)
 }
 public func capacity(budget: Double, reserve: Double = 4) -> Int? {
 guard memoryOK, available.isFinite, available >= 0, budget.isFinite, budget >= 0.5, reserve.isFinite, reserve >= 0 else { return nil }
 guard pressure == 1, swap == 0 else { return 0 }
 return Int(min(10000, floor(max(0, available-reserve)/budget)))
 }
 public var pressureText: String { !memoryOK ? "Unavailable" : pressure == 1 ? "Normal" : pressure == 2 ? "Warning" : pressure == 4 ? "Critical" : "Unknown" }
 public static func sample(_ scenario: Int) -> Reading {
 switch scenario { case 1: return Reading(available:3,compressed:9,swap:2,resident:8,pressure:2,agents:5)
 case 2: return Reading(available:20,compressed:1,resident:3,agents:2)
 default: return Reading() }
 }
}

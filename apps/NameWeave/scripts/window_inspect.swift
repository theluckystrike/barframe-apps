import AppKit
let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]]
for window in list {
let owner = window[kCGWindowOwnerName as String] as? String ?? ""
if owner.contains("NameWeave") || owner.contains("openAndSave") { print(window) }
}

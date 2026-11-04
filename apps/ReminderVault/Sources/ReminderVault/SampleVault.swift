import Foundation

enum SampleVault {
    static var url: URL? {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("ReminderVault_ReminderVault.bundle/Resources/SampleVault/Today.md"), FileManager.default.fileExists(atPath: resource.path) { return resource }
        return Bundle.module.url(forResource: "Today", withExtension: "md", subdirectory: "Resources/SampleVault")
    }
}

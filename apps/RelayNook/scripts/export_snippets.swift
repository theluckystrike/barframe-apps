import Foundation
@main struct ExportSnippets {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = ["agentping-hook.sh": Snippets.hookScript, "install-hook.sh": Snippets.installScript(), "claude-settings.json": Snippets.claudeJSON, "codex-config.toml": Snippets.codexTOML, "generic-function.sh": Snippets.genericFunction(), "hook.pl": Snippets.hookPerl, "generic.pl": Snippets.genericPerl]
        if CommandLine.arguments.contains("--fixtures") {
            // Fixture credential. Never export an installation token.
            let fixture = "0123456789abcdef0123456789abcdef"
            try Data(Snippets.installScript(token: fixture).utf8).write(to: directory.appendingPathComponent("install-bound-hook.sh"))
            try Data(Snippets.genericFunction(token: fixture).utf8).write(to: directory.appendingPathComponent("generic-bound-function.sh"))
        }
        for (name, text) in files { try Data((text + "\n").utf8).write(to: directory.appendingPathComponent(name)) }
    }
}

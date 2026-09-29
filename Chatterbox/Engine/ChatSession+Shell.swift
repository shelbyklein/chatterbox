import Foundation

/// "!command" in the message box: runs a shell command in the chat's folder, streams its
/// output into the chat, and hands both to the agent with your next message, like Claude
/// Code's shell mode.
extension ChatSession {
    /// Where the chat works: its project or Studio, its Codex folder, or the working folder.
    var workingFolder: String {
        record.boundFolder ?? record.codex?.folder ?? UserDefaults.standard.string(forKey: "codexFolder") ?? NSHomeDirectory()
    }

    static let shellOutputLimit = 100_000

    func runShell(_ command: String) {
        guard !command.isEmpty else { return }
        let itemID = appendItem(DisplayItem(kind: .shell, text: command, toolState: .running, detail: ""))
        onChange?(self)
        let folder = workingFolder
        Task { [weak self] in
            let (output, status) = await Self.execute(command, in: folder) { chunk in
                Task { @MainActor in
                    self?.updateItem(itemID) {
                        let current = $0.detail ?? ""
                        if current.count < Self.shellOutputLimit { $0.detail = current + chunk }
                    }
                }
            }
            await MainActor.run {
                guard let self else { return }
                var text = output
                if text.count > Self.shellOutputLimit { text = String(text.prefix(Self.shellOutputLimit)) + "\n\u{2026} (output cut off)" }
                self.updateItem(itemID) {
                    $0.detail = text
                    $0.toolState = status == 0 ? .done : .failed
                    if status != 0 { $0.text = command }
                }
                let note = "<shell_command cwd=\"\(folder)\" exit_code=\"\(status)\">\n$ \(command)\n\(String(text.suffix(20_000)))\n</shell_command>"
                self.record.pendingShellContext = [self.record.pendingShellContext, note].compactMap { $0 }.joined(separator: "\n\n")
                self.onChange?(self)
            }
        }
    }

    /// The pending "!" commands for the agent's next message, with a line on what they are.
    func takeShellContext() -> String? {
        guard let context = record.pendingShellContext else { return nil }
        record.pendingShellContext = nil
        return "The user ran these commands in the chat themselves; here's what they printed:\n\n" + context
    }

    /// Runs through the user's login shell so their PATH and aliases apply. Output streams
    /// through `onOutput`; returns everything printed and the exit status.
    private static func execute(_ command: String, in folder: String, onOutput: @escaping @Sendable (String) -> Void) async -> (String, Int32) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            process.environment = BinaryLocator.environment
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let collected = OutputCollector()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                collected.append(text)
                onOutput(text)
            }
            do { try process.run() } catch { return ("Couldn't run the command: \(error.localizedDescription)", -1) }
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if !rest.isEmpty { collected.append(rest); onOutput(rest) }
            return (collected.text, process.terminationStatus)
        }.value
    }
}

/// Collects output from the pipe's background callbacks.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ text: String) { lock.lock(); buffer += text; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return buffer }
}

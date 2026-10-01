import Foundation

/// One of Claude Code's tasks: its plan, kept by number.
struct ClaudeTask: Codable, Equatable {
    var id: String
    var subject: String
    /// "pending", "in_progress", or "completed".
    var status: String
}

/// Newer Claude Code keeps its plan with task tools (TaskCreate, TaskUpdate, TaskList)
/// instead of one TodoWrite list. This follows them and shows the result as the plan card.
extension ChatSession {
    static let claudeTaskTools: Set<String> = ["TaskCreate", "TaskUpdate", "TaskList", "TaskGet"]

    /// A task tool's input, once complete: TaskUpdate changes a task right away; TaskCreate
    /// waits for its result, which says the new task's number.
    func claudeTaskToolUsed(_ name: String, input: JSON, useID: String) {
        switch name {
        case "TaskUpdate":
            guard let id = Self.taskID(input["taskId"]) else { return }
            var tasks = record.claudeTasks ?? []
            if let index = tasks.firstIndex(where: { $0.id == id }) {
                if let status = input["status"]?.string {
                    if status == "deleted" { tasks.remove(at: index) } else { tasks[index].status = Self.planStatus(status) }
                }
                if index < tasks.count, let subject = input["subject"]?.string, !subject.isEmpty { tasks[index].subject = subject }
            } else if let subject = input["subject"]?.string {
                tasks.append(ClaudeTask(id: id, subject: subject, status: Self.planStatus(input["status"]?.string ?? "pending")))
            }
            record.claudeTasks = tasks
            showClaudeTasks()
        default:
            break
        }
    }

    /// A task tool's result: a created task's number, or the whole list from TaskList.
    func claudeTaskResult(_ name: String, input: JSON, result: String) {
        var tasks = record.claudeTasks ?? []
        switch name {
        case "TaskCreate":
            // "Task #3 created successfully: Bake"
            guard let id = Self.firstMatch(#"#(\d+)"#, in: result) else { return }
            let subject = input["subject"]?.string ?? input["activeForm"]?.string ?? "Task \(id)"
            if !tasks.contains(where: { $0.id == id }) { tasks.append(ClaudeTask(id: id, subject: subject, status: "pending")) }
        case "TaskList":
            // "#1 [completed] Mix dough" per line. Only fills in tasks this chat doesn't know;
            // the list can be sent before an update that ran alongside it lands.
            for line in result.split(separator: "\n") {
                let text = String(line)
                guard let id = Self.firstMatch(#"^#(\d+)"#, in: text), !tasks.contains(where: { $0.id == id }),
                      let status = Self.firstMatch(#"\[(\w+)\]"#, in: text),
                      let close = text.range(of: "] ") else { continue }
                tasks.append(ClaudeTask(id: id, subject: String(text[close.upperBound...]), status: Self.planStatus(status)))
            }
        default:
            return
        }
        record.claudeTasks = tasks
        showClaudeTasks()
    }

    private func showClaudeTasks() {
        let tasks = (record.claudeTasks ?? []).sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
        guard !tasks.isEmpty else { return }
        showPlan(tasks.map { PlanStep(step: $0.subject, status: $0.status) })
    }

    private static func taskID(_ value: JSON?) -> String? {
        if let text = value?.string { return text }
        if let number = value?.int { return String(number) }
        return nil
    }

    private static func planStatus(_ status: String) -> String {
        ["pending", "in_progress", "completed"].contains(status) ? status : "pending"
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

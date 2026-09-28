import Foundation

enum Tools {
    /// Tools Chatterbox runs itself. Eager input streaming means the API doesn't
    /// validate inputs, so `run` validates them before doing anything.
    static let clientTools: [JSON] = [
        [
            "name": "update_plan",
            "description": "Show or update a short step-by-step plan in the user's chat window. Use for multi-step work only. Exactly one step should be in_progress until everything is completed.",
            "eager_input_streaming": true,
            "input_schema": [
                "type": "object",
                "properties": [
                    "explanation": ["type": "string", "description": "Optional one-line reason for a change to the plan."],
                    "plan": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "step": ["type": "string", "description": "5-7 word description of the step."],
                                "status": ["type": "string", "enum": ["pending", "in_progress", "completed"]],
                            ],
                            "required": ["step", "status"],
                        ],
                    ],
                ],
                "required": ["plan"],
            ],
        ],
        [
            "name": "get_current_datetime",
            "description": "Get the user's current local date, time, and time zone.",
            "eager_input_streaming": true,
            "input_schema": ["type": "object", "properties": [:]],
        ],
    ]

    static let serverTools: [JSON] = [
        ["type": "web_search_20260209", "name": "web_search", "max_uses": 5],
        ["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 5],
    ]

    /// For models older than Opus/Sonnet 4.6, which lack dynamic filtering.
    static let basicServerTools: [JSON] = [
        ["type": "web_search_20250305", "name": "web_search", "max_uses": 5],
        ["type": "web_fetch_20250910", "name": "web_fetch", "max_uses": 5],
    ]

    static func definitions(webAccess: Bool, basicWebTools: Bool = false) -> [JSON] {
        clientTools + (webAccess ? (basicWebTools ? basicServerTools : serverTools) : [])
    }

    enum Outcome {
        case text(String)
        case plan([PlanStep], String)
        case error(String)
    }

    static func run(name: String, input: JSON) -> Outcome {
        switch name {
        case "update_plan":
            guard let rawSteps = input["plan"]?.array, !rawSteps.isEmpty else {
                return .error("update_plan needs a non-empty `plan` array.")
            }
            var steps: [PlanStep] = []
            for raw in rawSteps {
                guard let step = raw["step"]?.string, let status = raw["status"]?.string,
                      ["pending", "in_progress", "completed"].contains(status) else {
                    return .error("Each plan item needs `step` and a `status` of pending, in_progress, or completed.")
                }
                steps.append(PlanStep(step: step, status: status))
            }
            return .plan(steps, "Plan updated.")

        case "get_current_datetime":
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            return .text("\(formatter.string(from: now)) (\(TimeZone.current.identifier))")

        default:
            return .error("Unknown tool: \(name)")
        }
    }

    /// Human-readable status line for a tool call.
    static func label(name: String, input: JSON?) -> String {
        switch name {
        case "web_search":
            if let q = input?["query"]?.string { return "Searching the web for \u{201C}\(q)\u{201D}" }
            return "Searching the web"
        case "web_fetch":
            if let url = input?["url"]?.string { return "Reading \(URL(string: url)?.host ?? url)" }
            return "Reading a page"
        case "get_current_datetime": return "Checking the time"
        case "update_plan": return "Updating the plan"
        case "code_execution", "bash_code_execution", "text_editor_code_execution": return "Sifting through results"
        default: return "Using \(name)"
        }
    }
}

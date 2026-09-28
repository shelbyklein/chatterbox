import Foundation

/// Loads the prompt files bundled from the repo's `prompts/` folder.
enum Prompts {
    static let vars: [String: String] = [
        "assistant_name": "Chatterbox",
        "assistant_role": "a conversational assistant for questions, research, writing, and thinking things through",
        "product_name": "Chatterbox, a Mac chat app",
        "product_specific_rules": """
        # About this app
        - The user reads your replies in a Mac chat window that renders Markdown. Text you write before a tool call appears as a dim, inline note; only your final message appears as the main reply.
        - The user can't see raw tool output, such as search results or fetched pages. Summarize what matters and link sources when you use the web.
        - Blocks tagged <personality_spec>, <user_steering>, <turn_aborted>, or <conversation_summary> come from the app, not from something the user typed. Follow them.
        """,
    ]

    static func load(_ name: String, subdirectory: String? = nil) -> String {
        let dir = subdirectory.map { "prompts/\($0)" } ?? "prompts"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: dir),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    /// Frozen for the life of the app so the prompt cache stays warm. Personality lives
    /// in the conversation instead, so it can change mid-chat.
    static let system: String = {
        var out = load("conversational_base")
        var filled = vars
        filled["personality"] = "Your personality is described in the most recent <personality_spec> block."
        for (key, value) in filled {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static func personalitySpec(_ p: Personality) -> String {
        let body: String
        switch p {
        case .friendly: body = load("friendly", subdirectory: "personalities")
        case .pragmatic: body = load("pragmatic", subdirectory: "personalities")
        case .neutral: body = "# Personality\n\nUse a neutral, concise, matter-of-fact tone."
        }
        return "<personality_spec>\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n</personality_spec>"
    }

    static var compaction: String { load("compaction") }

    /// Codex brings its own conversational system prompt; this adds the tone and the app context.
    static func codexDeveloperInstructions(_ p: Personality) -> String {
        """
        \(personalitySpec(p))

        # About this app
        You're running inside Chatterbox, a Mac chat app, not a terminal. The user reads your messages in a chat window that renders Markdown, and they can't see command output unless you summarize it. Your commentary messages show as small inline notes; your final answer is the main reply. A newer <personality_spec> block from the app replaces this one.
        """
    }
}

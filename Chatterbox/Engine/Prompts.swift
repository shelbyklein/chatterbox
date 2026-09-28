import Foundation

/// Loads the prompt files bundled from the repo's `prompts/` folder.
enum Prompts {
    static func load(_ name: String, subdirectory: String? = nil) -> String {
        let dir = subdirectory.map { "prompts/\($0)" } ?? "prompts"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: dir),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func personalitySpec(_ p: Personality) -> String {
        let body: String
        switch p {
        case .friendly: body = load("friendly", subdirectory: "personalities")
        case .pragmatic: body = load("pragmatic", subdirectory: "personalities")
        case .neutral: body = "# Personality\n\nUse a neutral, concise, matter-of-fact tone."
        }
        return "<personality_spec>\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n</personality_spec>"
    }

    /// Added to Claude Code's system prompt and to Codex's developer instructions.
    /// Both agents bring their own base prompt; this adds the tone and the app context.
    static func agentInstructions(_ p: Personality) -> String {
        """
        \(personalitySpec(p))

        # About this app
        You're running inside Chatterbox, a Mac chat app, not a terminal. The user reads your messages in a chat window that renders Markdown, and they can't see command or tool output unless you summarize it. Text you write before a tool call shows as a small inline note; your last message of the turn is the main reply. Blocks tagged <personality_spec> or <conversation_handoff> come from the app, not from something the user typed. A newer <personality_spec> block replaces this one.
        """
    }

    /// Hands the conversation to a different agent, or to a fresh session of the same one.
    static func handoff(from other: String, transcript: String, isWholeConversation: Bool) -> String {
        """
        <conversation_handoff>
        \(isWholeConversation
            ? "This chat started before your session did. Here is the conversation so far"
            : "The user switched agents in this chat. Here is what happened while \(other) was answering"), so you can continue without asking them to repeat anything:

        \(transcript)
        </conversation_handoff>
        """
    }
}

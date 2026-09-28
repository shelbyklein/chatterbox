// Provider-agnostic conversation loop adapted from the patterns in openai/codex.
// Plug in any model by implementing ModelClient; wire the events to your UI.

import { readFileSync } from "node:fs";
import { join } from "node:path";

// ---------- Types ----------

export type Role = "system" | "user" | "assistant" | "tool";

export interface ToolCall {
  id: string;
  name: string;
  args: unknown;
}

export interface Message {
  role: Role;
  content: string;
  toolCalls?: ToolCall[];
  toolCallId?: string;
  // Assistant text is either mid-turn narration or the answer that ends the turn.
  phase?: "commentary" | "final";
}

export interface ModelClient {
  // Streams text deltas via onDelta and resolves with the full assistant message.
  complete(
    messages: Message[],
    opts: { onDelta: (text: string) => void; signal: AbortSignal },
  ): Promise<Message>;
  countTokens(messages: Message[]): number;
}

export type ToolRunner = (call: ToolCall, signal: AbortSignal) => Promise<string>;

export type ConversationEvent =
  | { type: "delta"; text: string }
  | { type: "commentary"; text: string } // show inline and dimmed, like "thinking out loud"
  | { type: "final"; text: string } // the real reply
  | { type: "tool_start"; call: ToolCall }
  | { type: "tool_end"; call: ToolCall; output: string }
  | { type: "steer_applied"; text: string }
  | { type: "compacted" }
  | { type: "turn_end"; interrupted: boolean };

export type Personality = "friendly" | "pragmatic" | "none";

export interface ConversationOptions {
  model: ModelClient;
  runTool: ToolRunner;
  onEvent: (e: ConversationEvent) => void;
  promptVars: Record<string, string>; // assistant_name, assistant_role, product_name, product_specific_rules
  personality?: Personality;
  promptDir?: string;
  contextLimit?: number; // tokens
  compactAt?: number; // fraction of contextLimit
  maxToolRounds?: number;
}

// ---------- Prompt assembly ----------

function fill(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, k) => vars[k] ?? "");
}

function loadPersonality(dir: string, p: Personality): string {
  return p === "none" ? "" : readFileSync(join(dir, "personalities", `${p}.md`), "utf8");
}

// ---------- Conversation ----------

export class Conversation {
  private history: Message[] = [];
  private pending: string[] = [];
  private abort: AbortController | null = null;
  private personality: Personality;
  private sentPersonality: Personality | null = null;
  private readonly dir: string;
  private readonly systemPrompt: string;

  constructor(private readonly o: ConversationOptions) {
    this.dir = o.promptDir ?? join(process.cwd(), "prompts");
    this.personality = o.personality ?? "friendly";
    // The base prompt is static. Personality goes into a separate context block
    // so it can change mid-conversation without rewriting the system prompt.
    this.systemPrompt = fill(readFileSync(join(this.dir, "conversational_base.md"), "utf8"), {
      ...o.promptVars,
      personality: "Your personality is described in the most recent <personality_spec> block.",
    });
  }

  get running(): boolean {
    return this.abort !== null;
  }

  // Main entry point for user input. While a turn is running, the message
  // steers that turn instead of queueing a new one.
  async send(text: string): Promise<void> {
    if (this.running) {
      this.pending.push(text);
      return;
    }
    this.history.push({ role: "user", content: text });
    await this.runTurn();
  }

  interrupt(): void {
    this.abort?.abort();
  }

  setPersonality(p: Personality): void {
    this.personality = p;
  }

  private contextFragments(): Message[] {
    // Send a fragment only when it changes, so the model doesn't see it repeated every turn.
    const out: Message[] = [];
    if (this.personality !== this.sentPersonality) {
      const body = loadPersonality(this.dir, this.personality) || "Use a neutral, concise tone.";
      out.push({ role: "user", content: `<personality_spec>\n${body}\n</personality_spec>` });
      this.sentPersonality = this.personality;
    }
    return out;
  }

  private drainSteering(): void {
    for (const text of this.pending.splice(0)) {
      this.history.push({
        role: "user",
        content: `<user_steering>\n${text}\n</user_steering>\n(The user sent this while you were working. Fold it into the current task.)`,
      });
      this.o.onEvent({ type: "steer_applied", text });
    }
  }

  private async runTurn(): Promise<void> {
    const { model, runTool, onEvent } = this.o;
    const maxRounds = this.o.maxToolRounds ?? 50;
    this.abort = new AbortController();
    const signal = this.abort.signal;
    let interrupted = false;

    try {
      this.history.push(...this.contextFragments());

      for (let round = 0; round < maxRounds; round++) {
        this.drainSteering();
        await this.maybeCompact(signal);

        const reply = await model.complete(
          [{ role: "system", content: this.systemPrompt }, ...this.history],
          { signal, onDelta: (text) => onEvent({ type: "delta", text }) },
        );

        const hasTools = (reply.toolCalls?.length ?? 0) > 0;
        // Text sent alongside tool calls is a preamble; text with no tool calls ends the turn.
        reply.phase = hasTools ? "commentary" : "final";
        this.history.push(reply);

        if (!hasTools) {
          // If the user steered during the final generation, keep going instead of ending.
          if (this.pending.length > 0) continue;
          onEvent({ type: "final", text: reply.content });
          return;
        }

        if (reply.content.trim()) onEvent({ type: "commentary", text: reply.content });

        for (const call of reply.toolCalls!) {
          onEvent({ type: "tool_start", call });
          const output = await runTool(call, signal);
          onEvent({ type: "tool_end", call, output });
          this.history.push({ role: "tool", toolCallId: call.id, content: output });
        }
      }
    } catch (err) {
      if (signal.aborted) {
        interrupted = true;
        this.history.push({
          role: "user",
          content: "<turn_aborted>The user interrupted the previous turn.</turn_aborted>",
        });
      } else {
        throw err;
      }
    } finally {
      this.abort = null;
      onEvent({ type: "turn_end", interrupted });
      // Messages that arrive after the last model call become the next turn.
      if (this.pending.length > 0) {
        const next = this.pending.splice(0).join("\n\n");
        void this.send(next);
      }
    }
  }

  // Summarize old history into a handoff note when the context gets full,
  // while keeping recent user messages verbatim so the tone carries over.
  private async maybeCompact(signal: AbortSignal): Promise<void> {
    const limit = this.o.contextLimit ?? 200_000;
    const threshold = limit * (this.o.compactAt ?? 0.8);
    if (this.o.model.countTokens(this.history) < threshold) return;

    const instructions = readFileSync(join(this.dir, "compaction.md"), "utf8");
    const summary = await this.o.model.complete(
      [...this.history, { role: "user", content: instructions }],
      { signal, onDelta: () => {} },
    );

    const recentUser = this.history
      .filter((m) => m.role === "user" && !m.content.startsWith("<"))
      .slice(-3);

    this.history = [
      {
        role: "user",
        content:
          "<conversation_summary>\nEarlier parts of this conversation were summarized. " +
          "Continue from here without repeating completed work.\n\n" +
          summary.content +
          "\n</conversation_summary>",
      },
      ...recentUser,
    ];
    this.sentPersonality = null; // re-send the personality after compaction
    this.history.push(...this.contextFragments());
    this.o.onEvent({ type: "compacted" });
  }
}

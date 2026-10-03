import AppKit
import SwiftUI

// Run through scripts/test-chat-switch-perf.sh. Uses copies of saved chats; no agent is resumed.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

func ms(_ seconds: Double) -> String { String(format: "%7.1f ms", seconds * 1000) }
func now() -> Double { CFAbsoluteTimeGetCurrent() }
func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

// PERF_CURSOR=count counts NSCursor.set calls; =dedupe also skips sets of the cursor already showing.
var cursorSets = 0, cursorSkips = 0
let cursorMode = ProcessInfo.processInfo.environment["PERF_CURSOR"]
extension NSCursor {
    @objc func perfSet() {
        cursorSets += 1
        if cursorMode == "dedupe", NSCursor.current === self { cursorSkips += 1; return }
        perfSet()
    }
}
if cursorMode != nil, let a = class_getInstanceMethod(NSCursor.self, #selector(NSCursor.set)),
   let b = class_getInstanceMethod(NSCursor.self, #selector(NSCursor.perfSet)) { method_exchangeImplementations(a, b) }

@MainActor
func run() async throws {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"],
          root.hasPrefix("/tmp/chatterbox-perf.") else { fatalError("Use the isolated runner") }
    UserDefaults.standard.setVolatileDomain([
        "dotCheckIns": false, "dotWatchWaiting": false, "dotSummarizeFinished": false,
        "dotEmailWatch": false, "companionEnabled": false, "notifyNeeds": false,
        "notifyFinished": false, "keepMacAwake": false
    ], forName: UserDefaults.argumentDomain)
    let model = AppModel()
    let heavy = model.activeSessions.filter { !$0.isDot }.sorted { $0.items.count > $1.items.count }.prefix(6)
    guard heavy.count >= 2 else { fatalError("Need at least two saved chats") }

    // Parsing alone: what each switch pays for the newest 40 rows' markdown.
    print("Per-chat parse cost of the newest 40 rows (median of 5):")
    for session in heavy {
        let texts = session.items.suffix(ChatView.rowPage).map(\.text).filter { !$0.isEmpty }
        var blocks: [Double] = [], inline: [Double] = [], paths: [Double] = []
        for _ in 0..<5 {
            var t = now(); for text in texts { _ = MarkdownText.blocks(text) }; blocks.append(now() - t)
            t = now()
            let contexts = texts.map { PathLinks.context(for: $0, folder: session.workingFolder) }
            paths.append(now() - t)
            t = now()
            for (text, context) in zip(texts, contexts) { _ = MarkdownText.inline(text, paths: context) }
            inline.append(now() - t)
        }
        print("  \(session.items.count) items  blocks \(ms(median(blocks)))  path context \(ms(median(paths)))  inline+links \(ms(median(inline)))  \(session.title.prefix(40))")
    }

    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: ContentView().environment(model))
    // Like the app's WindowGroup: only the minimum size constrains the window.
    host.sizingOptions = [.minSize]
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    try await Task.sleep(for: .seconds(2))

    // A switch: change selection, then force the layout and draw the user would wait for.
    // Afterwards, a 2 ms timer measures how long the main thread stays blocked while it settles.
    var sync: [UUID: [Double]] = [:], stalls: [UUID: [Double]] = [:]
    for _ in 0..<(Int(ProcessInfo.processInfo.environment["PERF_ROUNDS"] ?? "") ?? 4) {
        for session in heavy {
            let t = now()
            model.selectedID = session.id
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            sync[session.id, default: []].append(now() - t)
            var last = now(), stalled = 0.0
            let deadline = last + 1.0
            while now() < deadline {
                try await Task.sleep(for: .milliseconds(2))
                let tick = now()
                if tick - last > 0.016 { stalled += tick - last }
                last = tick
            }
            stalls[session.id, default: []].append(stalled)
        }
    }
    print("\nSwitching (first round includes first-time loading; median of the later rounds):")
    var all: [Double] = []
    for session in heavy {
        let s = sync[session.id]!, st = stalls[session.id]!
        all += s.dropFirst()
        print("  \(session.items.count) items  first \(ms(s[0]))  switch \(ms(median(Array(s.dropFirst()))))  then blocked \(ms(median(Array(st.dropFirst())))))  \(session.title.prefix(40))")
    }
    if cursorMode != nil { print("cursor sets \(cursorSets), skipped \(cursorSkips)") }
    print(String(format: "\nRESULT median switch %.1f ms, worst %.1f ms", median(all) * 1000, all.max()! * 1000))
}

Task { @MainActor in
    do { try await run(); exit(0) } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()

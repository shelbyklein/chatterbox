import Foundation
import SwiftUI

// Run through scripts/test-markdown-cache.sh. Checks that the cached markdown parse and
// path lookups give exactly what the uncached functions give, then times both.
// Only files in a temp folder are touched.

var failures = 0
func check(_ ok: Bool, _ message: String) {
    if !ok { failures += 1; print("FAIL: \(message)") }
}

@MainActor
func run() {
    guard let root = ProcessInfo.processInfo.environment["CHATTERBOX_MDCACHE_DIR"],
          root.hasPrefix("/tmp/chatterbox-mdcache.") else { fatalError("Use the test script") }
    let fm = FileManager.default
    let work = root + "/work"
    try! fm.createDirectory(atPath: work + "/out/final", withIntermediateDirectories: true)
    for file in ["notes.md", "out/logo.png", "out/final/index.html", "Package.swift"] {
        fm.createFile(atPath: work + "/" + file, contents: Data("x".utf8))
    }

    func message(_ n: Int) -> String {
        """
        # Result \(n)

        I wrote `\(work)/out/` and `out/logo.png`, plus `notes.md` and `missing-\(n).txt`. Also `record.items` and `Package.swift:42`.
        Second **bold** line with *italics* and [a link](https://example.com/\(n)) and ![img](out/logo.png).

        - first item with `final/index.html`
        - second item
          wrapped continuation
            - nested \(n)
        1. numbered `/nope/\(n)`
        2) another

        > quoted `notes.md` text
        > more

        | File | Status | Note |
        |:-----|:------:|-----:|
        | `out/logo.png` | ok | a \\| b |
        | `gone.png` | missing |
        | **bold** | `~/` | x |

        ---

        ```swift
        let x = "`inside`"
        ```

        ```
        unterminated \(n)
        """
    }
    let messages = (0..<40).map(message) + [
        "", "plain", "\n\n\n", "## Heading ##", "***", "```", "| a | b |\n|---|---|", "`", "``unclosed", "- [ ] task\n- [x] done",
        "text with `~/Library/` and `\(work)/notes.md` and `\(work)`",
    ]

    func describe(_ blocks: [MarkdownText.Block]) -> String { String(describing: blocks) }

    func texts(_ blocks: [MarkdownText.Block]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .heading(_, let t), .paragraph(let t), .quote(let t): return [t]
            case .list(let items): return items.map(\.text)
            case .table(let header, let rows, _): return header + rows.flatMap { $0 }
            case .rule, .code: return []
            }
        }
    }

    // 1. Equivalence.
    let style = ReaderStyle.defaults
    var inlineCompared = 0
    var linked = 0
    for pass in 0..<2 {   // pass 0 is cold, pass 1 hits the caches
        for text in messages {
            let cached = MarkdownText.blocks(text)
            let plain = MarkdownText.parseBlocks(text)
            check(describe(cached) == describe(plain), "blocks differ (pass \(pass)) for: \(text.prefix(40))")
            let pathsCached = PathLinks.context(for: text, folder: work)
            let pathsPlain = PathLinks.context(for: text, folder: work, cached: false)
            check(pathsCached.bases == pathsPlain.bases, "bases differ for: \(text.prefix(40))")
            for run in texts(plain) {
                let a = MarkdownText.inline(run, style: style, paths: pathsCached)
                let b = MarkdownText.inline(run, style: style, paths: pathsPlain, cached: false)
                check(a == b, "inline differs for: \(run)")
                check(MarkdownText.inline(run, style: style, paths: nil) == MarkdownText.inline(run, style: style, paths: nil, cached: false), "inline (no paths) differs for: \(run)")
                inlineCompared += 1
                if a.runs.contains(where: { $0.link?.scheme == PathLinks.scheme }) { linked += 1 }
            }
        }
    }
    check(linked > 0, "no path links were produced, the corpus isn't exercising them")
    print("equivalence: \(messages.count) messages x 2 passes, \(inlineCompared) inline runs compared, \(linked) with path links")

    // Streaming: every prefix of a message parses the same cached or not.
    let streaming = message(7)
    var prefixes = 0
    var end = streaming.startIndex
    while end < streaming.endIndex {
        end = streaming.index(after: end)
        let prefix = String(streaming[..<end])
        check(describe(MarkdownText.blocks(prefix)) == describe(MarkdownText.parseBlocks(prefix)), "streaming prefix differs at \(prefixes)")
        prefixes += 1
    }
    print("streaming: \(prefixes) prefixes identical")

    // Path references through url(for:) agree, including relative, line-suffixed and missing.
    let codes = ["out/logo.png", "notes.md", "Package.swift:42", "Package.swift:42:7", "missing.txt", "record.items", "\(work)/out/", "~/", "./x", "out/final", " notes.md "]
    let cachedLinks = PathLinks.context(for: "`\(work)/out/`", folder: work)
    let plainLinks = PathLinks.context(for: "`\(work)/out/`", folder: work, cached: false)
    for code in codes {
        check(cachedLinks.url(for: code) == plainLinks.url(for: code), "url(for:) differs for \(code)")
    }
    check(cachedLinks.url(for: "out/logo.png") != nil, "existing file should link")
    check(cachedLinks.url(for: "missing.txt") == nil, "missing file should not link")

    // 2. The file memo: new files become links after the TTL, and it stays bounded.
    let probe = FileProbe(ttl: 0.2, limit: 10)
    let later = work + "/later.txt"
    check(!probe.lookup(later).exists, "later.txt should not exist yet")
    fm.createFile(atPath: later, contents: Data("x".utf8))
    check(!probe.lookup(later).exists, "memo should still say missing inside the TTL")
    Thread.sleep(forTimeInterval: 0.3)
    check(probe.lookup(later).exists, "memo should see the new file after the TTL")
    check(probe.lookup(work).isDirectory, "directory flag")
    for n in 0..<100 { _ = probe.lookup(work + "/n\(n)") }
    check(probe.lookup(later).exists, "lookups still right after the bound is hit")
    print("file memo: TTL and bound ok")

    // 3. Speed: ~40 messages, the way a chat switch renders them.
    func render(_ list: [String], cached: Bool) {
        for text in list {
            let paths = PathLinks.context(for: text, folder: work, cached: cached)
            let blocks = cached ? MarkdownText.blocks(text) : MarkdownText.parseBlocks(text)
            for run in texts(blocks) { _ = MarkdownText.inline(run, style: style, paths: paths, cached: cached) }
        }
    }
    func time(_ label: String, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        print("  \(label): \(String(format: "%.2f", ms)) ms")
        return ms
    }
    print("speed (40 messages per render):")
    let fresh = (1000..<1040).map(message)   // never seen by the equivalence pass
    let uncached = (0..<5).map { _ in time("uncached render") { render(fresh, cached: false) } }.reduce(0, +) / 5
    _ = time("cached render, cold (first sight)") { render(fresh, cached: true) }
    let warm = (0..<5).map { _ in time("cached render, warm") { render(fresh, cached: true) } }.reduce(0, +) / 5
    print(String(format: "  uncached avg %.2f ms, cached warm avg %.2f ms (%.1fx)", uncached, warm, uncached / max(warm, 0.001)))

    print(failures == 0 ? "PASS" : "FAILED: \(failures)")
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { run() }

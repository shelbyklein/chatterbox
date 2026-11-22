import AppKit
import SwiftUI

@MainActor
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    precondition(actual == expected, "FAIL: \(message) (got \(actual), expected \(expected))")
}

@MainActor
func runModelTests() {
    // 1. A2UI v0.8 JSONL parsing (beginRendering + surfaceUpdate + dataModelUpdate)
    let v08 = """
    {"beginRendering":{"surfaceId":"order","root":"root","title":"Coffee Order"}}
    {"surfaceUpdate":{"surfaceId":"order","components":[{"id":"root","component":{"Column":{"children":{"explicitList":["heading","size","qty","submit"]}}}},{"id":"heading","component":{"Text":{"text":{"literalString":"Configure Drink"},"usageHint":"h2"}}},{"id":"size","component":{"MultipleChoice":{"label":{"literalString":"Size"},"selections":{"path":"/order/size"},"maxAllowedSelections":1,"options":[{"label":{"literalString":"Small"},"value":"small"},{"label":{"literalString":"Large"},"value":"large"}]}}},{"id":"qty","component":{"Slider":{"label":{"literalString":"Cups"},"value":{"path":"/order/qty"},"minValue":1,"maxValue":5,"step":1}}},{"id":"submit","component":{"Button":{"child":"submitText","primary":true,"action":{"name":"submit_order","context":[{"key":"size","value":{"path":"/order/size"}},{"key":"quantity","value":{"path":"/order/qty"}}]}}}},{"id":"submitText","component":{"Text":{"text":{"literalString":"Place Order"}}}}]}}
    {"dataModelUpdate":{"surfaceId":"order","path":"/order","contents":[{"key":"size","valueArray":["large"]},{"key":"qty","valueNumber":2}]}}
    """

    let parsed08 = A2UIParser.parse(v08, closed: true)
    precondition(parsed08.isValid, "v0.8 surface should be valid")
    assertEqual(parsed08.validMessageCount, 3, "v0.8 message count")
    guard let s08 = parsed08.primarySurface else { fatalError("Missing v0.8 primary surface") }
    assertEqual(s08.rootId, "root", "v0.8 rootId")
    assertEqual(s08.title, "Coffee Order", "v0.8 title")
    assertEqual(s08.components.count, 6, "v0.8 component count")

    let store08 = A2UIDataStore(initialData: s08.initialData)
    assertEqual(store08.value(at: "/order/qty")?.intValue, 2, "v0.8 initial qty")
    assertEqual(store08.value(at: "/order/size")?.stringArrayValue, ["large"], "v0.8 initial size")

    // User edits qty, then streaming sync arrives -> user edit must be preserved!
    store08.setValue(.number(4), at: "/order/qty")
    store08.syncInitialData(s08.initialData)
    assertEqual(store08.value(at: "/order/qty")?.intValue, 4, "user edit preserved on sync")

    if case .button(_, _, _, let action) = s08.components["submit"]?.kind, let action {
        let msg = store08.formatActionMessage(action: action, buttonLabel: "Place Order")
        assertEqual(msg, "Place Order — Size: large, Quantity: 4", "formatted action message")
    } else {
        fatalError("Missing submit button action")
    }
    print("PASS v0.8 parsing, JSON pointer binding, and action formatting")

    // 2. A2UI v0.9 / v1.0 flat components + Swift Charts data extraction
    let v09 = """
    {"createSurface":{"surfaceId":"metrics","root":"root","title":"Sprint Velocity"}}
    {"updateComponents":{"surfaceId":"metrics","components":[{"id":"root","component":"Column","children":["chart1","tabs1"]},{"id":"chart1","component":"Chart","title":"Points by Sprint","chartType":"bar","data":{"path":"/metrics/sprints"},"xKey":"sprint","yKey":"points","seriesKey":"team"},{"id":"tabs1","component":"Tabs","tabItems":[{"title":"Trend","child":"line1"},{"title":"Split","child":"donut1"}]},{"id":"line1","component":"Chart","chartType":"line","data":{"path":"/metrics/sprints"},"xKey":"sprint","yKey":"points"},{"id":"donut1","component":"Chart","chartType":"donut","data":[{"label":"iOS","value":42},{"label":"Mac","value":58}]}]}}
    {"updateDataModel":{"surfaceId":"metrics","path":"/metrics","value":{"sprints":[{"sprint":"S1","points":24,"team":"Core"},{"sprint":"S2","points":31,"team":"Core"},{"sprint":"S2","points":18,"team":"Mobile"}]}}}
    """

    let parsed09 = A2UIParser.parse(v09, closed: true)
    precondition(parsed09.isValid, "v0.9 surface should be valid")
    guard let s09 = parsed09.primarySurface else { fatalError("Missing v0.9 surface") }
    let store09 = A2UIDataStore(initialData: s09.initialData)
    if case .chart(_, let type, let dataBinding, let xKey, let yKey, let seriesKey, _, _, _, _) = s09.components["chart1"]?.kind {
        assertEqual(type, .bar, "chart1 type")
        let points = A2UIChartDatum.extract(from: store09.resolve(dataBinding), xKey: xKey, yKey: yKey, seriesKey: seriesKey)
        assertEqual(points.count, 3, "chart1 point count")
        assertEqual(points[2].label, "S2", "chart1 label")
        assertEqual(points[2].value, 18, "chart1 value")
        assertEqual(points[2].series, "Mobile", "chart1 series")
    } else {
        fatalError("chart1 not parsed as Chart")
    }
    print("PASS v0.9 flat components and Swift Charts data extraction")

    // 3. Progressive streaming ignores incomplete trailing JSON line
    let streaming = """
    {"createSurface":{"surfaceId":"s","root":"root"}}
    {"updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":"Streaming live"}]}}
    {"updateDataModel":{"surfaceId":"s","path":"/incomp
    """
    let partial = A2UIParser.parse(streaming, closed: false)
    precondition(partial.isValid, "streaming partial A2UI should remain valid")
    precondition(partial.hasIncompleteTrailingLine, "should note incomplete trailing line")
    assertEqual(partial.primarySurface?.components.count, 1, "completed components parsed")
    print("PASS progressive streaming with partial trailing line")

    // 4. Relative pointer resolution inside list template items
    assertEqual(A2UIJSONPointer.resolvePath("title", basePath: "/items/2"), "/items/2/title", "relative path")
    assertEqual(A2UIJSONPointer.resolvePath("./price", basePath: "/items/2"), "/items/2/price", "dot-relative path")
    assertEqual(A2UIJSONPointer.resolvePath("/global/tax", basePath: "/items/2"), "/global/tax", "absolute path")

    // 5. Safety caps: max 200 components & deleteSurface & invalid JSON fallback
    var manyComponents: [[String: Any]] = []
    for i in 0..<250 {
        manyComponents.append(["id": "c\(i)", "component": "Text", "text": "Item \(i)"])
    }
    let payload: [String: Any] = ["root": "c0", "components": manyComponents]
    let bigData = try! JSONSerialization.data(withJSONObject: payload)
    let bigResult = A2UIParser.parse(String(data: bigData, encoding: .utf8)!, closed: true)
    assertEqual(bigResult.primarySurface?.components.count, A2UIParser.maxComponents, "component cap enforced")

    let deleted = A2UIParser.parse("""
    {"createSurface":{"surfaceId":"s","root":"root"}}
    {"updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":"Bye"}]}}
    {"deleteSurface":{"surfaceId":"s"}}
    """)
    precondition(!deleted.isValid, "deleted surface should not be renderable")

    let garbage = A2UIParser.parse("not json at all { broken")
    precondition(!garbage.isValid, "invalid JSON should fall back cleanly")
    print("PASS relative pointers, 200-component cap, deleteSurface, and invalid JSON fallback")

    // 6. SwiftUI layout & snapshot render test (including Swift Charts + cycle guard!)
    let cyclicJSON = """
    {"createSurface":{"surfaceId":"cyc","root":"a","title":"Cycle Guard"}}
    {"updateComponents":{"surfaceId":"cyc","components":[{"id":"a","component":"Column","children":["b","chart"]},{"id":"b","component":"Row","children":["a","txt"]},{"id":"txt","component":"Text","text":"Safe after cycle"},{"id":"chart","component":"Chart","chartType":"area","data":[{"label":"Mon","value":10},{"label":"Tue","value":22},{"label":"Wed","value":18}]}]}}
    """
    guard let cyclicSurface = A2UIParser.parse(cyclicJSON).primarySurface else {
        fatalError("Failed to parse cyclic surface")
    }
    let context = ReplyActionContext(state: .live, send: { _ in }, tint: .blue)
    let views: [AnyView] = [
        AnyView(A2UISurfaceView(source: v08, surface: s08, closed: true).environment(\.replyActions, context).frame(width: 520)),
        AnyView(A2UISurfaceView(source: v09, surface: s09, closed: true).environment(\.replyActions, context).frame(width: 520)),
        AnyView(A2UISurfaceView(source: cyclicJSON, surface: cyclicSurface, closed: true).environment(\.replyActions, context).frame(width: 520)),
    ]
    for (idx, view) in views.enumerated() {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage, cg.width > 100, cg.height > 40 else {
            fatalError("Failed to render SwiftUI A2UI surface #\(idx)")
        }
    }
    // Also confirm ReplyActions.containsInteractiveBlock detects both ```actions and ```a2ui
    precondition(ReplyActions.containsInteractiveBlock("Hi\n```a2ui\n{}\n```"), "detects ```a2ui")
    precondition(ReplyActions.containsInteractiveBlock("Hi\n```actions\nGo | go\n```"), "detects ```actions")
    precondition(!ReplyActions.containsInteractiveBlock("Plain reply"), "ignores plain reply")
    print("PASS SwiftUI rendering (v0.8 form, v0.9 Swift Charts, cycle guard) & replyActions detection")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    runModelTests()
}
print("ALL A2UI TESTS PASSED")

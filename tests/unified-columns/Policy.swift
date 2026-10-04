import Foundation
@main struct Check {
    static func main() {
        var cases = 0
        for w in stride(from: 300.0, through: 2400.0, by: 10) {
            for left in [false, true] { for right in [false, true] {
                for desired in [260.0, 620.0, 1400.0] {
                    let p = ChatColumnWidths(window: w, sidebarOpen: left, sidebarDesired: 420,
                        inspectorOpen: right, inspectorDesired: desired, inspectorMinimum: 260)
                    precondition(p.chat >= min(400, w))
                    precondition(p.sidebar >= 0 && p.inspector >= 0)
                    let total = p.sidebar + p.chat + p.inspector + (p.sidebar > 0 ? 6 : 0) + (p.inspector > 0 ? 6 : 0)
                    precondition(abs(total-w) < 0.01, "Allocated more than window")
                    precondition(p.inspector == 0 || p.inspectorX+p.inspector <= w+0.01)
                    cases += 1
                }
            }}
        }
        let wide = ChatColumnWidths(window: 1100, sidebarOpen: true, sidebarDesired: 260, inspectorOpen: true, inspectorDesired: 320, inspectorMinimum: 260)
        precondition(wide.sidebar == 260 && wide.inspector == 320 && wide.chat == 508)
        let narrow = ChatColumnWidths(window: 800, sidebarOpen: true, sidebarDesired: 260, inspectorOpen: true, inspectorDesired: 320, inspectorMinimum: 260)
        precondition(narrow.sidebar == 0 && narrow.inspector == 320 && narrow.chat == 474)
        let tiny = ChatColumnWidths(window: 640, sidebarOpen: true, sidebarDesired: 260, inspectorOpen: true, inspectorDesired: 320, inspectorMinimum: 260)
        precondition(tiny.sidebar == 0 && tiny.inspector == 0 && tiny.chat == 640 && tiny.inspectorOverlay)
        print("PASS \(cases) bounded allocations; chat minimum; sidebar collapse and inspector overlay")
    }
}

import Foundation
// The matcher's judgment: a clear fit, a named Studio, ambiguity and no fit.
func check(_ ok: Bool, _ what: String) { if !ok { print("FAIL: \(what)"); exit(1) }; print("PASS: \(what)") }
let archery = PlaceSuggestion.Place(id: UUID(), name: "USA Archery", instructions: "Website, print and marketing for USA Archery: banners, flyers, guides and the homepage.")
let playcase = PlaceSuggestion.Place(id: UUID(), name: "PlayCase Arcade", instructions: "The PlayCase Arcade iOS games, levels, App Store builds and TestFlight.")
let geekify = PlaceSuggestion.Place(id: UUID(), name: "Geekify", instructions: "Geekify store products, photos and Shopify listings.")
let all = [archery, playcase, geekify]
check(PlaceSuggestion.best(for: "Banner ideas for the USA Archery fall camp", among: all) == archery, "a named Studio")
check(PlaceSuggestion.best(for: "Can you redo the flyers and banners for the homepage?", among: all) == archery, "what belongs there, unnamed")
check(PlaceSuggestion.best(for: "Upload a new TestFlight build with the new levels", among: all) == playcase, "another Studio's work")
check(PlaceSuggestion.best(for: "What's the weather tomorrow?", among: all) == nil, "nothing fits: no suggestion")
check(PlaceSuggestion.best(for: "Photos for the banners", among: all) == nil, "a near tie: no suggestion")
check(PlaceSuggestion.best(for: "hello", among: []) == nil, "no Studios")

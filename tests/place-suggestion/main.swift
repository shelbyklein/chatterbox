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
// Projects are places too: their name and brief (the Desk proposes Studios and projects).
let dogear = PlaceSuggestion.Place(id: UUID(), name: "Dogear", instructions: "A reading app for iPhone: highlights, bookmarks and the book import.", kind: .project)
let chatterbox = PlaceSuggestion.Place(id: UUID(), name: "Chatterbox", instructions: "", kind: .project)
let mixed = all + [dogear, chatterbox]
check(PlaceSuggestion.best(for: "Fix the highlights sync, the bookmarks list and the book import", among: mixed) == dogear, "a project's brief")
check(PlaceSuggestion.best(for: "The Chatterbox sidebar jumps when a reply finishes", among: mixed) == chatterbox, "a project named, with no brief")
check(PlaceSuggestion.best(for: "Upload a new TestFlight build with the new levels", among: mixed) == playcase, "a Studio still wins its own work among projects")
check(PlaceSuggestion.best(for: "What's the weather tomorrow?", among: mixed) == nil, "nothing fits among projects either")
let twin = PlaceSuggestion.Place(id: UUID(), name: "Geekify", instructions: "The Geekify Shopify theme and store code.", kind: .project)
check(PlaceSuggestion.best(for: "Geekify listings", among: mixed + [twin]) == nil, "a Studio and project of the same name: no guess")
check(PlaceSuggestion.named("dogear", among: mixed) == dogear, "a place named in any case")
check(PlaceSuggestion.named("the USA Archery Studio", among: mixed) == archery, "a place named with \"the\" and \"Studio\" around it")
check(PlaceSuggestion.named("Geekify", among: mixed + [twin]) == nil, "two places of one name: neither")
check(PlaceSuggestion.named("Nowhere", among: mixed) == nil, "an unknown name")

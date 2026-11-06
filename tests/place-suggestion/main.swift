import Foundation
// The matcher's judgment: a place named (its name, a distinctive word of it, or a site its
// instructions name); ordinary words its instructions share don't count; ambiguity and no fit.
func check(_ ok: Bool, _ what: String) { if !ok { print("FAIL: \(what)"); exit(1) }; print("PASS: \(what)") }
let archery = PlaceSuggestion.Place(id: UUID(), name: "USA Archery", instructions: "Create website, print and marketing for USA Archery: banners, flyers, guides, images and versions. Use https://www.usarchery.org for official information. Generate in style, keep the case.")
let playcase = PlaceSuggestion.Place(id: UUID(), name: "PlayCase Arcade", instructions: "The PlayCase Arcade iOS games, levels, App Store builds and TestFlight.")
let geekify = PlaceSuggestion.Place(id: UUID(), name: "Geekify", instructions: "Geekify store products, photos and Shopify listings.")
let all = [archery, playcase, geekify]
check(PlaceSuggestion.best(for: "Banner ideas for the USA Archery fall camp", among: all) == archery, "a named Studio")
check(PlaceSuggestion.best(for: "Can you redo the flyers and banners for the homepage?", among: all) == nil, "words its instructions share, with no name: no guess")
check(PlaceSuggestion.best(for: "New levels for PlayCase, then a TestFlight build", among: all) == playcase, "a distinctive word of a Studio's name")
check(PlaceSuggestion.best(for: "Draft the archery camp email", among: all) == archery, "\u{201C}archery\u{201D} alone names USA Archery")
check(PlaceSuggestion.best(for: "What's on usarchery.org about the indoor nationals?", among: all) == archery, "a site its instructions name")
// Real chats it used to claim (Shelby, 2026-11-06): generic words its long instructions share.
for text in ["generate a stylistic, cartoonish camp cabin - more illustration than realism",
             "Look at the iPhone Duo basic case in c4d. What optimizations can you make? Keep the version",
             "Create a new icon and logo using the current image", "Ship a USA flag sticker"] {
    check(PlaceSuggestion.best(for: text, among: all) == nil, "no Studio for \u{201C}\(text.prefix(40))\u{2026}\u{201D}")
}
let product = PlaceSuggestion.Place(id: UUID(), name: "PlayCase Product", instructions: "")
check(PlaceSuggestion.best(for: "PlayCase lid magnets", among: all + [product]) == nil, "a word two Studios' names share: no guess")
check(PlaceSuggestion.best(for: "PlayCase Product lid magnets", among: all + [product]) == product, "the whole name settles it")
check(PlaceSuggestion.best(for: "What's the weather tomorrow?", among: all) == nil, "nothing fits: no suggestion")
check(PlaceSuggestion.best(for: "Photos for the banners", among: all) == nil, "a near tie: no suggestion")
check(PlaceSuggestion.best(for: "hello", among: []) == nil, "no Studios")
// Projects are places too: their name and brief (the Desk proposes Studios and projects).
let dogear = PlaceSuggestion.Place(id: UUID(), name: "Dogear", instructions: "A reading app for iPhone: highlights, bookmarks and the book import.", kind: .project)
let chatterbox = PlaceSuggestion.Place(id: UUID(), name: "Chatterbox", instructions: "", kind: .project)
let mixed = all + [dogear, chatterbox]
check(PlaceSuggestion.best(for: "Fix the highlights sync, the bookmarks list and the book import", among: mixed) == nil, "a project's brief words alone: no guess")
check(PlaceSuggestion.best(for: "Fix the Dogear highlights sync", among: mixed) == dogear, "a project named")
check(PlaceSuggestion.best(for: "The Chatterbox sidebar jumps when a reply finishes", among: mixed) == chatterbox, "a project named, with no brief")
check(PlaceSuggestion.best(for: "Upload a PlayCase TestFlight build", among: mixed) == playcase, "a Studio still wins when named among projects")
check(PlaceSuggestion.best(for: "What's the weather tomorrow?", among: mixed) == nil, "nothing fits among projects either")
let twin = PlaceSuggestion.Place(id: UUID(), name: "Geekify", instructions: "The Geekify Shopify theme and store code.", kind: .project)
check(PlaceSuggestion.best(for: "Geekify listings", among: mixed + [twin]) == nil, "a Studio and project of the same name: no guess")
check(PlaceSuggestion.named("dogear", among: mixed) == dogear, "a place named in any case")
check(PlaceSuggestion.named("the USA Archery Studio", among: mixed) == archery, "a place named with \"the\" and \"Studio\" around it")
check(PlaceSuggestion.named("Geekify", among: mixed + [twin]) == nil, "two places of one name: neither")
check(PlaceSuggestion.named("Nowhere", among: mixed) == nil, "an unknown name")

check(PlaceSuggestion.best(for: "Update the USAA camp email", among: all) == archery, "a recognizable organization abbreviation")
check(PlaceSuggestion.best(for: "Compare PlayCase Arcade and Geekify", among: all) == nil, "two explicit names do not favor the longer one")
check(PlaceSuggestion.best(for: "Compare archery with PlayCase levels", among: all) == nil, "two different own-term matches: no guess")
let generic = PlaceSuggestion.Place(id: UUID(), name: "Creative Studio", instructions: "Create art and images.")
check(PlaceSuggestion.best(for: "I need creative ideas", among: all + [generic]) == nil, "a generic name is not identity evidence")
check(PlaceSuggestion.best(for: "The Github image example", among: [PlaceSuggestion.Place(id: UUID(), name: "USA Archery", instructions: "See https://github.com/example and https://www.usarchery.org")]) == nil, "shared infrastructure sites do not identify the Studio")
check(PlaceSuggestion.best(for: "A Geekify redesign", among: [PlaceSuggestion.Place(id: UUID(), name: "Geekify", instructions: "")])?.name == "Geekify", "a named Studio needs no instructions")

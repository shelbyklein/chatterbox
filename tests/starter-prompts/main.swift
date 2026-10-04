import Foundation
for backend in Backend.allCases {
    let project=StarterPrompts.suggestions(project:"Galley",studio:nil,backend:backend)
    precondition(project.count==3 && project.allSatisfy {$0.contains("Galley")})
    let studio=StarterPrompts.suggestions(project:nil,studio:"USA Archery",backend:backend)
    precondition(studio.count==3 && studio.allSatisfy {$0.contains("USA Archery")})
    precondition(studio[0].contains("design.md"))
    let combined=StarterPrompts.suggestions(project:"Website",studio:"Geekify",backend:backend)
    precondition(combined.allSatisfy {$0.contains("Website") && $0.contains("Geekify")})
    precondition(StarterPrompts.suggestions(project:"  ",studio:"  ",backend:backend)==StarterPrompts.suggestions(project:nil,studio:nil,backend:backend))
}
print("PASS: named project, Studio, combined context and unbound fallback for Claude/Codex")

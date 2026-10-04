import SwiftUI

@main struct Checks {
    @MainActor static func main() async throws {
        let a=UUID(), b=UUID(), c=UUID()
        let s=ChatSwitchTransition()
        await s.show(a,reduceMotion:false)
        precondition(s.displayedID==a && !s.switching && s.opacity==1)
        let first=Task { await s.show(b,reduceMotion:false) }
        try await Task.sleep(for:.milliseconds(40))
        precondition(s.displayedID==a && s.opacity==0 && s.offset<0 && s.switching)
        first.cancel()
        let second=Task {await s.show(c,reduceMotion:false,waitForMount:true)}
        try await Task.sleep(for:.milliseconds(180))
        precondition(s.displayedID==c && s.opacity==0 && s.offset>0 && s.switching)
        s.didMount(c)
        await second.value
        await first.value
        precondition(s.displayedID==c && s.opacity==1 && s.offset==0 && !s.switching)
        // Cancel during hidden new-view staging by returning to that same selection.
        let third=Task {await s.show(b,reduceMotion:false,waitForMount:true)}
        try await Task.sleep(for:.milliseconds(180))
        third.cancel()
        await s.show(b,reduceMotion:false)
        await third.value
        precondition(s.displayedID==b && s.opacity==1 && !s.switching)
        // Leaving chat for Settings/web/mini bypasses staged presentation.
        let fourth=Task {await s.show(a,reduceMotion:false)}
        try await Task.sleep(for:.milliseconds(30))
        fourth.cancel()
        await s.show(nil,reduceMotion:false)
        await fourth.value
        precondition(s.displayedID==nil && s.opacity==1 && !s.switching)
        await s.show(c,reduceMotion:true)
        let reduced=Task {await s.show(a,reduceMotion:true)}
        for _ in 0..<24 {
            try await Task.sleep(for:.milliseconds(30))
            precondition(s.offset==0,"Reduce Motion translated chat")
        }
        await reduced.value
        precondition(s.displayedID==a && s.opacity==1 && !s.switching)
        let mounted=Task {await s.show(b,reduceMotion:false,waitForMount:true)}
        try await Task.sleep(for:.milliseconds(650))
        precondition(s.displayedID==b && s.opacity==0 && s.switching,"Revealed before view mounted")
        let revealStart=Date()
        s.didMount(b)
        await mounted.value
        let revealDelay=Date().timeIntervalSince(revealStart)
        precondition(revealDelay<0.25,"Added pause or input lock after mounting: \(revealDelay)")
        print("Post-mount reveal and interaction: \(Int(revealDelay*1000))ms")
        precondition(s.opacity==1 && !s.switching)
        print("PASS delayed mounting; initial entry, hidden swap, rapid latest-wins cancellation, same-ID recovery, alternate detail, Reduce Motion")
    }
}

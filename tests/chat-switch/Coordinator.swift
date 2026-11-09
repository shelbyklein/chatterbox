import SwiftUI

// ChatSwitchTransition (Core/Chatterbox/Views/ChatSwitchTransition.swift) as it is since
// "Faster chat switching: no fade" (c36c9c9): the next chat replaces the current one at once,
// never faded or slid (a fade cost ~190 ms a switch); old and new are never mounted together;
// input waits only until the new chat has mounted. The latest switch always wins.
@main struct Checks {
    @MainActor static func main() async throws {
        let a=UUID(), b=UUID(), c=UUID()
        let s=ChatSwitchTransition()
        func settled(_ id: UUID?) -> Bool { s.displayedID==id && s.opacity==1 && s.offset==0 && !s.switching }

        // First show: straight in.
        await s.show(a,reduceMotion:false)
        precondition(settled(a),"initial show")

        // A switch without waiting for mount: replaced at once, no fade, no slide, nothing locked.
        await s.show(b,reduceMotion:false)
        precondition(settled(b),"immediate switch, no fade")

        // Waiting for mount: the new chat is displayed at once (opacity 1, no offset) but input is
        // locked until it mounts; mounting releases it promptly.
        let mount=Task { await s.show(c,reduceMotion:false,waitForMount:true) }
        try await Task.sleep(for:.milliseconds(40))
        precondition(s.displayedID==c && s.opacity==1 && s.offset==0 && s.switching,"shown at once, input locked until mounted")
        let revealStart=Date()
        s.didMount(c)
        await mount.value
        let revealDelay=Date().timeIntervalSince(revealStart)
        precondition(settled(c),"mounted: unlocked")
        precondition(revealDelay<0.25,"Added pause or input lock after mounting: \(revealDelay)")
        print("Post-mount unlock: \(Int(revealDelay*1000))ms")

        // Rapid switching: the latest wins; an earlier switch still waiting never takes over.
        let older=Task { await s.show(a,reduceMotion:false,waitForMount:true) }
        try await Task.sleep(for:.milliseconds(30))
        let newer=Task { await s.show(b,reduceMotion:false,waitForMount:true) }
        try await Task.sleep(for:.milliseconds(30))
        s.didMount(a)   // the older one mounting late changes nothing
        try await Task.sleep(for:.milliseconds(30))
        precondition(s.displayedID==b && s.switching,"latest wins; a stale mount doesn't unlock it")
        s.didMount(b)
        await newer.value
        await older.value
        precondition(settled(b),"latest mounted: settled")

        // Cancelled while waiting, then back to that same chat: recovers, unlocked.
        let cancelled=Task { await s.show(c,reduceMotion:false,waitForMount:true) }
        try await Task.sleep(for:.milliseconds(40))
        cancelled.cancel()
        await cancelled.value
        await s.show(c,reduceMotion:false)
        precondition(settled(c),"same-ID recovery after a cancelled switch")

        // Leaving chat (Settings, web, mini): no staging at all.
        let leaving=Task { await s.show(a,reduceMotion:false,waitForMount:true) }
        try await Task.sleep(for:.milliseconds(30))
        await s.show(nil,reduceMotion:false)
        await leaving.value
        precondition(settled(nil),"leaving chat clears at once")

        // Reduce Motion: never translated, before or after mounting.
        await s.show(c,reduceMotion:true)
        let reduced=Task { await s.show(a,reduceMotion:true,waitForMount:true) }
        for _ in 0..<10 {
            try await Task.sleep(for:.milliseconds(20))
            precondition(s.offset==0 && s.opacity==1,"Reduce Motion translated or faded chat")
        }
        s.didMount(a)
        await reduced.value
        precondition(settled(a),"Reduce Motion: settled")

        print("PASS immediate switch (no fade), mount-gated input, prompt unlock, latest-wins, same-ID recovery, leaving chat, Reduce Motion")
    }
}

import Foundation

// The idle-simulator sweep's decisions (Core/ChatterboxRuntime/SimulatorSweep.swift): which
// booted devices it would shut down, and which it leaves alone, without touching a simulator.

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL \(message)"); exit(1) }
    print("PASS \(message)")
}

let generic = SimulatorSweep.Device(udid: "4C455030-C77A-4B3B-96BF-6172C17BDFBF", name: "iPhone 17 Pro")
let stale = SimulatorSweep.Device(udid: "980F4C54-669D-48C3-B02C-0CC6C01ED556", name: "iPhone 17 Pro Max")
let building = SimulatorSweep.Device(udid: "C8A20145-F2AA-4CB4-B004-6C78F8B5ADEA", name: "Chatterbox home nav regression")
let ours = SimulatorSweep.Device(udid: "FA3E0000-0000-4000-8000-000000000001", name: "Chatterbox test iPhone 26.2")
let windowed = SimulatorSweep.Device(udid: "57D56E05-5888-4EA8-AFD9-86E9E7BC0623", name: "iPad Pro 13-inch (M5)")
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
var sweep = SimulatorSweep()

// First look: nothing has been idle long enough; the ones in use are kept for their reasons.
var decisions = sweep.evaluate(
    booted: [generic, stale, building, ours, windowed],
    processArguments: ["/usr/bin/xcodebuild -project X -destination platform=iOS Simulator,id=c8a20145-f2aa-4cb4-b004-6c78f8b5adea test", "bash scripts/test-x.sh"],
    simulatorAppPaths: ["/Users/shelby/Library/Developer/CoreSimulator/Devices/57D56E05-5888-4EA8-AFD9-86E9E7BC0623/data/var/run/launchd_bootstrap.plist"],
    registered: [ours.udid], now: t0)
func decision(_ device: SimulatorSweep.Device, in list: [SimulatorSweep.Decision]) -> SimulatorSweep.Decision { list.first { $0.device == device }! }
check(decisions.allSatisfy { $0.action == .keep }, "first look: nothing is shut down (nothing has been idle for 30 min yet)")
check(decision(building, in: decisions).reason == "a running process names it", "a device an xcodebuild targets is kept (UDID matched whatever its case)")
check(decision(ours, in: decisions).reason == "a Chatterbox test run has it on record as in use", "a device a Chatterbox test registered is kept")
check(decision(windowed, in: decisions).reason == "open in Simulator.app", "a device open in a Simulator window is kept")
check(decision(generic, in: decisions).reason == "unused for 0 min, under the 30 min idle time", "an unused device starts its idle clock")
check(sweep.firstSeenIdle.keys.sorted() == [generic.udid, stale.udid].sorted(), "idle clocks run only for the unused devices")

// 20 minutes on: still under the idle time.
decisions = sweep.evaluate(booted: [generic, stale, building, ours, windowed], processArguments: [], simulatorAppPaths: [], registered: [ours.udid], now: t0 + 20 * 60)
check(decisions.allSatisfy { $0.action == .keep }, "20 min on: still nothing shut down")
check(decision(building, in: decisions).reason == "unused for 0 min, under the 30 min idle time", "the build finished: that device's idle clock starts now")

// 31 minutes on: the two generics go; the one whose build just ended stays; ours stays.
decisions = sweep.evaluate(booted: [generic, stale, building, ours], processArguments: [], simulatorAppPaths: [], registered: [ours.udid], now: t0 + 31 * 60)
let shut = decisions.filter { $0.action == .shutDown }.map(\.device)
check(Set(shut) == [generic, stale], "31 min on: the two unused generics are shut down, nothing else")
check(decision(generic, in: decisions).reason == "booted but nothing has used it for 31 min; shut down to free its memory and processes", "the reason names the idle time")
check(decision(ours, in: decisions).action == .keep, "the registered test device is never shut down, however long it sits")
check(sweep.firstSeenIdle[generic.udid] == nil && sweep.firstSeenIdle[stale.udid] == nil, "a shutdown clears the device's idle clock")

// A device used again mid-way starts over; one that's no longer booted is forgotten.
decisions = sweep.evaluate(booted: [building], processArguments: ["xcrun simctl launch C8A20145-F2AA-4CB4-B004-6C78F8B5ADEA com.example"], simulatorAppPaths: [], registered: [], now: t0 + 45 * 60)
check(decision(building, in: decisions).action == .keep && sweep.firstSeenIdle[building.udid] == nil, "used again: kept, and its idle clock is cleared")
decisions = sweep.evaluate(booted: [building], processArguments: [], simulatorAppPaths: [], registered: [], now: t0 + 46 * 60)
decisions = sweep.evaluate(booted: [building], processArguments: [], simulatorAppPaths: [], registered: [], now: t0 + 75 * 60)
check(decision(building, in: decisions).action == .keep, "after being used, a device needs another 30 idle minutes (29 so far)")
decisions = sweep.evaluate(booted: [building], processArguments: [], simulatorAppPaths: [], registered: [], now: t0 + 76 * 60)
check(decision(building, in: decisions).action == .shutDown, "and then it's shut down (30 min idle)")
check(sweep.firstSeenIdle.isEmpty, "nothing booted and unused is left on the clock")

// Under pressure (MacPressure, through SimulatorSweeper.pressureChanged): Busy waits 5 minutes,
// Overloaded none; a device a running build or test names, one open in Simulator.app, and one a
// test run has on record are still kept.
check(SimulatorSweep.idleAfter(pressure: "ok") == 30 * 60 && SimulatorSweep.idleAfter(pressure: "busy") == 5 * 60
      && SimulatorSweep.idleAfter(pressure: "overloaded") == 0, "idle times: 30 min at OK, 5 at Busy, none when Overloaded")
var busy = SimulatorSweep(); busy.idleAfter = SimulatorSweep.idleAfter(pressure: "busy")
let p0 = t0 + 100 * 60
decisions = busy.evaluate(booted: [generic, stale], processArguments: [], simulatorAppPaths: [], registered: [], now: p0)
check(decisions.allSatisfy { $0.action == .keep }, "Busy: first seen unused, kept for now")
decisions = busy.evaluate(booted: [generic, stale], processArguments: [], simulatorAppPaths: [], registered: [], now: p0 + 5 * 60)
check(decisions.allSatisfy { $0.action == .shutDown }, "Busy: unused for 5 min, shut down")
var overloaded = SimulatorSweep(); overloaded.idleAfter = SimulatorSweep.idleAfter(pressure: "overloaded")
let open = "/Users/x/Library/Developer/CoreSimulator/Devices/\(stale.udid)/data/foo"
decisions = overloaded.evaluate(booted: [generic, stale, building, ours],
                                processArguments: ["/usr/bin/xcodebuild test -destination platform=iOS Simulator,id=\(building.udid)"],
                                simulatorAppPaths: [open], registered: [ours.udid], now: p0)
check(decision(generic, in: decisions).action == .shutDown && decision(generic, in: decisions).reason.contains("0 min"),
      "Overloaded: an unused device is shut down at the first look, no idle wait")
check(decision(building, in: decisions).action == .keep, "Overloaded: the device a running xcodebuild targets is kept")
check(decision(ours, in: decisions).action == .keep, "Overloaded: a device a running test registered is never shut down")
check(decision(stale, in: decisions).action == .keep, "Overloaded: one open in a Simulator window (maybe yours) is kept")

// simctl's JSON: only booted devices, by name.
let json = """
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"udid":"A","name":"iPhone 17 Pro","state":"Booted"},{"udid":"B","name":"iPhone Air","state":"Shutdown"}],
"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"C","name":"Chatterbox home nav regression","state":"Booted"}]}}
"""
let parsed = SimulatorSweep.devices(fromSimctlJSON: Data(json.utf8))
check(parsed == [SimulatorSweep.Device(udid: "C", name: "Chatterbox home nav regression"), SimulatorSweep.Device(udid: "A", name: "iPhone 17 Pro")], "simctl's JSON gives the booted devices, by name")
check(SimulatorSweep.devices(fromSimctlJSON: Data("not json".utf8)).isEmpty, "unreadable output means no devices, not a crash")
// Who may act for the Mac: the LaunchAgents pass the flavor's own data folder, tests a /tmp one.
let own = "/Users/x/Library/Application Support/Chatterbox"
check(SimulatorSweep.isInstalledService(dataDir: nil, ownDataDirectory: own), "no data folder given: the installed service")
check(SimulatorSweep.isInstalledService(dataDir: own, ownDataDirectory: own), "its own data folder, as the LaunchAgent passes it: the installed service")
check(SimulatorSweep.isInstalledService(dataDir: own + "/", ownDataDirectory: own), "a trailing slash is the same folder")
check(!SimulatorSweep.isInstalledService(dataDir: "/tmp/chatterbox-test-desk.abc", ownDataDirectory: own), "a test's /tmp folder never acts")
check(!SimulatorSweep.isInstalledService(dataDir: own + " Dev", ownDataDirectory: own), "another flavor's folder isn't this one's")
print("All simulator sweep checks passed.")

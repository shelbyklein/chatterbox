import Foundation

// Chatterbox's identities, real and Dev (Core/Shared/Flavor.swift). The real values are the
// ones Chatterbox used before Dev existed: changing one would move the real app's data, ports,
// pairings or Keychain items. scripts/test-flavor.sh builds this twice, plain and with
// -D CHATTERBOX_DEV, and the expected flavor comes in as the first argument.

var failures = 0
func expect<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
    if actual != expected { failures += 1; print("FAIL \(what): \(actual) != \(expected)") }
}

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
let real = Flavor.real, dev = Flavor.dev

// The real app: exactly as before.
expect(real.appName, "Chatterbox", "real app name")
expect(real.appBundleID, "com.shelbyklein.Chatterbox", "real app id")
expect(real.hostBundleID, "com.shelbyklein.Chatterbox.Host", "real host id")
expect(real.daemonBundleID, "com.shelbyklein.Chatterbox.Daemon", "real service id")
expect(real.mobileBundleID, "com.shelbyklein.Chatterbox.mobile", "real phone app id")
expect(real.daemonName, "chatterboxd", "real service name")
expect(real.serviceLabel, "com.shelbyklein.chatterboxd", "real LaunchAgent")
expect(real.keychainPrefix + ".secrets", "com.shelbyklein.Chatterbox.secrets", "real secrets Keychain service")
expect(real.keychainPrefix + ".apns.app", "com.shelbyklein.Chatterbox.apns.app", "real APNs Keychain service")
expect(real.keychainPrefix + ".apns", "com.shelbyklein.Chatterbox.apns", "real old APNs Keychain service")
expect(real.keychainPrefix + ".mobile", "com.shelbyklein.Chatterbox.mobile", "real phone Keychain service")
expect(real.keychainPrefix + ".macscreen", "com.shelbyklein.Chatterbox.macscreen", "real Mac Screen Keychain service")
expect(real.urlScheme, "chatterbox", "real URL scheme")
expect(real.appGroup, "group.com.shelbyklein.Chatterbox", "real app group")
expect(real.dataDirectory.path, support.appendingPathComponent("Chatterbox").path, "real data folder")
expect(real.hostDirectory.path, support.appendingPathComponent("Chatterbox/Host").path, "real host folder")
expect(real.studiosDirectory.path, home.appendingPathComponent("Chatterbox/Studios").path, "real Studios")
expect(real.pcMirrorDirectory.path, home.appendingPathComponent("Chatterbox/PC").path, "real PC copies")
expect(real.servicePreferencesSuite, nil, "real service preferences (its standard domain)")
expect(real.companionPort, 47_321, "real phone port")
expect(real.bonjourType, "_chatterbox._tcp", "real Bonjour type")
expect(real.connectorPort, 47_331, "real connector port")
expect(real.connectorPublicURL, "https://chatterbox-mcp.shelbyklein.com", "real connector URL")
expect(real.pcTunnelPort, 47_340, "real PC tunnel")
expect(real.pcCodexPort, 47_390, "real PC Codex port")
expect(real.pcClaudeBasePort, 47_400, "real PC Claude ports")
expect(real.signpostSubsystem, "com.shelbyklein.Chatterbox", "real signposts")
expect(real.ownsCrashReport(named: "Chatterbox-2026-11-04-120000.ips"), true, "real app crash")
expect(real.ownsCrashReport(named: "ChatterboxHost-2026-11-04-120000.ips"), true, "real host crash")
expect(real.ownsCrashReport(named: "Chatterbox Dev-2026-11-04-120000.ips"), false, "Dev crash isn't real's")
expect(Flavor.teamID, "9F3MKVW9C5", "team")

// Dev: every one of them different.
expect(dev.appName, "Chatterbox Dev", "Dev app name")
expect(dev.appBundleID, "com.shelbyklein.Chatterbox.dev", "Dev app id")
expect(dev.hostBundleID, "com.shelbyklein.Chatterbox.dev.Host", "Dev host id")
expect(dev.daemonBundleID, "com.shelbyklein.Chatterbox.dev.Daemon", "Dev service id")
expect(dev.mobileBundleID, "com.shelbyklein.Chatterbox.mobile.dev", "Dev phone app id")
expect(dev.daemonName, "chatterboxd-dev", "Dev service name")
expect(dev.serviceLabel, "com.shelbyklein.chatterboxd.dev", "Dev LaunchAgent")
expect(dev.keychainPrefix, "com.shelbyklein.Chatterbox.dev", "Dev Keychain prefix")
expect(dev.urlScheme, "chatterbox-dev", "Dev URL scheme")
expect(dev.appGroup, nil, "Dev has no app group")
expect(dev.dataDirectory.path, support.appendingPathComponent("Chatterbox Dev").path, "Dev data folder")
expect(dev.hostDirectory.path, support.appendingPathComponent("Chatterbox Dev/Host").path, "Dev host folder")
expect(dev.studiosDirectory.path, home.appendingPathComponent("Chatterbox Dev/Studios").path, "Dev Studios")
expect(dev.servicePreferencesSuite, "com.shelbyklein.chatterboxd.dev", "Dev service preferences")
expect(dev.companionPort, 47_421, "Dev phone port")
expect(dev.bonjourType, "_chatterbox-dev._tcp", "Dev Bonjour type")
expect(dev.connectorPort, 47_431, "Dev connector port")
expect(dev.connectorPublicURL.hasPrefix("http://127.0.0.1:"), true, "Dev connector is local only")
expect(dev.ownsCrashReport(named: "Chatterbox Dev-2026-11-04-120000.ips"), true, "Dev app crash")
expect(dev.ownsCrashReport(named: "Chatterbox-2026-11-04-120000.ips"), false, "real crash isn't Dev's")
let devPorts: [Int] = [Int(dev.companionPort), Int(dev.connectorPort), dev.pcTunnelPort, dev.pcCodexPort]
let realPorts: [Int] = [Int(real.companionPort), Int(real.connectorPort), real.pcTunnelPort, real.pcCodexPort]
expect(Set(devPorts).isDisjoint(with: realPorts), true, "Dev ports are its own")
expect((dev.pcClaudeBasePort..<dev.pcClaudeBasePort + 500).overlaps(real.pcClaudeBasePort..<real.pcClaudeBasePort + 500), false, "Dev PC ports are its own")
expect((dev.pcClaudeBasePort..<dev.pcClaudeBasePort + 500).contains(dev.pcCodexPort), false, "Dev PC Codex port")

// What this build is, and the values the rest of Chatterbox reads from it.
let want = CommandLine.arguments.dropFirst().first ?? "real"
expect(Flavor.current.rawValue, want, "compiled flavor")
let current = Flavor.current
expect(Companion.port, current.companionPort, "Companion.port")
expect(Companion.serviceType, current.bonjourType, "Companion.serviceType")
if ProcessInfo.processInfo.environment["CHATTERBOX_HOST_DIR"] == nil {
    expect(HostPaths.directory.path, current.hostDirectory.path, "HostPaths.directory")
}
if ProcessInfo.processInfo.environment["CHATTERBOX_PREFERENCES_SUITE"] == nil {
    // The service's preferences: the real one's standard domain, Dev's own suite.
    expect(AppPreferences.defaults === UserDefaults.standard, !current.isDev, "service preferences domain")
}

if failures > 0 { print("\(failures) failed"); exit(1) }
print("Flavor (\(want)): all identities check out.")

import AppKit
import Foundation
import RoyalVNCKit

// Connects to this Mac's Screen Sharing, signs in, and saves the first frame as a PNG.
// The password comes from a hidden-text dialog and stays in memory.
setvbuf(stdout, nil, _IOLBF, 0)   // Each line reaches the log as it happens.
let output = CommandLine.arguments.dropFirst().first ?? "/tmp/vnc-spike.png"

final class Spike: NSObject, VNCConnectionDelegate {
    var connection: VNCConnection?
    var saved = false
    var sawAuth: String = "none"
    /// Kept in memory only, so a retry doesn't ask again (RoyalVNC issue #42 fails ~1% of handshakes).
    var password: String?
    var attempts = 0

    func start() {
        let settings = VNCConnection.Settings(isDebugLoggingEnabled: false, hostname: "127.0.0.1", port: 5900, isShared: true,
                                              isScalingEnabled: false, useDisplayLink: false, inputMode: .none,
                                              isClipboardRedirectionEnabled: false, colorDepth: .depth24Bit, frameEncodings: .default)
        attempts += 1
        let connection = VNCConnection(settings: settings)
        connection.delegate = self
        self.connection = connection
        connection.connect()
    }

    func connection(_ connection: VNCConnection, stateDidChange state: VNCConnection.ConnectionState) {
        print("state: \(state.status)" + (state.error.map { " (\($0))" } ?? ""))
        guard state.status == .disconnected else { return }
        if !saved, password != nil, attempts < 3 {
            print("retrying with the same password (attempt \(attempts + 1) of 3)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.start() }
            return
        }
        print(saved ? "done" : "failed after \(attempts) attempt(s)")
        exit(saved ? 0 : 1)
    }

    func connection(_ connection: VNCConnection, credentialFor type: VNCAuthenticationType, completion: @escaping (VNCCredential?) -> Void) {
        sawAuth = "\(type)"
        print("auth: \(type) (username: \(type.requiresUsername), password: \(type.requiresPassword))")
        guard let password = password ?? Spike.askPassword() else { completion(nil); return }
        self.password = password
        // From here on it should be quick; waiting for the person to type isn't counted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("timed out after signing in"); exit(2) }
        completion(type.requiresUsername ? VNCUsernamePasswordCredential(username: NSUserName(), password: password)
                                         : VNCPasswordCredential(password: password))
    }

    /// A dialog on the Mac's screen; the answer goes straight back to this process.
    static func askPassword() -> String? {
        let script = """
        display dialog "Chatterbox's Mac Screen check: your Mac password for \(NSUserName()), to sign in to Screen Sharing. It isn't saved." default answer "" with hidden answer with title "Chatterbox" buttons {"Cancel", "Sign In"} default button "Sign In"
        text returned of result
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe(); process.standardOutput = pipe
        try? process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return String(text.dropLast(text.hasSuffix("\n") ? 1 : 0))
    }

    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        print("framebuffer: \(framebuffer.size.width)x\(framebuffer.size.height)")
    }
    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {}
    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer, x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        guard !saved, let image = framebuffer.cgImage else { return }
        saved = true
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
        print("saved \(image.width)x\(image.height) to \(output)")
        connection.disconnect()
    }
    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {}
}

// Ask first: Screen Sharing hangs up if the sign-in takes minutes to arrive.
let spike = Spike()
guard let password = Spike.askPassword() else { print("cancelled"); exit(1) }
spike.password = password
spike.start()
RunLoop.main.run()

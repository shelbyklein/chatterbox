// swift-tools-version: 6.0
// T1 of plans/mobile-remote-desktop.md: can RoyalVNCKit sign in to this Mac's Screen Sharing
// and get a frame? Run with scripts/test-vnc-spike.sh.
import PackageDescription

let package = Package(
    name: "vnc-spike",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/royalapplications/royalvnc.git", revision: "92d4427c73817d8f849bb289ff190aa4b40c44ea")], // 1.1.0, pinned by commit (it depends on a CryptoSwift branch)
    targets: [.executableTarget(name: "vnc-spike", dependencies: [.product(name: "RoyalVNCKit", package: "royalvnc")],
                                swiftSettings: [.swiftLanguageMode(.v5)])]
)

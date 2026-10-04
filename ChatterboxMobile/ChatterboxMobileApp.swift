import SwiftUI

#if !GOLEM_APP
@main
struct ChatterboxMobileApp: App {
    @UIApplicationDelegateAdaptor(MobilePushAppDelegate.self) private var delegate
    @State private var store = MobileStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isPaired {
                    ChatListView(hidesAssistant:true)
                } else {
                    ConnectView()
                }
            }
            .environment(store).defaultAppStorage(AppPreferences.defaults)
            // Replies read like on the Mac, at a phone's size.
            .environment(\.readerStyle, .mobile)
            .onOpenURL { url in
                guard url.scheme == "chatterbox", url.host == "chat",
                      let id = UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { return }
                MobilePushNotifications.shared.pendingChat = id
            }
            #if DEBUG
            .task { await CompanionTransportProbe.runIfRequested() }
            .task {
                // Simulator tests: pair from the environment instead of typing.
                let env = ProcessInfo.processInfo.environment
                if !store.isPaired, let host = env["CHATTERBOX_TEST_HOST"], let code = env["CHATTERBOX_TEST_CODE"] {
                    try? await store.pair(host: host, code: code)
                }
            }
            #endif
        }
    }
}

#endif

extension ReaderStyle {
    static var mobile: ReaderStyle {
        var style = ReaderStyle.defaults
        style.textSize = 17
        style.codeSize = 14
        style.lineSpacing = 3
        style.paragraphSpacing = 12
        style.contentWidth = 10_000
        return style
    }
}

/// Pairing: find the Mac on this Wi-Fi (or type its Tailscale address), then enter the
/// code from Chatterbox → Settings → iPhone.
struct ConnectView: View {
    @Environment(MobileStore.self) private var store
    @State private var finder = MacFinder()
    @State private var address = ""
    @State private var chosen: MacFinder.Found?
    @State private var code = ""
    @State private var pairing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if finder.found.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for Chatterbox on this Wi-Fi\u{2026}").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(finder.found) { mac in
                        Button {
                            chosen = mac
                            address = ""
                        } label: {
                            HStack {
                                Label(mac.name, systemImage: "desktopcomputer")
                                Spacer()
                                if chosen == mac { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("On this Wi-Fi")
                } footer: {
                    Text("Turn on Chatterbox → Settings → iPhone on your Mac.")
                }

                Section {
                    TextField("100.x.y.z", text: $address)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: address) { _, text in if !text.isEmpty { chosen = nil } }
                } header: {
                    Text("Or its address")
                } footer: {
                    Text("Away from home, use the Mac's Tailscale address, shown in the same Settings tab.")
                }

                Section("Pairing code") {
                    TextField("123 456", text: $code)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack {
                            Spacer()
                            if pairing { ProgressView() } else { Text("Pair").bold() }
                            Spacer()
                        }
                    }
                    .disabled(pairing || digits.count != 6 || (chosen == nil && address.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .navigationTitle("Connect to Your Mac")
            .onAppear { finder.start() }
            .onDisappear { finder.stop() }
        }
    }

    private var digits: String { code.filter(\.isNumber) }

    private func pair() async {
        pairing = true
        error = nil
        defer { pairing = false }
        var host = address.trimmingCharacters(in: .whitespaces)
        if let chosen {
            guard let found = await finder.address(of: chosen) else {
                error = "Couldn't reach \(chosen.name). Try its address instead."
                return
            }
            host = found
        }
        do {
            try await store.pair(host: host, code: digits)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

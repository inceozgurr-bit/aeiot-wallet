import SwiftUI
import UIKit

@main
struct AEIOTWalletApp: App {
    @State private var wallet = WalletStore()
    @State private var addressBook = AddressBook()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("themeMode") private var themeMode = ThemeMode.light
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.deviceDefault
    @AppStorage("requireBiometricUnlock") private var requireBiometricUnlock = true
    /// Checked once at launch: a jailbroken device weakens Keychain protection.
    @State private var showIntegrityWarning = DeviceIntegrity.isCompromised
    /// iOS dismisses its launch screen the moment the app is ready, which is
    /// too fast to register. This holds the same image a little longer.
    @State private var showSplash = true
    @State private var walletConnect = WalletConnectService.shared

    init() {
        // Before any view reads a string, so the first frame is already translated.
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        Localization.apply(AppLanguage(rawValue: stored) ?? .deviceDefault)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if wallet.wallets.isEmpty {
                    OnboardingView()
                } else if wallet.isLocked {
                    LockView()
                } else {
                    HomeView()
                }
            }
            // Rebuilds the tree so already-rendered strings pick up the new language.
            .id(appLanguage)
            .environment(wallet)
            .environment(addressBook)
            .environment(\.locale, Locale(identifier: appLanguage.bundleCode))
            // The chosen language overrides the device one, so iOS will not flip
            // the layout for Arabic on its own.
            .environment(\.layoutDirection, appLanguage.layoutDirection)
            .tint(.appAccent)
            .overlay {
                if showSplash {
                    ZStack {
                        Color.black
                        Image("LaunchLogo")
                    }
                    // The whole stack, not just the background: inside the safe
                    // area the mark sits below the true centre, and iOS centres
                    // the launch screen's copy on the full screen — so the logo
                    // visibly jumped as one replaced the other.
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .task {
                // Dapp requests can arrive at any time, so the relay starts with
                // the app rather than when the connections screen is opened.
                walletConnect.start()
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
            }
            .onOpenURL { url in
                Task { await walletConnect.pair(url.absoluteString) }
            }
            // Presented from the root so a dapp reaches the user on any screen —
            // but never over the lock screen, where approving a connection would
            // expose the address and open a lasting session with no check at all.
            .sheet(isPresented: .init(get: { walletConnect.proposal != nil && !wallet.isLocked },
                                      set: { if !$0 { walletConnect.proposal = nil } })) {
                if let proposal = walletConnect.proposal {
                    ConnectionRequestSheet(pending: proposal)
                }
            }
            .sheet(isPresented: .init(get: { walletConnect.request != nil && !wallet.isLocked },
                                      set: { if !$0 { walletConnect.request = nil } })) {
                if let request = walletConnect.request {
                    SignatureRequestSheet(pending: request)
                }
            }
            .alert("This device looks jailbroken", isPresented: $showIntegrityWarning) {
                Button("I understand", role: .cancel) {}
            } message: {
                Text("On a jailbroken device other apps may be able to reach your recovery phrase. Use a stock device for real funds.")
            }
            .onChange(of: themeMode, initial: true) { _, mode in
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .forEach { $0.overrideUserInterfaceStyle = mode.uiStyle }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && !wallet.wallets.isEmpty && requireBiometricUnlock {
                    wallet.isLocked = true
                }
            }
        }
    }
}

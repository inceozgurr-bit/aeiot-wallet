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
            .tint(.appAccent)
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

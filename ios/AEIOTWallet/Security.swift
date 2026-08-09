import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Watches for screen recording and screenshots while secrets are on screen.
/// iOS cannot block a screenshot outright, but it can tell us one happened and
/// it can tell us a recording is running — the latter is the real risk, since a
/// recording captures the phrase without the user noticing.
@Observable @MainActor
final class ScreenGuard {
    private(set) var isRecording = UIScreen.main.isCaptured
    private(set) var screenshotTaken = false

    /// deinit runs outside the main actor, so this has to be reachable from there.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isRecording = UIScreen.main.isCaptured }
        })
        observers.append(center.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenshotTaken = true }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

enum SecurePasteboard {
    /// Copies with an expiry so an address or recovery phrase does not sit in
    /// the pasteboard for other apps to read hours later.
    /// Local only: without it the pasteboard syncs through Universal Clipboard,
    /// which would put a recovery phrase on every Mac and iPad signed into the
    /// same Apple ID — and the expiry does not stop that, the sync is immediate.
    static func copy(_ text: String, expiresIn seconds: TimeInterval = 60) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: text]],
            options: [.expirationDate: Date().addingTimeInterval(seconds),
                      .localOnly: true]
        )
    }
}

enum DeviceIntegrity {
    /// Best-effort jailbreak check. Any single signal can be defeated, so this
    /// warns the user rather than blocking the app outright.
    static var isCompromised: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/usr/sbin/sshd",
            "/bin/bash",
        ]
        if suspiciousPaths.contains(where: FileManager.default.fileExists(atPath:)) { return true }
        // A sandboxed app cannot write outside its own container.
        let probe = "/private/aeiot_write_probe"
        if (try? "probe".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probe)
            return true
        }
        return false
        #endif
    }
}

extension View {
    /// Covers the content whenever the screen is being recorded or mirrored.
    func hiddenWhileRecording(_ screenGuard: ScreenGuard) -> some View {
        overlay {
            if screenGuard.isRecording {
                ZStack {
                    Rectangle().fill(.ultraThickMaterial)
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.appAccent)
                        Text("Hidden while the screen is being recorded.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
}

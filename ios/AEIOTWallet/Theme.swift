import SwiftUI
import UIKit

enum ThemeMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    /// Applied to the window rather than the view tree: sheets live in their own
    /// presentation and would otherwise ignore a `preferredColorScheme`.
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: .unspecified
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .system: "gear"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .light: "Light Theme"
        case .dark: "Dark Theme"
        case .system: "System"
        }
    }
}

extension Color {
    /// The app's only accent, sampled from the AEIOT mark. Darkened on light
    /// backgrounds so red text still clears the contrast floor.
    static let appAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.953, green: 0.047, blue: 0.106, alpha: 1)
            : UIColor(red: 0.831, green: 0.031, blue: 0.086, alpha: 1)
    })

    static let appBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1)
            : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    })
}

extension View {
    func glassCard() -> some View {
        padding(20).glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    /// For text in a fixed-width slot — buttons, badges, a row's trailing value.
    /// Languages with long words (German "Empfangen", Ukrainian "Отримати")
    /// would otherwise wrap and push the surrounding layout out of shape, so the
    /// text shrinks to fit instead.
    func oneLine(_ minimumScale: CGFloat = 0.7) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScale)
    }
}

/// Falls back to a lettered disc for coins that have no artwork bundled.
struct TokenLogo: View {
    let token: Token
    var size: CGFloat = 40

    var body: some View {
        if UIImage(named: token.logo) != nil {
            Image(token.logo)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(.quaternary)
                .frame(width: size, height: size)
                .overlay {
                    Text(token.symbol.prefix(2))
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

enum Haptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, tr, es, de, fr, it, pt, nl, ru, uk, ar, hi, id_, th, vi, zhHans = "zh-Hans", ja, ko

    var id: String { rawValue }

    /// The .lproj folder to read strings from. Indonesian would collide with
    /// `Identifiable.id`, so its case carries an underscore and is mapped back here.
    var bundleCode: String { self == .id_ ? "id" : rawValue }

    /// Language names are written in their own language, as Apple does.
    var label: String {
        switch self {
        case .en: "English"
        case .tr: "Türkçe"
        case .es: "Español"
        case .de: "Deutsch"
        case .fr: "Français"
        case .it: "Italiano"
        case .pt: "Português"
        case .nl: "Nederlands"
        case .ru: "Русский"
        case .uk: "Українська"
        case .ar: "العربية"
        case .hi: "हिन्दी"
        case .id_: "Bahasa Indonesia"
        case .th: "ไทย"
        case .vi: "Tiếng Việt"
        case .zhHans: "简体中文"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }

    var layoutDirection: LayoutDirection { self == .ar ? .rightToLeft : .leftToRight }

    /// Only the languages whose strings actually shipped in this build — a case
    /// without its .lproj would silently fall back to English. The three the
    /// wallet's own users speak come first; the rest follow by name.
    /// Bundle.main never changes at runtime, so this is computed once.
    static let available: [AppLanguage] = {
        let shipped = allCases.filter {
            Bundle.main.path(forResource: $0.bundleCode, ofType: "lproj") != nil
        }
        let pinned: [AppLanguage] = [.tr, .en, .uk]
        let rest = shipped.filter { !pinned.contains($0) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return pinned.filter(shipped.contains) + rest
    }()

    /// First launch follows the device; after that the Settings choice wins.
    static var deviceDefault: AppLanguage {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return available.first {
            preferred == $0.bundleCode || preferred.hasPrefix($0.bundleCode + "-")
        } ?? .en
    }
}

/// Reads strings from the language the user picked in Settings instead of the
/// device language. Everything — `Text`, `Label`, `String(localized:)` — goes
/// through `localizedString(forKey:)`, so overriding it here covers the app.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table: String?) -> String {
        guard let code = Localization.overrideCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: table)
        }
        return bundle.localizedString(forKey: key, value: value, table: table)
    }
}

enum Localization {
    nonisolated(unsafe) fileprivate static var overrideCode: String?
    nonisolated(unsafe) private static var cached: Bundle?

    /// `String(localized:)` does not go through the Bundle override above, so it
    /// has to be handed this bundle explicitly — see `String.loc`.
    static var bundle: Bundle {
        if let cached { return cached }
        guard let code = overrideCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        cached = bundle
        return bundle
    }

    static func apply(_ language: AppLanguage) {
        _ = installOnce
        overrideCode = language.bundleCode
        cached = nil
    }

    private static let installOnce: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()
}

extension String {
    /// Use instead of `String(localized:)` so the text follows the language
    /// chosen in Settings rather than the device language.
    static func loc(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: Localization.bundle)
    }
}

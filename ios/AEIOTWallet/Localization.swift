import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case tr, en
    var id: String { rawValue }

    /// Language names are written in their own language, as Apple does.
    var label: String {
        switch self {
        case .tr: "Türkçe"
        case .en: "English"
        }
    }

    /// The .lproj folder to read strings from.
    var bundleCode: String { rawValue }

    /// First launch follows the device; after that the Settings choice wins.
    static var deviceDefault: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("tr") == true ? .tr : .en
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

import Foundation

enum L10n {
    private static let resourceBundleName = "CodexLoginManager_CodexLoginManager"

    private static let resourceBundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let appBundle = Bundle(
               url: resourceURL.appendingPathComponent("\(resourceBundleName).bundle")
           ) {
            return appBundle
        }

        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()

    private static let bundle = localizedBundle(
        in: resourceBundle,
        preferredLanguages: Locale.preferredLanguages
    )

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static func text(_ key: String, preferredLanguages: [String]) -> String {
        let bundle = localizedBundle(in: resourceBundle, preferredLanguages: preferredLanguages)
        return NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    private static func localizedBundle(
        in resourceBundle: Bundle,
        preferredLanguages: [String]
    ) -> Bundle {
        let availableLocalizations = resourceBundle.localizations.filter { $0 != "Base" }
        guard let localization = Bundle.preferredLocalizations(
            from: availableLocalizations,
            forPreferences: preferredLanguages
        ).first,
        let localizationPath = resourceBundle.path(forResource: localization, ofType: "lproj"),
        let localizedBundle = Bundle(path: localizationPath) else {
            return resourceBundle
        }

        return localizedBundle
    }
}

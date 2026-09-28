import Foundation
import SwiftUI

enum AddressBarPosition: String, CaseIterable, Identifiable {
    case bottom = "Onderaan"
    case top = "Bovenaan"
    var id: String { rawValue }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo = "DuckDuckGo"
    case brave = "Brave Search"
    case google = "Google"
    case bing = "Bing"

    var id: String { rawValue }

    func searchURL(for query: String) -> URL? {
        var base: String
        switch self {
        case .duckDuckGo: base = "https://duckduckgo.com/"
        case .brave: base = "https://search.brave.com/search"
        case .google: base = "https://www.google.com/search"
        case .bing: base = "https://www.bing.com/search"
        }

        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Systeem"
    case light = "Licht"
    case dark = "Donker"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var strictBlocking: Bool { didSet { save("strictBlocking", strictBlocking) } }
    @Published var clearOnBackground: Bool { didSet { save("clearOnBackground", clearOnBackground) } }
    @Published var targetLanguage: String { didSet { save("targetLanguage", targetLanguage) } }
    @Published var homePage: String { didSet { save("homePage", homePage) } }
    @Published var addressBarPositionRaw: String { didSet { save("addressBarPosition", addressBarPositionRaw) } }
    @Published var searchEngineRaw: String { didSet { save("searchEngine", searchEngineRaw) } }
    @Published var themeRaw: String { didSet { save("theme", themeRaw) } }
    @Published var textScale: Double { didSet { save("textScale", textScale) } }
    @Published var httpsOnly: Bool { didSet { save("httpsOnly", httpsOnly) } }
    @Published var javaScriptEnabled: Bool { didSet { save("javaScriptEnabled", javaScriptEnabled) } }
    @Published var desktopMode: Bool { didSet { save("desktopMode", desktopMode) } }
    @Published var blockPopups: Bool { didSet { save("blockPopups", blockPopups) } }

    var addressBarPosition: AddressBarPosition {
        get { AddressBarPosition(rawValue: addressBarPositionRaw) ?? .bottom }
        set { addressBarPositionRaw = newValue.rawValue }
    }

    var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: searchEngineRaw) ?? .duckDuckGo }
        set { searchEngineRaw = newValue.rawValue }
    }

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    private init() {
        strictBlocking = defaults.object(forKey: "strictBlocking") as? Bool ?? false
        clearOnBackground = defaults.object(forKey: "clearOnBackground") as? Bool ?? true
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? "nl"
        homePage = defaults.string(forKey: "homePage") ?? "https://duckduckgo.com/"
        addressBarPositionRaw = defaults.string(forKey: "addressBarPosition") ?? AddressBarPosition.bottom.rawValue
        searchEngineRaw = defaults.string(forKey: "searchEngine") ?? SearchEngine.duckDuckGo.rawValue
        themeRaw = defaults.string(forKey: "theme") ?? AppTheme.system.rawValue
        textScale = defaults.object(forKey: "textScale") as? Double ?? 1.0
        httpsOnly = defaults.object(forKey: "httpsOnly") as? Bool ?? true
        javaScriptEnabled = defaults.object(forKey: "javaScriptEnabled") as? Bool ?? true
        desktopMode = defaults.object(forKey: "desktopMode") as? Bool ?? false
        blockPopups = defaults.object(forKey: "blockPopups") as? Bool ?? true
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }
}

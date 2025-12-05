
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System default"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Returns the ColorScheme override, or nil for system default
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum UserDefaultsKeys {
    static let selectedTheme = "selectedTheme"
}


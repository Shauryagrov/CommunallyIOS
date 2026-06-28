//
//  ThemeMode.swift
//  Communally
//
//  User-selectable appearance: System / Light / Dark. Persisted in
//  UserDefaults via @AppStorage("communally_theme_mode"). Read at the app
//  root to drive `.preferredColorScheme`.
//
//  Defaults to `.light` so existing users see no change on update; dark
//  mode is opt-in from Settings until the full surface sweep lands.
//

import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// The forced appearance — always Light or Dark (no System option).
    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "communally_theme_mode"
}

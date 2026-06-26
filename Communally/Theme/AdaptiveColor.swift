//
//  AdaptiveColor.swift
//  Communally
//
//  Helpers for colors that resolve differently in Light vs Dark mode.
//  The whole dark-mode story leans on this: CommunallyTheme tokens are
//  redefined as `.adaptive(light:dark:)` so every existing call site
//  (CommunallyTheme.primaryGreen, .darkGray, …) adapts with zero changes.
//

import SwiftUI
import UIKit

extension UIColor {
    /// Convenience for opaque sRGB from 0...1 components.
    convenience init(rgb r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    /// A UIColor that resolves per trait collection (Light vs Dark).
    static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension Color {
    /// A SwiftUI Color that resolves per trait collection (Light vs Dark).
    /// Resolves against the current environment when rendered, so it also
    /// works inside otherwise-static gradients.
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor.adaptive(light: light, dark: dark))
    }
}

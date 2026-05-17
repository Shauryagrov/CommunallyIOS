//
//  ReviewPromptManager.swift
//  Communally
//

import Foundation

final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    private let defaults = UserDefaults.standard
    private let firstLaunchKey  = "rl_firstLaunch"
    private let launchCountKey  = "rl_launchCount"
    private let promptedKey     = "rl_reviewPrompted_v1"

    private init() {}

    func recordLaunch() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
        }
        defaults.set(defaults.integer(forKey: launchCountKey) + 1, forKey: launchCountKey)
    }

    // Show after 3+ days AND 4+ launches — enough signal that the user is engaged.
    var shouldPrompt: Bool {
        guard !defaults.bool(forKey: promptedKey) else { return false }
        guard let first = defaults.object(forKey: firstLaunchKey) as? Date else { return false }
        let days = Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
        return days >= 3 && defaults.integer(forKey: launchCountKey) >= 4
    }

    func markPrompted() {
        defaults.set(true, forKey: promptedKey)
    }
}

import Foundation

enum ModerationSurface {
    case jobPost
    case message
    case profile
}

enum ContentModerationError: LocalizedError {
    case unsafe(surface: ModerationSurface)
    case offTopic(surface: ModerationSurface)
    
    var errorDescription: String? {
        switch self {
        case .unsafe(let surface):
            switch surface {
            case .jobPost:
                return "This post includes unsafe or inappropriate language. Keep job posts professional and job-related."
            case .message:
                return "That message looks unsafe or inappropriate. Keep messages professional and related to the job."
            case .profile:
                return "That profile text includes unsafe or inappropriate language. Keep it professional."
            }
        case .offTopic(let surface):
            switch surface {
            case .jobPost:
                return "This post looks unrelated to a legitimate job. Describe the work, pay, time, and location instead."
            case .message:
                return "That message does not look job-related. Keep conversations focused on the opportunity."
            case .profile:
                return "That profile text does not look appropriate for Communally."
            }
        }
    }
}

final class ContentModerationService {
    static let shared = ContentModerationService()
    
    private let explicitPatterns = [
        "nudes?",
        "naked",
        "sexy",
        "horny",
        "fetish",
        "kink",
        "porn",
        "blowjob",
        "hook ?up",
        "sugar daddy",
        "sugar baby",
        "bedroom",
        "sleep ?over",
        "cuddle",
        "kiss me",
        "touch me"
    ]
    
    private let groomingOrIsolationPatterns = [
        "come alone",
        "dont tell your parents",
        "don't tell your parents",
        "dont tell anyone",
        "fuck",
        "shit",
        "bitch",
        "slut",
        "sex",
        
        "don't tell anyone",
        "keep this secret",
        "no parents",
        "no adults",
        "get in my car",
        "ride with me",
        "private room",
        "my place only",
        "hotel room"
    ]
    
    private let offPlatformPatterns = [
        "snap(chat)?",
        "telegram",
        "whats ?app",
        "discord",
        "signal me",
        "text me instead",
        "dm me instead",
        "send pics",
        "send photo",
        "send selfie"
    ]
    
    private init() {}
    
    func validateJobPost(title: String, description: String) -> ContentModerationError? {
        let combined = "\(title) \(description)"
        if containsUnsafePattern(in: combined) {
            return .unsafe(surface: .jobPost)
        }
        if containsOffTopicPattern(in: combined) {
            return .offTopic(surface: .jobPost)
        }
        return nil
    }
    
    func validateMessage(_ text: String) -> ContentModerationError? {
        if containsUnsafePattern(in: text) {
            return .unsafe(surface: .message)
        }
        if containsOffTopicPattern(in: text) {
            return .offTopic(surface: .message)
        }
        return nil
    }
    
    func validateProfileText(_ text: String) -> ContentModerationError? {
        if containsUnsafePattern(in: text) {
            return .unsafe(surface: .profile)
        }
        return nil
    }
    
    private func containsUnsafePattern(in text: String) -> Bool {
        contains(patterns: explicitPatterns + groomingOrIsolationPatterns, in: text)
    }
    
    private func containsOffTopicPattern(in text: String) -> Bool {
        contains(patterns: offPlatformPatterns, in: text)
    }
    
    private func contains(patterns: [String], in text: String) -> Bool {
        let normalized = text.lowercased()
        return patterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

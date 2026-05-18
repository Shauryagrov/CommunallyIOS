//
//  CrashReporter.swift
//  Communally
//
//  Thin wrapper around Firebase Crashlytics. Keeps all crash-reporting
//  calls in one place so callers don't import Crashlytics directly and
//  we can swap providers (Sentry, Bugsnag) without touching the rest
//  of the app.
//
//  Crashlytics auto-initializes once FirebaseApp.configure() runs, so
//  `bootstrap()` is mostly a no-op today — its job is to log a clear
//  marker on launch (so we can confirm in Console that the SDK linked
//  successfully) and to be the documented init point if we ever need
//  to flip flags before the first event is captured.
//
//  Usage:
//    CrashReporter.shared.bootstrap()                 // once, from CommunallyApp
//    CrashReporter.shared.setUser(userId: "abc123")   // on sign-in
//    CrashReporter.shared.clearUser()                 // on sign-out
//    CrashReporter.shared.log("payment release attempt for job \(id)")
//    CrashReporter.shared.recordError(error)
//

import Foundation
import FirebaseCrashlytics

final class CrashReporter {
    static let shared = CrashReporter()

    private init() {}

    /// Called once from CommunallyApp after FirebaseApp.configure().
    /// Crashlytics auto-starts when linked, but we call this so the
    /// import isn't dead-code-eliminated and so we have a single
    /// place to attach build-time keys (version, build number, etc).
    func bootstrap() {
        let crashlytics = Crashlytics.crashlytics()

        // Tag every report with the marketing version + build number
        // so we can filter by release in the Crashlytics console.
        if let info = Bundle.main.infoDictionary {
            if let version = info["CFBundleShortVersionString"] as? String {
                crashlytics.setCustomValue(version, forKey: "app_version")
            }
            if let build = info["CFBundleVersion"] as? String {
                crashlytics.setCustomValue(build, forKey: "app_build")
            }
        }

        #if DEBUG
        // Disable crash collection in DEBUG so simulator/dev crashes
        // don't pollute the dashboard. Flip to true if you specifically
        // want to test the integration end-to-end.
        crashlytics.setCrashlyticsCollectionEnabled(false)
        print("🟡 Crashlytics: collection DISABLED in DEBUG build")
        #else
        crashlytics.setCrashlyticsCollectionEnabled(true)
        print("✅ Crashlytics: enabled for release build")
        #endif
    }

    /// Attach the signed-in user's ID to subsequent crash reports so
    /// we can correlate a crash with a Firestore user. Do NOT pass
    /// email or anything PII — Apple's privacy rules require this
    /// identifier to be opaque.
    func setUser(userId: String) {
        guard !userId.isEmpty else { return }
        Crashlytics.crashlytics().setUserID(userId)
    }

    /// Clear the user ID on sign-out so the next user's crashes
    /// aren't misattributed.
    func clearUser() {
        Crashlytics.crashlytics().setUserID("")
    }

    /// Add a breadcrumb that will be attached to the next crash report.
    /// Use sparingly for high-signal events (payment release, account
    /// deletion, identity verification step). Avoid logging PII or
    /// payment amounts.
    func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    /// Record a caught non-fatal error so we can see it in the
    /// Crashlytics dashboard without crashing the app. Useful for
    /// "this shouldn't have happened" branches in payment / auth flows.
    func recordError(_ error: Error, context: [String: String]? = nil) {
        if let context = context, !context.isEmpty {
            let crashlytics = Crashlytics.crashlytics()
            for (key, value) in context {
                crashlytics.setCustomValue(value, forKey: key)
            }
        }
        Crashlytics.crashlytics().record(error: error)
    }

}

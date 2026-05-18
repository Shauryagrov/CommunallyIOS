//
//  CommunallyApp.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import GoogleSignIn
import Foundation
import FirebaseCore
import FirebaseCrashlytics
import FirebaseMessaging
import UserNotifications

@main
struct CommunallyApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Configure Firebase with error handling
        configureFirebase()
    }
    
    private func configureFirebase() {
        // Check if GoogleService-Info.plist exists and has valid values
        guard let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let googleAppId = plist["GOOGLE_APP_ID"] as? String,
              !googleAppId.contains("YOUR_") else {
            print("❌ Firebase configuration SKIPPED")
            print("⚠️  GoogleService-Info.plist has placeholder values")
            print("📝 To fix this:")
            print("   1. Go to https://console.firebase.google.com")
            print("   2. Download your GoogleService-Info.plist")
            print("   3. Replace Communally/GoogleService-Info.plist")
            print("   4. See IMPORTANT_FIREBASE_SETUP.md for details")
            return
        }
        
        // Configure Firebase if not already done in AppDelegate
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully")
        }
        guard FirebaseApp.app() != nil else { return }

        // Crashlytics MUST bootstrap right after FirebaseApp.configure() so
        // it captures any crash that happens during the rest of init. The
        // helper is a no-op in DEBUG so simulator crashes don't pollute
        // the production dashboard.
        CrashReporter.shared.bootstrap()

        // Initialize managers (safe if AppDelegate already configured Firebase)
        OpportunityManager.shared.initialize()
        ApplicationManager.shared.initialize()
        RatingManager.shared.startListening()
        print("✅ Firestore listeners initialized")
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                SplashScreenView()
                    .environmentObject(authManager)
                LoadingOverlayView()
            }
            // Force light mode app-wide. Without this, devices set to dark
            // mode bleed into our white cards — text fields render with white
            // text on white backgrounds (invisible) and TextEditors get a
            // black background. We always want the same light look.
            .preferredColorScheme(.light)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

// MARK: - App Delegate for Push Notifications

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        Messaging.messaging().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Hand the APNs token to FCM so it can map it to an FCM registration token.
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        // FCM tokens are per-device push targets — anyone with one can
        // send arbitrary pushes to this device until it rotates. Don't
        // leave them in customer Console logs.
        Log.debug("✅ FCM token: \(fcmToken)")
        NotificationManager.shared.saveFCMToken(fcmToken)
    }
}


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
        
        // Configure Firebase if valid credentials exist
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("✅ Firebase configured successfully")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

// MARK: - App Delegate for Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        return true
    }
    
    // Handle device token for push notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("✅ Device Token: \(token)")
        // In production, you would send this token to your server
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

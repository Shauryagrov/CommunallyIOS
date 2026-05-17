//
//  UserMigration.swift
//  Communally
//
//  Migrates existing local users to Firebase
//

import Foundation
import FirebaseCore
import FirebaseFirestore

class UserMigration {
    static let shared = UserMigration()
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    
    private init() {}
    
    /// Migrate all local users to Firebase (one-time operation)
    func migrateLocalUsersToFirebase(completion: @escaping (Int, Int) -> Void) {
        guard let db = db else {
            print("❌ UserMigration: Firebase not configured")
            completion(0, 0)
            return
        }
        
        let localUsers = UserDatabase.shared.getAllUsers()
        
        guard !localUsers.isEmpty else {
            print("ℹ️ UserMigration: No local users to migrate")
            completion(0, 0)
            return
        }
        
        print("🔄 UserMigration: Starting migration of \(localUsers.count) users...")
        
        var successCount = 0
        var failureCount = 0
        let dispatchGroup = DispatchGroup()
        
        for user in localUsers {
            dispatchGroup.enter()
            
            do {
                try db.collection("users").document(user.id).setData(from: user) { error in
                    if let error = error {
                        print("❌ UserMigration: Failed to migrate \(user.fullName): \(error.localizedDescription)")
                        failureCount += 1
                    } else {
                        print("✅ UserMigration: Migrated \(user.fullName)")
                        successCount += 1
                    }
                    dispatchGroup.leave()
                }
            } catch {
                print("❌ UserMigration: Error encoding user \(user.fullName): \(error.localizedDescription)")
                failureCount += 1
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            print("🎉 UserMigration: Complete! ✅ \(successCount) succeeded, ❌ \(failureCount) failed")
            completion(successCount, failureCount)
        }
    }
    
    /// Check if migration is needed
    func needsMigration() -> Bool {
        let localUsers = UserDatabase.shared.getAllUsers()
        let hasMigrated = UserDefaults.standard.bool(forKey: "hasМigratedUsersToFirebase")
        
        return !localUsers.isEmpty && !hasMigrated
    }
    
    /// Mark migration as complete
    func markMigrationComplete() {
        UserDefaults.standard.set(true, forKey: "hasMigratedUsersToFirebase")
        print("✅ UserMigration: Marked migration as complete")
    }
}


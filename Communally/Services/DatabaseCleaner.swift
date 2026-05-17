//
//  DatabaseCleaner.swift
//  Communally
//
//  Utility to clear all data and start fresh
//

import Foundation
import FirebaseCore
import FirebaseFirestore

class DatabaseCleaner {
    static let shared = DatabaseCleaner()
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    
    private init() {}
    
    /// DANGER: Deletes ALL data from Firebase and local storage
    func deleteEverything(completion: @escaping (Bool) -> Void) {
        print("🗑️ DatabaseCleaner: Starting complete data wipe...")
        print("⚠️ This will delete ALL users, opportunities, applications, messages, notifications, and ratings!")
        
        let dispatchGroup = DispatchGroup()
        var hasErrors = false
        
        // Clear all local data first
        clearAllLocalData()
        
        guard let db = db else {
            print("⚠️ DatabaseCleaner: Firebase not configured, local data cleared only")
            completion(true)
            return
        }
        
        // Delete all collections from Firebase
        let collections = ["users", "opportunities", "applications", "conversations", "messages", "notifications", "ratings"]
        
        for collectionName in collections {
            dispatchGroup.enter()
            deleteCollection(db: db, collectionName: collectionName) { success in
                if !success {
                    hasErrors = true
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if hasErrors {
                print("⚠️ DatabaseCleaner: Completed with some errors")
            } else {
                print("✅ DatabaseCleaner: All data deleted successfully!")
            }
            print("🎉 Database is now completely clean and ready for fresh start!")
            completion(!hasErrors)
        }
    }
    
    /// Delete all documents in a collection
    private func deleteCollection(db: Firestore, collectionName: String, completion: @escaping (Bool) -> Void) {
        print("🗑️ Deleting collection: \(collectionName)...")
        
        db.collection(collectionName).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching \(collectionName): \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                print("ℹ️ Collection \(collectionName) is already empty")
                completion(true)
                return
            }
            
            let batch = db.batch()
            for document in documents {
                batch.deleteDocument(document.reference)
            }
            
            batch.commit { error in
                if let error = error {
                    print("❌ Error deleting \(collectionName): \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Deleted \(documents.count) documents from \(collectionName)")
                    completion(true)
                }
            }
        }
    }
    
    /// Clear all local data (UserDefaults)
    private func clearAllLocalData() {
        print("🗑️ Clearing all local data...")
        
        // Clear user data
        UserDefaults.standard.removeObject(forKey: "savedUserId")
        UserDefaults.standard.removeObject(forKey: "savedUser")
        UserDefaults.standard.removeObject(forKey: "allUsers")
        
        // Clear migration flag
        UserDefaults.standard.removeObject(forKey: "hasMigratedUsersToFirebase")
        
        // Clear any other app data
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        
        print("✅ All local data cleared")
    }
}


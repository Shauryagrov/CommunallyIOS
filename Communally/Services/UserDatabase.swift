//
//  UserDatabase.swift
//  Communally
//
//  Persistent storage for all users
//

import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

class UserDatabase: ObservableObject {
    static let shared = UserDatabase()
    
    private let usersKey = "allUsers"
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }
    
    private init() {}
    
    // Get user by Google ID
    func getUser(byGoogleId googleId: String) -> User? {
        let allUsers = getAllUsers()
        return allUsers.first { $0.id == googleId }
    }
    
    // Get user by email
    func getUser(byEmail email: String) -> User? {
        let allUsers = getAllUsers()
        return allUsers.first { $0.email == email }
    }
    
    func getUser(byAppleUserId appleUserId: String) -> User? {
        let allUsers = getAllUsers()
        return allUsers.first { $0.appleUserId == appleUserId }
    }
    
    // Save or update user
    func saveUser(_ user: User) {
        var allUsers = getAllUsers()
        
        // Remove existing user with same ID if exists
        allUsers.removeAll { $0.id == user.id }
        
        // Add updated user
        allUsers.append(user)
        
        // Save to UserDefaults
        if let encodedData = try? JSONEncoder().encode(allUsers) {
            UserDefaults.standard.set(encodedData, forKey: usersKey)
            print("💾 UserDatabase: Saved user \(user.fullName) (Total users: \(allUsers.count))")
        }
        
        syncUserToFirebase(user)
    }
    
    // Get all users
    func getAllUsers() -> [User] {
        guard let data = UserDefaults.standard.data(forKey: usersKey),
              let users = try? JSONDecoder().decode([User].self, from: data) else {
            return []
        }
        return users
    }
    
    // Delete user
    func deleteUser(byId id: String) {
        var allUsers = getAllUsers()
        allUsers.removeAll { $0.id == id }
        
        if let encodedData = try? JSONEncoder().encode(allUsers) {
            UserDefaults.standard.set(encodedData, forKey: usersKey)
            print("🗑️ UserDatabase: Deleted user with ID \(id)")
        }
    }
    
    /// Removes the user document from Firestore (`users/{userId}`). Call before clearing local session.
    func deleteUserFromFirebase(userId: String, completion: @escaping (Error?) -> Void) {
        guard let db = db else {
            completion(NSError(domain: "UserDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Firebase is not configured."]))
            return
        }
        
        db.collection("users").document(userId).delete { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ UserDatabase: Failed to delete cloud user \(userId): \(error.localizedDescription)")
                } else {
                    print("☁️ UserDatabase: Deleted cloud user \(userId)")
                }
                completion(error)
            }
        }
    }
    
    // Clear all users (for testing)
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: usersKey)
        print("🗑️ UserDatabase: Cleared all users")
    }
    
    // MARK: - Cloud Sync
    
    func fetchUserFromFirebase(byGoogleId googleId: String, completion: @escaping (User?) -> Void) {
        guard let db = db else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        db.collection("users").document(googleId).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("⚠️ UserDatabase: Failed to fetch cloud user \(googleId): \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            do {
                let user = try snapshot.data(as: User.self)
                self?.saveUserLocally(user)
                DispatchQueue.main.async { completion(user) }
            } catch {
                print("⚠️ UserDatabase: Failed to decode cloud user \(googleId): \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    func fetchUserFromFirebase(byUserId userId: String, completion: @escaping (User?) -> Void) {
        guard let db = db else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("⚠️ UserDatabase: Failed to fetch user \(userId): \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            do {
                let user = try snapshot.data(as: User.self)
                self?.saveUserLocally(user)
                DispatchQueue.main.async { completion(user) }
            } catch {
                print("⚠️ UserDatabase: Failed to decode user \(userId): \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    func fetchUserFromFirebase(byEmail email: String, completion: @escaping (User?) -> Void) {
        guard let db = db else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("⚠️ UserDatabase: Failed to fetch user by email \(email): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                do {
                    let user = try document.data(as: User.self)
                    self?.saveUserLocally(user)
                    DispatchQueue.main.async { completion(user) }
                } catch {
                    print("⚠️ UserDatabase: Failed to decode user by email \(email): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                }
            }
    }
    
    func fetchUserFromFirebase(byAppleUserId appleUserId: String, completion: @escaping (User?) -> Void) {
        guard let db = db else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        db.collection("users")
            .whereField("appleUserId", isEqualTo: appleUserId)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("⚠️ UserDatabase: Failed to fetch user by Apple ID \(appleUserId): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                do {
                    let user = try document.data(as: User.self)
                    self?.saveUserLocally(user)
                    DispatchQueue.main.async { completion(user) }
                } catch {
                    print("⚠️ UserDatabase: Failed to decode user by Apple ID \(appleUserId): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                }
            }
    }
    
    private func syncUserToFirebase(_ user: User) {
        guard let db = db else { return }
        
        do {
            var data = try Firestore.Encoder().encode(user)
            data["usernameLowercased"] = user.username?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            db.collection("users").document(user.id).setData(data, merge: true) { error in
                if let error = error {
                    print("⚠️ UserDatabase: Failed to sync user \(user.fullName) to Firebase: \(error.localizedDescription)")
                } else {
                    print("☁️ UserDatabase: Synced user \(user.fullName) to Firebase")
                }
            }
        } catch {
            print("⚠️ UserDatabase: Failed to encode user \(user.fullName) for Firebase sync: \(error.localizedDescription)")
        }
    }
    
    private func saveUserLocally(_ user: User) {
        var allUsers = getAllUsers()
        allUsers.removeAll { $0.id == user.id }
        allUsers.append(user)
        
        if let encodedData = try? JSONEncoder().encode(allUsers) {
            UserDefaults.standard.set(encodedData, forKey: usersKey)
            print("💾 UserDatabase: Cached cloud user \(user.fullName) locally")
        }
    }
    
    // MARK: - Username Availability
    
    /// Check if username is available (async, non-blocking)
    func checkUsernameAvailability(_ username: String, completion: @escaping (Bool) -> Void) {
        let lowercased = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check locally first
        let localUsers = getAllUsers()
        if localUsers.contains(where: { $0.username?.lowercased() == lowercased }) {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // If we have Firebase, check there too
        guard let db = db else {
            // No Firebase, just check local
            DispatchQueue.main.async {
                completion(true)
            }
            return
        }
        
        db.collection("users")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("⚠️ Error checking username: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(true) // Allow on error
                    }
                    return
                }
                
                let isAvailable = !(snapshot?.documents.contains(where: { document in
                    let username = ((document.data()["usernameLowercased"] as? String)
                        ?? (document.data()["username"] as? String)?.lowercased()
                        ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return username == lowercased
                }) ?? false)
                
                DispatchQueue.main.async {
                    completion(isAvailable)
                }
            }
    }
}


//
//  User.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import Foundation

/// Optional credential files (PDF / images) a job seeker adds to their profile — similar idea to LinkedIn media.
struct QualificationAttachment: Codable, Identifiable, Hashable {
    let id: String
    let fileName: String
    let downloadURL: String
    let uploadedAt: Date?
    
    init(id: String = UUID().uuidString, fileName: String, downloadURL: String, uploadedAt: Date? = Date()) {
        self.id = id
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.uploadedAt = uploadedAt
    }
}

enum UserType: String, CaseIterable, Codable {
    case jobSeeker = "job_seeker"
    case jobHirer = "job_hirer"
}

enum UserAgeGroup: String, Codable {
    case teen = "teen" // under 18
    case adult = "adult" // 18+
}

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let username: String? // Unique username (@handle)
    let firstName: String
    let lastName: String
    /// Stored age (kept for Firestore compatibility). Prefer `resolvedAge` for display and rules.
    let age: Int
    /// When set, `resolvedAge` is derived from this so the profile stays accurate over time.
    let dateOfBirth: Date?
    let userType: UserType
    let profileImageURL: String?
    let profileImageData: Data? // Store the actual image data
    let skills: [String]
    let description: String?
    let location: Location?
    let createdAt: Date
    let parentalConsentGiven: Bool? // For minors - parent acknowledged terms
    let hasCompletedOnboarding: Bool
    let acceptedTermsDate: Date?
    let acceptedPrivacyDate: Date?
    
    // Change tracking for username and name
    let lastUsernameChange: Date? // When username was last changed
    let lastNameChange: Date? // When name (first/last) was last changed
    
    // Stripe fields for payment processing
    let stripeCustomerId: String? // For hirers making payments
    let stripeConnectAccountId: String? // For workers receiving payouts
    let stripeConnectActive: Bool? // Is Connect account fully set up?
    let stripeConnectDetailsSubmitted: Bool? // Has worker submitted details?
    
    // Legacy bank account fields (kept for backwards compatibility)
    let bankAccountConnected: Bool?
    let stripeConnectedAccountId: String?
    var appleUserId: String? = nil
    
    /// Hirer identity verification (not government KYC — stored for admin review).
    let legalFirstNameOnId: String?
    let legalLastNameOnId: String?
    let identityDocumentURL: String?
    let identityVerificationSubmittedAt: Date?
    
    /// Hirer verified US home address (from onboarding); used to enforce posting within 5 miles.
    let verifiedHomeAddress: String?
    let verifiedHomeLatitude: Double?
    let verifiedHomeLongitude: Double?
    
    /// Government ID + selfie verified via Stripe Identity (`identity.verification_session` → webhook updates Firestore).
    let stripeIdentityVerified: Bool?
    let stripeIdentityVerifiedAt: Date?
    let stripeIdentityLastSessionId: String?
    
    /// Résumé, certificates, or other credentials (seekers); Firebase Storage URLs.
    let qualificationAttachments: [QualificationAttachment]?

    /// Cover banner image shown above the avatar on the profile screen (Twitter/LinkedIn style).
    let profileBannerImageData: Data?

    /// Optional self-described pronouns shown next to the @handle.
    let pronouns: String?

    /// Up to 3 images attached to the bio (compressed, stored as Data).
    let bioAttachmentData: [Data]

    /// Parent's email captured during seeker onboarding (under-18 only).
    /// Non-nil means the seeker has provided a parent contact and a verification email has been sent.
    let parentEmail: String?

    /// Parent's name captured during seeker onboarding.
    let parentName: String?

    /// One-time token sent to the parent in the approval email; verified by the
    /// `approveParentalConsent` Cloud Function before flipping `isParentalApproved`.
    let parentApprovalToken: String?

    /// True once the parent clicks the approval link in the email.
    let isParentalApproved: Bool?

    /// Server-side timestamp set by the Cloud Function when the parent approves.
    let parentApprovalDate: Date?

    /// Custom init kept backwards-compatible: every new field has a default so existing
    /// `User(id: …, email: …, …)` call sites elsewhere in the app keep compiling.
    init(
        id: String,
        email: String,
        username: String?,
        firstName: String,
        lastName: String,
        age: Int,
        dateOfBirth: Date?,
        userType: UserType,
        profileImageURL: String?,
        profileImageData: Data?,
        skills: [String],
        description: String?,
        location: Location?,
        createdAt: Date,
        parentalConsentGiven: Bool?,
        hasCompletedOnboarding: Bool,
        acceptedTermsDate: Date?,
        acceptedPrivacyDate: Date?,
        lastUsernameChange: Date?,
        lastNameChange: Date?,
        stripeCustomerId: String?,
        stripeConnectAccountId: String?,
        stripeConnectActive: Bool?,
        stripeConnectDetailsSubmitted: Bool?,
        bankAccountConnected: Bool?,
        stripeConnectedAccountId: String?,
        appleUserId: String? = nil,
        legalFirstNameOnId: String?,
        legalLastNameOnId: String?,
        identityDocumentURL: String?,
        identityVerificationSubmittedAt: Date?,
        verifiedHomeAddress: String?,
        verifiedHomeLatitude: Double?,
        verifiedHomeLongitude: Double?,
        stripeIdentityVerified: Bool?,
        stripeIdentityVerifiedAt: Date?,
        stripeIdentityLastSessionId: String?,
        qualificationAttachments: [QualificationAttachment]?,
        profileBannerImageData: Data? = nil,
        pronouns: String? = nil,
        bioAttachmentData: [Data] = [],
        parentEmail: String? = nil,
        parentName: String? = nil,
        parentApprovalToken: String? = nil,
        isParentalApproved: Bool? = nil,
        parentApprovalDate: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.age = age
        self.dateOfBirth = dateOfBirth
        self.userType = userType
        self.profileImageURL = profileImageURL
        self.profileImageData = profileImageData
        self.skills = skills
        self.description = description
        self.location = location
        self.createdAt = createdAt
        self.parentalConsentGiven = parentalConsentGiven
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.acceptedTermsDate = acceptedTermsDate
        self.acceptedPrivacyDate = acceptedPrivacyDate
        self.lastUsernameChange = lastUsernameChange
        self.lastNameChange = lastNameChange
        self.stripeCustomerId = stripeCustomerId
        self.stripeConnectAccountId = stripeConnectAccountId
        self.stripeConnectActive = stripeConnectActive
        self.stripeConnectDetailsSubmitted = stripeConnectDetailsSubmitted
        self.bankAccountConnected = bankAccountConnected
        self.stripeConnectedAccountId = stripeConnectedAccountId
        self.appleUserId = appleUserId
        self.legalFirstNameOnId = legalFirstNameOnId
        self.legalLastNameOnId = legalLastNameOnId
        self.identityDocumentURL = identityDocumentURL
        self.identityVerificationSubmittedAt = identityVerificationSubmittedAt
        self.verifiedHomeAddress = verifiedHomeAddress
        self.verifiedHomeLatitude = verifiedHomeLatitude
        self.verifiedHomeLongitude = verifiedHomeLongitude
        self.stripeIdentityVerified = stripeIdentityVerified
        self.stripeIdentityVerifiedAt = stripeIdentityVerifiedAt
        self.stripeIdentityLastSessionId = stripeIdentityLastSessionId
        self.qualificationAttachments = qualificationAttachments
        self.profileBannerImageData = profileBannerImageData
        self.pronouns = pronouns
        self.bioAttachmentData = bioAttachmentData
        self.parentEmail = parentEmail
        self.parentName = parentName
        self.parentApprovalToken = parentApprovalToken
        self.isParentalApproved = isParentalApproved
        self.parentApprovalDate = parentApprovalDate
    }

    // Custom Codable so old cloud user docs (saved before later fields existed)
    // still decode successfully — missing fields fall back to safe defaults
    // instead of failing the whole document and tripping the "new user" path.
    private enum CodingKeys: String, CodingKey {
        case id, email, username, firstName, lastName, age, dateOfBirth, userType
        case profileImageURL, profileImageData, skills, description, location, createdAt
        case parentalConsentGiven, hasCompletedOnboarding, acceptedTermsDate, acceptedPrivacyDate
        case lastUsernameChange, lastNameChange
        case stripeCustomerId, stripeConnectAccountId, stripeConnectActive, stripeConnectDetailsSubmitted
        case bankAccountConnected, stripeConnectedAccountId, appleUserId
        case legalFirstNameOnId, legalLastNameOnId, identityDocumentURL, identityVerificationSubmittedAt
        case verifiedHomeAddress, verifiedHomeLatitude, verifiedHomeLongitude
        case stripeIdentityVerified, stripeIdentityVerifiedAt, stripeIdentityLastSessionId
        case qualificationAttachments
        case profileBannerImageData, pronouns, bioAttachmentData
        case parentEmail, parentName, parentApprovalToken, isParentalApproved, parentApprovalDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.email = try c.decode(String.self, forKey: .email)
        self.username = try c.decodeIfPresent(String.self, forKey: .username)
        self.firstName = try c.decode(String.self, forKey: .firstName)
        self.lastName = try c.decode(String.self, forKey: .lastName)
        self.age = try c.decode(Int.self, forKey: .age)
        self.dateOfBirth = try c.decodeIfPresent(Date.self, forKey: .dateOfBirth)
        self.userType = try c.decode(UserType.self, forKey: .userType)
        self.profileImageURL = try c.decodeIfPresent(String.self, forKey: .profileImageURL)
        self.profileImageData = try c.decodeIfPresent(Data.self, forKey: .profileImageData)
        self.skills = (try c.decodeIfPresent([String].self, forKey: .skills)) ?? []
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.location = try c.decodeIfPresent(Location.self, forKey: .location)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.parentalConsentGiven = try c.decodeIfPresent(Bool.self, forKey: .parentalConsentGiven)
        self.hasCompletedOnboarding = (try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
        self.acceptedTermsDate = try c.decodeIfPresent(Date.self, forKey: .acceptedTermsDate)
        self.acceptedPrivacyDate = try c.decodeIfPresent(Date.self, forKey: .acceptedPrivacyDate)
        self.lastUsernameChange = try c.decodeIfPresent(Date.self, forKey: .lastUsernameChange)
        self.lastNameChange = try c.decodeIfPresent(Date.self, forKey: .lastNameChange)
        self.stripeCustomerId = try c.decodeIfPresent(String.self, forKey: .stripeCustomerId)
        self.stripeConnectAccountId = try c.decodeIfPresent(String.self, forKey: .stripeConnectAccountId)
        self.stripeConnectActive = try c.decodeIfPresent(Bool.self, forKey: .stripeConnectActive)
        self.stripeConnectDetailsSubmitted = try c.decodeIfPresent(Bool.self, forKey: .stripeConnectDetailsSubmitted)
        self.bankAccountConnected = try c.decodeIfPresent(Bool.self, forKey: .bankAccountConnected)
        self.stripeConnectedAccountId = try c.decodeIfPresent(String.self, forKey: .stripeConnectedAccountId)
        self.appleUserId = try c.decodeIfPresent(String.self, forKey: .appleUserId)
        self.legalFirstNameOnId = try c.decodeIfPresent(String.self, forKey: .legalFirstNameOnId)
        self.legalLastNameOnId = try c.decodeIfPresent(String.self, forKey: .legalLastNameOnId)
        self.identityDocumentURL = try c.decodeIfPresent(String.self, forKey: .identityDocumentURL)
        self.identityVerificationSubmittedAt = try c.decodeIfPresent(Date.self, forKey: .identityVerificationSubmittedAt)
        self.verifiedHomeAddress = try c.decodeIfPresent(String.self, forKey: .verifiedHomeAddress)
        self.verifiedHomeLatitude = try c.decodeIfPresent(Double.self, forKey: .verifiedHomeLatitude)
        self.verifiedHomeLongitude = try c.decodeIfPresent(Double.self, forKey: .verifiedHomeLongitude)
        self.stripeIdentityVerified = try c.decodeIfPresent(Bool.self, forKey: .stripeIdentityVerified)
        self.stripeIdentityVerifiedAt = try c.decodeIfPresent(Date.self, forKey: .stripeIdentityVerifiedAt)
        self.stripeIdentityLastSessionId = try c.decodeIfPresent(String.self, forKey: .stripeIdentityLastSessionId)
        self.qualificationAttachments = try c.decodeIfPresent([QualificationAttachment].self, forKey: .qualificationAttachments)
        self.profileBannerImageData = try c.decodeIfPresent(Data.self, forKey: .profileBannerImageData)
        self.pronouns = try c.decodeIfPresent(String.self, forKey: .pronouns)
        self.bioAttachmentData = (try c.decodeIfPresent([Data].self, forKey: .bioAttachmentData)) ?? []
        self.parentEmail = try c.decodeIfPresent(String.self, forKey: .parentEmail)
        self.parentName = try c.decodeIfPresent(String.self, forKey: .parentName)
        self.parentApprovalToken = try c.decodeIfPresent(String.self, forKey: .parentApprovalToken)
        self.isParentalApproved = try c.decodeIfPresent(Bool.self, forKey: .isParentalApproved)
        self.parentApprovalDate = try c.decodeIfPresent(Date.self, forKey: .parentApprovalDate)
    }

    /// Age used for UI, parental consent, and eligibility (prefers date of birth when available).
    var resolvedAge: Int {
        if let dob = dateOfBirth {
            return Self.ageFromDateOfBirth(dob)
        }
        return age
    }

    static func ageFromDateOfBirth(_ dateOfBirth: Date, on referenceDate: Date = Date()) -> Int {
        let comps = Calendar.current.dateComponents([.year], from: dateOfBirth, to: referenceDate)
        return max(0, comps.year ?? 0)
    }

    var ageGroup: UserAgeGroup {
        return resolvedAge >= 18 ? .adult : .teen
    }
    
    var fullName: String {
        return "\(firstName) \(lastName)"
    }

    /// Best-effort city extraction from `verifiedHomeAddress`. Powers the
    /// city-scoped community feed; nil for users who haven't completed home
    /// verification yet (the feed should hide for them).
    /// Handles common Apple-geocoded formats:
    ///   "123 Main St, San Francisco, CA 94103, United States" → "San Francisco"
    ///   "San Francisco, CA 94103, USA"                        → "San Francisco"
    ///   "San Francisco, CA"                                   → "San Francisco"
    /// Strategy: find the first comma-separated part that matches the
    /// "STATE ZIP" / "STATE" pattern and treat the part right before it
    /// as the city.
    var homeCity: String? {
        guard let raw = verifiedHomeAddress?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        for (i, part) in parts.enumerated() {
            let tokens = part.split(separator: " ").map(String.init)
            // "STATE ZIP" — first token is a 2-letter state code.
            let firstIsState = tokens.first.map {
                $0.count == 2 && $0.allSatisfy { $0.isLetter }
            } ?? false
            if firstIsState, i > 0 {
                return parts[i - 1]
            }
        }
        // Fallback: most addresses have a trailing country. Prefer the
        // second-to-last part if there are ≥ 2 components.
        if parts.count >= 2 { return parts[parts.count - 2] }
        return parts.first
    }
    
    var displayUsername: String {
        if let username = username, !username.isEmpty {
            return "@\(username)"
        }
        return ""
    }
    
    /// True when Stripe Identity webhook marked the user verified (source of truth vs. local cache).
    var isStripeIdentityVerified: Bool {
        stripeIdentityVerified == true
    }
    
    var qualificationAttachmentsList: [QualificationAttachment] {
        qualificationAttachments ?? []
    }
    
    var hasBankAccount: Bool {
        return bankAccountConnected ?? false || stripeConnectActive ?? false
    }
    
    var canReceivePayments: Bool {
        return stripeConnectActive ?? false
    }
    
    // Username/name change restrictions
    var hasUsername: Bool {
        return username != nil && !(username?.isEmpty ?? true)
    }
    
    var canChangeUsername: Bool {
        guard let lastChange = lastUsernameChange else {
            return true // Never changed before, can change
        }
        let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
        return daysSinceLastChange >= 14
    }
    
    var daysUntilUsernameChange: Int {
        guard let lastChange = lastUsernameChange else {
            return 0 // Can change immediately
        }
        let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
        return max(0, 14 - daysSinceLastChange)
    }
    
    var canChangeName: Bool {
        guard let lastChange = lastNameChange else {
            return true // Never changed before, can change
        }
        let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
        return daysSinceLastChange >= 10
    }
    
    var daysUntilNameChange: Int {
        guard let lastChange = lastNameChange else {
            return 0 // Can change immediately
        }
        let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
        return max(0, 10 - daysSinceLastChange)
    }
    
    // Parental consent check (honor system)
    var needsParentalConsent: Bool {
        return resolvedAge < 18
    }

    // Backward-compatible alias used in some views/services.
    var needsParentalApproval: Bool {
        return needsParentalConsent
    }
    
    var hasParentalConsent: Bool {
        if resolvedAge >= 18 { return true }
        return parentalConsentGiven ?? false
    }

    // Backward-compatible alias used in navigation guards.
    var isFullyApproved: Bool {
        return hasParentalConsent
    }
}

struct Location: Codable {
    let latitude: Double
    let longitude: Double
    let address: String?
}

struct JobOpportunity: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let hirerId: String
    let location: Location
    let isVolunteer: Bool
    let skillsRequired: [String]
    let createdAt: Date
    let isActive: Bool
}
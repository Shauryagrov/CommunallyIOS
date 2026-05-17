//
//  ClickableUserProfile.swift
//  Communally
//
//  Reusable component for clickable user profiles with ratings
//

import SwiftUI

struct ClickableUserProfile: View {
    let userId: String
    let userName: String
    let userImageData: Data?
    let showRating: Bool
    let size: CGFloat
    
    @ObservedObject private var ratingManager = RatingManager.shared
    
    init(userId: String, userName: String, userImageData: Data?, showRating: Bool = true, size: CGFloat = 50) {
        self.userId = userId
        self.userName = userName
        self.userImageData = userImageData
        self.showRating = showRating
        self.size = size
    }
    
    var stats: UserRatingStats {
        ratingManager.getStats(forUser: userId)
    }
    
    var body: some View {
        NavigationLink(destination: UserProfileView(userId: userId).environmentObject(AuthenticationManager.shared)) {
            HStack(spacing: 12) {
                // Profile Photo
                if let imageData = userImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.5))
                                .foregroundColor(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    if showRating && stats.totalRatings > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 12))
                            
                            Text(String(format: "%.1f", stats.averageScore))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Text("(\(stats.totalRatings))")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Version (for cards)
struct CompactClickableProfile: View {
    let userId: String
    let userName: String
    let userImageData: Data?
    let size: CGFloat
    
    @ObservedObject private var ratingManager = RatingManager.shared
    
    init(userId: String, userName: String, userImageData: Data?, size: CGFloat = 40) {
        self.userId = userId
        self.userName = userName
        self.userImageData = userImageData
        self.size = size
    }
    
    var stats: UserRatingStats {
        ratingManager.getStats(forUser: userId)
    }
    
    var body: some View {
        NavigationLink(destination: UserProfileView(userId: userId).environmentObject(AuthenticationManager.shared)) {
            HStack(spacing: 8) {
                // Profile Photo
                if let imageData = userImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.5))
                                .foregroundColor(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .lineLimit(1)
                    
                    if stats.totalRatings > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 10))
                            
                            Text(String(format: "%.1f", stats.averageScore))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Profile Photo Only (for tight spaces)
struct ClickableProfilePhoto: View {
    let userId: String
    let userImageData: Data?
    let size: CGFloat
    let showRatingBadge: Bool
    
    @ObservedObject private var ratingManager = RatingManager.shared
    
    init(userId: String, userImageData: Data?, size: CGFloat = 50, showRatingBadge: Bool = false) {
        self.userId = userId
        self.userImageData = userImageData
        self.size = size
        self.showRatingBadge = showRatingBadge
    }
    
    var stats: UserRatingStats {
        ratingManager.getStats(forUser: userId)
    }
    
    var body: some View {
        NavigationLink(destination: UserProfileView(userId: userId).environmentObject(AuthenticationManager.shared)) {
            ZStack(alignment: .bottomTrailing) {
                // Profile Photo
                if let imageData = userImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.5))
                                .foregroundColor(.white)
                        )
                }
                
                // Rating Badge
                if showRatingBadge && stats.totalRatings > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text(String(format: "%.1f", stats.averageScore))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.yellow)
                    )
                    .offset(x: 4, y: 4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}


//
//  CommunityFeedView.swift
//  Communally
//
//  City-scoped photo feed accessed from the bottom dock's left mini-cell.
//  Users only see posts from neighbors with the same `homeCity` — keeps the
//  feed feeling like the small-town energy the app is going for.
//

import SwiftUI
import UIKit
import CoreLocation

struct CommunityFeedView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var feed = CommunityPostManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showComposer = false
    @State private var profilePresentingId: String?

    // Inline home-address gate (seekers don't pick a home address during
    // onboarding the way hirers do, so the community feed is their first
    // chance to set one). Bound to `AddressSearchWithMiniMap`.
    @State private var pickedAddressLine: String = ""
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var addressInlineError: String?
    @State private var isSavingAddress = false

    private var city: String? { authManager.currentUser?.homeCity }
    private var cityHeader: String {
        guard let city, !city.isEmpty else { return "Your community" }
        return "City of \(city)"
    }

    var body: some View {
        ZStack {
            CommunallyTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if city == nil {
                    addressGate
                } else if feed.posts.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(feed.posts) { post in
                                CommunityPostCard(
                                    post: post,
                                    isOwn: post.authorId == authManager.currentUser?.id,
                                    onTapAuthor: { profilePresentingId = post.authorId },
                                    onDelete: { delete(post) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
            }

            // Floating compose FAB
            if city != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showComposer = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(CommunallyTheme.primaryGreen.opacity(0.32))
                                    .frame(width: 68, height: 68)
                                    .blur(radius: 9)
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 60, height: 60)
                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2))
                                    .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
                                Image(systemName: "plus")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Share a community post")
                        .padding(.trailing, 22)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            CommunityPostComposerView()
                .environmentObject(authManager)
        }
        .sheet(item: Binding(
            get: { profilePresentingId.map(IdentifiableString.init) },
            set: { profilePresentingId = $0?.value }
        )) { wrapper in
            NavigationView {
                UserProfileView(userId: wrapper.value)
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            if let city, !city.isEmpty {
                feed.startListening(forCity: city)
            }
        }
        .onDisappear { feed.stopListening() }
    }

    // MARK: - Top bar (city label + back)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // City label — top-LEFT, per spec.
            VStack(alignment: .leading, spacing: 1) {
                Text("Community")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(CommunallyTheme.primaryGreen.opacity(0.85))
                Text(cityHeader)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CommunallyTheme.darkGray)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.94)))
                    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            }
            .accessibilityLabel("Close community feed")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(CommunallyTheme.primaryGreen.opacity(0.55))
            Text("Be the first to post")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(CommunallyTheme.darkGray)
            Text("Share what's happening in your community.\nOnly neighbors in \(city ?? "your city") can see it.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    /// Inline address picker shown when the signed-in user has no
    /// `homeCity`. Required for seekers, who skip the home-address step in
    /// onboarding (only hirers go through that). Saves to the User profile
    /// via `AuthenticationManager.setHomeAddress(...)` and the feed re-renders
    /// with the unlocked city the moment `currentUser` updates.
    private var addressGate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick your home")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text("Your community feed shows posts from neighbors in the same city. Drop a pin on your home so we know which city to scope it to — only the city name is shared, not the exact address.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)

                AddressSearchWithMiniMap(
                    addressLine: $pickedAddressLine,
                    resolvedCoordinate: $pickedCoordinate
                )
                .padding(.horizontal, 18)

                if let addressInlineError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red.opacity(0.85))
                        Text(addressInlineError)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    )
                    .padding(.horizontal, 18)
                }

                Button(action: saveAddress) {
                    HStack(spacing: 8) {
                        if isSavingAddress {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(isSavingAddress ? "Saving…" : "Unlock community feed")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(canSaveAddress ? 1.0 : 0.5)
                }
                .disabled(!canSaveAddress)
                .padding(.horizontal, 18)

                Spacer(minLength: 32)
            }
            .padding(.top, 12)
        }
    }

    private var canSaveAddress: Bool {
        pickedCoordinate != nil
            && !pickedAddressLine.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSavingAddress
    }

    private func saveAddress() {
        guard let coord = pickedCoordinate else { return }
        let line = pickedAddressLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else {
            addressInlineError = "Drop a pin on the map first."
            return
        }
        guard GeoAppConstants.isCoordinateInUS(coord) else {
            addressInlineError = "Pin must be inside the United States."
            return
        }
        isSavingAddress = true
        addressInlineError = nil
        authManager.setHomeAddress(line, coordinate: coord)
        // Give the published `currentUser` change a beat to land before the
        // listener kicks in — `homeCity` is recomputed on the next render.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isSavingAddress = false
            if let city = authManager.currentUser?.homeCity, !city.isEmpty {
                feed.startListening(forCity: city)
            }
        }
    }

    private func delete(_ post: CommunityPost) {
        feed.deletePost(post) { _ in /* listener will refresh */ }
    }
}

// MARK: - Card

private struct CommunityPostCard: View {
    let post: CommunityPost
    let isOwn: Bool
    let onTapAuthor: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onTapAuthor) {
                    Group {
                        if let data = post.authorImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle()
                                .fill(CommunallyTheme.primaryGreen.opacity(0.18))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(CommunallyTheme.primaryGreen)
                                )
                        }
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(post.authorName)'s profile")

                VStack(alignment: .leading, spacing: 1) {
                    Button(action: onTapAuthor) {
                        Text(post.authorName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)
                    }
                    .buttonStyle(.plain)
                    Text("\(post.cityDisplay) · \(post.timeAgo)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                }

                Spacer()

                if isOwn {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete post", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Photo is optional — text-only posts skip this block entirely.
            if let data = post.photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CommunallyTheme.primaryGreen.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .alert("Delete this post?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Your neighbors won't see it anymore. This can't be undone.")
        }
    }
}

/// Tiny `Identifiable` wrapper so we can drive a `.sheet(item:)` off a bare
/// String. Keeping it private keeps it from leaking into other modules.
private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

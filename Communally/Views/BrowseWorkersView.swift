//
//  BrowseWorkersView.swift
//  Communally
//
//  Hirer-facing "find a worker" experience. Lists job seekers in
//  the area so the hirer can browse profiles BEFORE posting a job —
//  the Rover/TaskRabbit model. The traditional post-and-wait flow
//  still works; this is an additive shortcut.
//
//  Why a list and not map pins:
//    Seeker location data isn't reliably present today (User.location
//    is optional and unverified). A list works with whatever data we
//    have. Once we tighten seeker-location signals we'll add map pins
//    in a follow-up — until then a list ranks workers by city +
//    completion count + rating, which is what Rover users actually
//    read anyway.
//
//  Wired into MapTabView for hirers as a sheet — see DashboardView.
//

import SwiftUI

struct BrowseWorkersView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var ratingManager = RatingManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedSkill: String? = nil
    @State private var selectedWorkerId: String? = nil

    /// All workers that are real job seekers, excluding the current
    /// user (hirers viewing themselves makes no sense).
    private var allWorkers: [User] {
        let currentUserId = authManager.currentUser?.id ?? ""
        return UserDatabase.shared.getAllUsers().filter { user in
            user.id != currentUserId
                && user.userType == .jobSeeker
                && user.hasCompletedOnboarding
        }
    }

    /// Distinct skills offered by seekers in the result set. Used to
    /// populate the filter chips at the top.
    private var availableSkills: [String] {
        var set = Set<String>()
        for w in allWorkers { for s in w.skills { set.insert(s) } }
        return set.sorted()
    }

    /// Workers filtered by current search/skill, then ranked by:
    /// completed jobs DESC → rating DESC → name. Rover-style "the
    /// most active locals first" ordering.
    ///
    /// Broken into discrete steps because Swift's type-checker times
    /// out on a single chained filter+sort closure with this many
    /// comparators (the dreaded "unable to type-check in reasonable
    /// time" error).
    private var rankedWorkers: [User] {
        let filtered = filterWorkers(allWorkers)
        return filtered.sorted(by: rankCompare)
    }

    private func filterWorkers(_ workers: [User]) -> [User] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workers.filter { user in
            if let sk = selectedSkill {
                let hasSkill = user.skills.contains { $0.caseInsensitiveCompare(sk) == .orderedSame }
                if !hasSkill { return false }
            }
            if q.isEmpty { return true }
            if user.fullName.lowercased().contains(q) { return true }
            if let bio = user.description, bio.lowercased().contains(q) { return true }
            return user.skills.contains { $0.lowercased().contains(q) }
        }
    }

    private func rankCompare(_ a: User, _ b: User) -> Bool {
        let aJobs = completedJobs(for: a.id)
        let bJobs = completedJobs(for: b.id)
        if aJobs != bJobs { return aJobs > bJobs }
        let aRating = ratingManager.averageRating(for: a.id)
        let bRating = ratingManager.averageRating(for: b.id)
        if aRating != bRating { return aRating > bRating }
        return a.fullName < b.fullName
    }

    private func completedJobs(for userId: String) -> Int {
        applicationManager.applications.filter {
            $0.applicantId == userId && $0.status == .completed
        }.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        searchBar
                        if !availableSkills.isEmpty { skillChips }

                        if rankedWorkers.isEmpty {
                            emptyState
                        } else {
                            countLabel
                            workerList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Find workers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CommunallyTheme.primaryGreen)
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: Binding(
                get: { selectedWorkerId.map(WorkerIdWrapper.init) },
                set: { selectedWorkerId = $0?.id }
            )) { wrapper in
                NavigationView {
                    UserProfileView(userId: wrapper.id)
                        .environmentObject(authManager)
                }
            }
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
            TextField("Search name, skill, or bio", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var skillChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedSkill = nil }
                } label: {
                    Text("All")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedSkill == nil ? .white : CommunallyTheme.darkGray)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selectedSkill == nil
                                           ? CommunallyTheme.primaryGreen
                                           : Color.white.opacity(0.7))
                        )
                }
                ForEach(availableSkills, id: \.self) { skill in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSkill = (selectedSkill == skill) ? nil : skill
                        }
                    } label: {
                        Text(skill)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedSkill == skill ? .white : CommunallyTheme.darkGray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selectedSkill == skill
                                               ? CommunallyTheme.primaryGreen
                                               : Color.white.opacity(0.7))
                            )
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var countLabel: some View {
        HStack {
            Text("\(rankedWorkers.count) \(rankedWorkers.count == 1 ? "worker" : "workers") found")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Text("Top first")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var workerList: some View {
        VStack(spacing: 10) {
            ForEach(rankedWorkers, id: \.id) { worker in
                Button {
                    selectedWorkerId = worker.id
                } label: {
                    workerCard(worker)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func workerCard(_ worker: User) -> some View {
        let jobs = completedJobs(for: worker.id)
        let avgRating = ratingManager.averageRating(for: worker.id)
        let ratingCount = ratingManager.ratings(forUserId: worker.id).count
        let isVerified = worker.stripeIdentityVerified == true

        return HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.18))
                    .frame(width: 56, height: 56)
                if let data = worker.profileImageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    Text(worker.fullName.prefix(1))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(CommunallyTheme.primaryGreen)
                }
            }

            // Body
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(worker.fullName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CommunallyTheme.darkGray)
                        .lineLimit(1)
                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(CommunallyTheme.primaryGreen)
                    }
                }

                HStack(spacing: 8) {
                    if ratingCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", avgRating))
                                .font(.system(size: 12, weight: .semibold))
                            Text("(\(ratingCount))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if jobs > 0 {
                        Text("• \(jobs) job\(jobs == 1 ? "" : "s") done")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if ratingCount == 0 && jobs == 0 {
                        Text("New worker")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CommunallyTheme.primaryGreen)
                    }
                }

                if let bio = worker.description, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                if !worker.skills.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(worker.skills.prefix(5), id: \.self) { skill in
                                Text(skill)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CommunallyTheme.primaryGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.10))
                                    )
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.gray.opacity(0.45))
                .padding(.top, 22)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 60)
            BambuMascotView(size: 130, pose: .thinking)
            Text(searchText.isEmpty && selectedSkill == nil
                 ? "No workers in your area yet"
                 : "No workers match that filter")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.7))
            Text(searchText.isEmpty && selectedSkill == nil
                 ? "As more neighbors sign up, they'll appear here. In the meantime, post a job and workers will find you."
                 : "Try clearing the filter or searching a different skill.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 2)
            Spacer(minLength: 40)
        }
    }
}

/// Tiny Identifiable wrapper so we can drive the .sheet(item:) modifier
/// off a plain String userId.
private struct WorkerIdWrapper: Identifiable {
    let id: String
}

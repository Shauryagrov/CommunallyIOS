//
//  MyApplicationsView.swift
//  Communally
//
//  View for job seekers to track their applications
//

import SwiftUI

struct MyApplicationsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @State private var selectedOpportunity: Opportunity?
    @State private var listFilter: SeekerAppFilter = .active

    private enum SeekerAppFilter: String, CaseIterable {
        case active  = "Active"
        case pending = "Pending"
        case removed = "Removed"
        case past    = "Past"
    }

    private var myApplications: [JobApplication] {
        guard let userId = authManager.currentUser?.id else { return [] }
        return applicationManager.getApplications(byUser: userId)
            .sorted { $0.appliedAt > $1.appliedAt }
    }

    private func liveOpportunity(for app: JobApplication) -> Opportunity? {
        opportunityManager.opportunities.first { $0.safeId == app.opportunityId }
    }

    private func isRemovedApplication(_ app: JobApplication) -> Bool {
        guard app.status == .pending || app.status == .accepted else { return false }
        guard let opp = liveOpportunity(for: app) else { return true }
        return opp.status == .cancelled || !opp.isActive
    }

    private var filteredApplications: [JobApplication] {
        switch listFilter {
        case .active:
            return myApplications.filter { app in
                guard app.status == .accepted else { return false }
                guard let opp = liveOpportunity(for: app) else { return false }
                return opp.status == .inProgress || opp.status == .open
            }
        case .pending:
            return myApplications.filter { app in
                guard app.status == .pending else { return false }
                guard let opp = liveOpportunity(for: app) else { return false }
                return opp.isActive && opp.status == .open
            }
        case .removed:
            return myApplications.filter { isRemovedApplication($0) }
        case .past:
            return myApplications.filter {
                $0.status == .rejected || $0.status == .completed || $0.status == .cancelled
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()

                if myApplications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Picker("Filter", selection: $listFilter) {
                                ForEach(SeekerAppFilter.allCases, id: \.self) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 8)

                            if filteredApplications.isEmpty {
                                Text("No \(listFilter.rawValue.lowercased()) applications.")
                                    .font(.subheadline)
                                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else {
                                LazyVStack(spacing: 10) {
                                    ForEach(filteredApplications) { application in
                                        ApplicationStatusCard(
                                            application: application,
                                            opportunity: getOpportunity(for: application),
                                            onTap: { selectedOpportunity = getOpportunity(for: application) }
                                        )
                                    }
                                }
                            }

                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("My Applications")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedOpportunity) { opportunity in
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
        }
    }

    // MARK: - Empty State
    /// Same minimal pattern as the Messages empty state — small icon +
    /// confident one-line label, vertically centered. No halo circles, no
    /// marketing paragraph.
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.55))
            Text("No applications yet")
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func getOpportunity(for application: JobApplication) -> Opportunity? {
        return opportunityManager.opportunities.first { $0.safeId == application.opportunityId }
    }
}

// MARK: - Application Status Card
struct ApplicationStatusCard: View {
    let application: JobApplication
    let opportunity: Opportunity?
    let onTap: () -> Void

    private var statusColor: Color {
        switch application.status {
        case .pending: return Color(red: 1.0, green: 0.7, blue: 0.2)
        case .accepted: return Color(red: 0.3, green: 0.8, blue: 0.4)
        case .rejected: return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .completed: return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .cancelled: return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
    }

    private var statusIcon: String {
        switch application.status {
        case .pending: return "clock.fill"
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "xmark.circle.fill"
        case .completed: return "star.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }

    private var statusText: String {
        switch application.status {
        case .pending: return "Pending Review"
        case .accepted: return "Accepted!"
        case .rejected: return "Not Selected"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    private var canSeeExactLocation: Bool {
        return application.status == .accepted || application.status == .completed
    }

    private var displayLocationName: String {
        guard let opp = opportunity else {
            return application.opportunityLocationNameSnapshot ?? ""
        }
        if canSeeExactLocation {
            return opp.locationName
        } else {
            let components = opp.locationName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count >= 2 {
                return components.suffix(2).joined(separator: ", ")
            }
            return opp.locationName
        }
    }

    private var displayTitle: String {
        opportunity?.title ?? application.opportunityTitleSnapshot ?? "Opportunity"
    }

    private var isArchivedOpportunity: Bool {
        opportunity == nil && application.opportunityTitleSnapshot != nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 5)
                    .padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        if let opp = opportunity ?? snapshotOpportunity {
                            ZStack {
                                Circle()
                                    .fill(statusColor.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                Image(systemName: iconForJobType(opp.jobType))
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(statusColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayTitle)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Image(systemName: canSeeExactLocation ? "mappin.circle.fill" : "location.circle.fill")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(statusColor)
                                    Text(displayLocationName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                        .lineLimit(1)
                                }
                                if isArchivedOpportunity {
                                    Text("Posting archived, application details saved")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Opportunity Unavailable")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                Text("This posting has been removed")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                            }
                        }
                        Spacer()
                    }

                    Rectangle()
                        .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                        .frame(height: 1)

                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(statusColor)
                            Text(statusText)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(statusColor)
                        }
                        Spacer()
                        Text("Applied \(application.timeAgo)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }

                    if application.status == .accepted, opportunity != nil {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            Text("The hirer has accepted you! Tap to view details and contact information.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                                .lineSpacing(3)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                        )
                    }
                }
                .padding(18)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: statusColor.opacity(0.15), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForJobType(_ type: String) -> String {
        return JobTypeHelper.icon(for: type)
    }

    private var snapshotOpportunity: Opportunity? {
        guard let title = application.opportunityTitleSnapshot,
              let jobType = application.opportunityJobTypeSnapshot,
              let locationName = application.opportunityLocationNameSnapshot else {
            return nil
        }
        return Opportunity(
            id: application.opportunityId,
            title: title,
            description: application.message ?? "",
            hirerId: application.hirerIdSnapshot ?? "",
            hirerName: application.hirerNameSnapshot ?? "",
            hirerImageData: nil,
            location: Location(latitude: 0, longitude: 0, address: locationName),
            locationName: locationName,
            isVolunteer: false,
            payAmount: nil,
            jobType: jobType,
            createdAt: application.appliedAt,
            isActive: false,
            applicantCount: 0,
            status: .cancelled,
            acceptedApplicantId: nil,
            scheduledDate: nil,
            scheduledTime: nil
        )
    }
}

#Preview {
    MyApplicationsView()
        .environmentObject(AuthenticationManager.shared)
}

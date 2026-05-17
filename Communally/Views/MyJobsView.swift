//
//  MyJobsView.swift
//  Communally
//
//  Beautiful, modern view for hirers to manage their jobs
//

import SwiftUI
import FirebaseAuth

struct MyJobsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var paymentManager = PaymentManager.shared
    @State private var showPostOpportunity = false
    @State private var selectedOpportunity: Opportunity?
    @State private var jobToDelete: Opportunity?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false
    @State private var listFilter: HirerJobsFilter = .all
    
    private enum HirerJobsFilter: String, CaseIterable {
        case all = "All"
        case action = "In Progress"
        case waiting = "Open"
        case done = "Done"
    }

    /// Prefer Firebase Auth UID so it matches `hirerId` on posted opportunities.
    private var effectiveHirerId: String? {
        Auth.auth().currentUser?.uid ?? authManager.currentUser?.id
    }

    private var userOpportunities: [Opportunity] {
        guard let userId = effectiveHirerId else { return [] }
        return opportunityManager.getUserOpportunities(userId: userId)
    }

    /// Live count from ApplicationManager — avoids stale `applicantCount` field on Opportunity docs.
    private func liveApplicantCount(for opportunity: Opportunity) -> Int {
        applicationManager.applications.filter {
            $0.opportunityId == opportunity.safeId && $0.status == .pending
        }.count
    }

    // Open jobs with applicants waiting for hirer review
    private var jobsNeedingReview: [Opportunity] {
        userOpportunities.filter { opp in
            opp.status == .open && liveApplicantCount(for: opp) > 0
        }
    }

    // Jobs in progress: accepted someone, not yet complete
    private var jobsInProgress: [Opportunity] {
        userOpportunities.filter { $0.status == .inProgress }
    }

    // Jobs waiting for applicants
    private var jobsWaiting: [Opportunity] {
        userOpportunities.filter { opp in
            opp.status == .open && liveApplicantCount(for: opp) == 0
        }
    }
    
    // Completed jobs
    private var jobsCompleted: [Opportunity] {
        userOpportunities.filter { $0.status == .completed }
    }
    
    // Badge count for tab (action items only)
    var actionItemCount: Int {
        jobsNeedingReview.count + jobsInProgress.count
    }
    
    private var filteredJobs: [Opportunity] {
        let sorted = userOpportunities.sorted { $0.createdAt > $1.createdAt }
        switch listFilter {
        case .all:
            return sorted.filter { $0.status != .completed && $0.status != .cancelled }
        case .action:
            let set = Set(jobsNeedingReview.map(\.safeId)).union(Set(jobsInProgress.map(\.safeId)))
            return sorted.filter { set.contains($0.safeId) }
        case .waiting:
            return sorted.filter { $0.status == .open && liveApplicantCount(for: $0) == 0 }
        case .done:
            return sorted.filter { $0.status == .completed }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        compactPostJobButton
                            .padding(.top, 8)
                        
                        if !userOpportunities.isEmpty {
                            Picker("Filter", selection: $listFilter) {
                                ForEach(HirerJobsFilter.allCases, id: \.self) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        if userOpportunities.isEmpty {
                            emptyState
                                .padding(.top, 40)
                        } else if filteredJobs.isEmpty {
                            Text("No jobs in this category.")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredJobs) { job in
                                    compactJobRow(job)
                                }
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("My Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPostOpportunity) {
                PostOpportunityView()
                    .environmentObject(authManager)
            }
            .sheet(item: $selectedOpportunity) { opportunity in
                // Route the in-progress row directly into the live ActiveJobView
                // (with this specific opportunity pinned) so a hirer with
                // multiple jobs running can tap the right one. Open jobs still
                // get the detail view so they can review applicants.
                if opportunity.status == .inProgress {
                    ActiveJobView(targetOpportunityId: opportunity.safeId)
                        .environmentObject(authManager)
                } else {
                    NavigationView {
                        OpportunityDetailView(opportunity: opportunity)
                            .environmentObject(authManager)
                    }
                }
            }
            .alert("Delete Job?", isPresented: $showDeleteConfirmation, presenting: jobToDelete) { job in
                Button("Cancel", role: .cancel) {
                    jobToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    deleteJob(job)
                }
            } message: { job in
                Text("Are you sure you want to delete \"\(job.title)\"? This cannot be undone.")
            }
            .alert("Can't Delete Job", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "This job can't be deleted.")
            }
        }
    }
    
    // MARK: - Delete Job
    private func deleteJob(_ opportunity: Opportunity) {
        if let reason = deleteRestrictionReason(for: opportunity) {
            deleteErrorMessage = reason
            showDeleteError = true
            jobToDelete = nil
            return
        }
        
        opportunityManager.deleteOpportunity(id: opportunity.safeId)
        jobToDelete = nil
    }
    
    private func deleteRestrictionReason(for opportunity: Opportunity) -> String? {
        guard let application = applicationManager.applications.first(where: {
            $0.opportunityId == opportunity.safeId && ($0.status == .accepted || $0.status == .completed)
        }) else {
            return nil
        }
        
        guard let payment = paymentManager.getPayment(for: application.id) else {
            return nil
        }
        
        switch payment.status {
        case .held:
            return "You can't delete this job because payment is already being held for it."
        case .released:
            return "You can't delete this job because the worker has already been paid."
        default:
            return nil
        }
    }
    
    // MARK: - Compact post button
    private var compactPostJobButton: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            showPostOpportunity = true
        }) {
            HStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Post a job")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                    Text("Hire local help")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.gray.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.14), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CommunallyTheme.lightGray, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func jobRowSubtitle(for job: Opportunity) -> String {
        switch job.status {
        case .open:
            let count = liveApplicantCount(for: job)
            if count > 0 {
                return "Review \(count) applicant\(count == 1 ? "" : "s")"
            }
            return "Waiting for applicants"
        case .inProgress:
            return "In progress — complete when done"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    private func canShowDelete(for job: Opportunity) -> Bool {
        if job.status == .completed || job.status == .cancelled { return false }
        if jobRowSubtitle(for: job) == "Completed" { return false }
        return true
    }
    
    private func compactJobRow(_ job: Opportunity) -> some View {
        OpportunityCompactListRow(
            opportunity: job,
            subtitle: jobRowSubtitle(for: job),
            subtitleHighlight: job.status == .open && liveApplicantCount(for: job) > 0,
            showApplicantBadge: job.status == .open && liveApplicantCount(for: job) > 0,
            onTap: {
                let impactLight = UIImpactFeedbackGenerator(style: .light)
                impactLight.impactOccurred()
                selectedOpportunity = job
            },
            onDelete: canShowDelete(for: job)
                ? {
                    let impactLight = UIImpactFeedbackGenerator(style: .light)
                    impactLight.impactOccurred()
                    jobToDelete = job
                    showDeleteConfirmation = true
                }
                : nil
        )
        .contextMenu {
            if canShowDelete(for: job) {
                Button(role: .destructive) {
                    jobToDelete = job
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Job", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CommunallyTheme.primaryGreen.opacity(0.12),
                                CommunallyTheme.primaryGreen.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "briefcase.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.75))
            }
            
            VStack(spacing: 14) {
                Text("No Jobs Yet")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                
                Text("Post your first job to get started!\n\nFind local help for any task.")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    MyJobsView()
        .environmentObject(AuthenticationManager.shared)
}

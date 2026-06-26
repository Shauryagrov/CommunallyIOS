//
//  ActiveJobView.swift
//  Communally
//
//  Full-screen in-progress job tracker shown for both seekers and hirers.
//

import SwiftUI
import MapKit

// MARK: - Map annotation model
private struct JobMapPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isDestination: Bool
}

// MARK: - Main view
struct ActiveJobView: View {
    /// When set (hirer side), pin the view to this specific opportunity.
    /// Lets a hirer with multiple in-progress jobs tap a row in MyJobs and
    /// land on the right one, instead of always seeing the most-recent one.
    /// Nil falls back to the legacy "first .inProgress" behavior.
    var targetOpportunityId: String? = nil

    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var appManager   = ApplicationManager.shared
    @ObservedObject private var oppManager   = OpportunityManager.shared
    @ObservedObject private var locManager   = LocationManager.shared
    @ObservedObject private var liveManager  = LiveLocationManager.shared
    /// Observed so the hirer's "Mark as Complete" gate unlocks the moment
    /// the seeker enters the Start PIN — the PIN service's listener fires
    /// instantly when /pins/{jobId} flips to verified, which is faster and
    /// more reliable than waiting for the seeker's LiveLocation write to
    /// propagate to our snapshot listener.
    @ObservedObject private var pinService   = PINVerificationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var journeyStatus: SeekerJourneyStatus = .notStarted
    @State private var elapsed: TimeInterval = 0
    @State private var elapsedTimer: Timer?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var showCompletion = false
    @State private var skipPINOnComplete = false
    @State private var completionApp: JobApplication?
    @State private var completionOpp: Opportunity?
    @State private var showOtherProfile = false
    @State private var otherProfileId: String?
    @State private var showReadyToStartConfirm = false
    @State private var pendingArrivedHirerName: String = ""
    @State private var pendingArrivedHirerId: String = ""
    @State private var pendingArrivedJobTitle: String = ""
    /// Drives the PIN-entry sheet the seeker sees when they tap Job Start.
    @State private var showJobStartPINEntry = false
    /// Drives the PIN-display sheet the hirer sees when they want to share
    /// the start PIN with the worker in person.
    @State private var showJobStartPINDisplay = false
    /// Seeker side: true once the seeker taps "I'm on my way" and starts
    /// broadcasting their live location to the hirer (until they arrive).
    @State private var isSharingLocation = false
    /// Road-network ETA (minutes) from MKDirections, hirer side. Falls back to
    /// the straight-line estimate when nil. Refreshed as the seeker's live
    /// position updates (~every 30s).
    @State private var roadETAMinutes: Int?

    private var userId: String? { authManager.currentUser?.id }
    private var isHirer: Bool { authManager.currentUser?.userType == .jobHirer }

    /// Uber-style timeline stage for the hirer: 0 Accepted · 1 On the way ·
    /// 2 Nearby · 3 Arrived. "Nearby" is derived from the seeker's live
    /// distance so it lights up without a new broadcast status.
    private var hirerTimelineStage: Int {
        if seekerHasStartedJob || liveManager.seekerJourneyStatus == .arrived { return 3 }
        if let snap = liveManager.seekerSnapshot, let opp = activeOpportunity {
            let dest = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
            if isValidCoord(dest) {
                return snap.coordinate.distanceMiles(to: dest) < 0.3 ? 2 : 1
            }
            return 1
        }
        return liveManager.seekerJourneyStatus == .onTheWay ? 1 : 0
    }

    /// True once the seeker has tapped "Job Start" (`.arrived`). The
    /// "Mark as Complete" button only appears after this gates true so neither
    /// side can flip a job to completed before it actually started.
    /// Hirer accepts EITHER the PIN-verified signal (instant via the
    /// /pins doc listener) OR the LiveLocation journey-status broadcast.
    /// Without the PIN fallback there was a real-time-sync lag where the
    /// seeker would tap Job Start, verify the PIN, and the hirer would
    /// have to close and reopen the In Progress sheet before the Complete
    /// button unlocked.
    private var seekerHasStartedJob: Bool {
        if isHirer {
            let jobId = activeOpportunity?.safeId ?? ""
            if !jobId.isEmpty,
               pinService.isVerified(jobId: jobId, type: .jobStart) {
                return true
            }
            return liveManager.seekerJourneyStatus == .arrived
        }
        return journeyStatus == .arrived
    }

    /// Combined gate: complete is allowed once both the seeker has tapped
    /// Job Start AND the scheduled end time has passed. Both sides see the
    /// same button visibility — pressability is what differs.
    private var canCompleteJob: Bool {
        seekerHasStartedJob && scheduledDurationElapsed
    }

    /// Helper card explaining why Mark as Complete is disabled. Renders an
    /// EmptyView when the button is enabled (SwiftUI layout skips it). Two
    /// reasons in priority order: job hasn't started yet, or it's started
    /// but the scheduled window hasn't run out.
    @ViewBuilder
    private var completionBlockerHint: some View {
        if !seekerHasStartedJob {
            jobNotStartedHint
        } else if !scheduledDurationElapsed {
            jobInProgressHint
        } else {
            EmptyView()
        }
    }

    /// True once the wall clock has reached the scheduled start time. Job
    /// Start cannot be tapped before this — without the gate, a seeker could
    /// clock in at 2 AM the day before, flip the status, and either show up
    /// at the wrong time or game the duration check. Re-evaluated every
    /// second via the elapsed timer. Legacy jobs without a start time fall
    /// through to true so behavior matches build 6.
    private var scheduledStartHasArrived: Bool {
        _ = elapsed
        guard let opp = activeOpportunity, let startAt = opp.scheduledStartDateTime else {
            return true
        }
        return Date() >= startAt
    }

    /// Human-readable countdown to the scheduled start. Nil when already past.
    private var remainingUntilScheduledStart: String? {
        _ = elapsed
        guard let opp = activeOpportunity, let startAt = opp.scheduledStartDateTime else { return nil }
        let remaining = startAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        if mins >= 1 {
            return secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    /// "9:00 AM – 11:00 AM" pulled straight off the Opportunity. Used by the
    /// scheduled-window banner that emphasises when the seeker is supposed
    /// to actually be at the job.
    private var scheduledWindowText: String? {
        guard let opp = activeOpportunity,
              let start = opp.scheduledTime, !start.isEmpty else { return nil }
        if let end = opp.scheduledEndTime, !end.isEmpty {
            return "\(start) – \(end)"
        }
        return start
    }

    /// True once the scheduled end time has passed. Hirer paid for the full
    /// window (e.g., 9–11 AM = $50) so we don't let either side mark complete
    /// before 11 AM and short-circuit the worker out of the work or the hirer
    /// out of the time. Re-evaluated every second via the elapsed timer.
    /// Legacy jobs without an end time fall through to "elapsed" so behavior
    /// matches build 6.
    private var scheduledDurationElapsed: Bool {
        _ = elapsed   // touch the per-second timer state so SwiftUI re-renders
        guard let opp = activeOpportunity, let endAt = opp.scheduledEndDateTime else {
            return true
        }
        return Date() >= endAt
    }

    /// Human-readable countdown to the scheduled end. Nil when already past.
    private var remainingUntilScheduledEnd: String? {
        _ = elapsed
        guard let opp = activeOpportunity, let endAt = opp.scheduledEndDateTime else { return nil }
        let remaining = endAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        if mins >= 1 {
            return secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    private var seekerApplication: JobApplication? {
        guard let uid = userId else { return nil }
        if isHirer {
            guard let opp = hirerOpportunity else { return nil }
            return appManager.applications.first { $0.opportunityId == opp.safeId && $0.status == .accepted }
        }
        return appManager.applications.first { $0.applicantId == uid && $0.status == .accepted }
    }

    private var hirerOpportunity: Opportunity? {
        guard let uid = userId, isHirer else { return nil }
        let mine = oppManager.opportunities.filter { $0.hirerId == uid && $0.status == .inProgress }
        // Caller pinned a specific job → show it. Used when a hirer with
        // multiple in-progress jobs taps a specific row in MyJobs.
        if let id = targetOpportunityId,
           let match = mine.first(where: { $0.safeId == id }) {
            return match
        }
        // Fallback: most-recently-started in-progress job.
        return mine
            .sorted { ($0.inProgressAt ?? $0.createdAt) > ($1.inProgressAt ?? $1.createdAt) }
            .first
    }

    /// Applicant id the hirer should attach `LiveLocationManager` to. Prefers
    /// the live `JobApplication` (most authoritative), falling back to the
    /// `Opportunity.acceptedApplicantId` snapshot when applications haven't
    /// landed in `appManager` yet — without this fallback, opening the In
    /// Progress sheet right after launch can miss the listener attach and the
    /// "Mark as Complete" gate never opens.
    private var hirerListenerApplicantId: String? {
        seekerApplication?.applicantId ?? activeOpportunity?.acceptedApplicantId
    }

    private var activeOpportunity: Opportunity? {
        if isHirer { return hirerOpportunity }
        guard let app = seekerApplication else { return nil }
        if let opp = oppManager.opportunities.first(where: { $0.safeId == app.opportunityId }) {
            return opp
        }
        // Fallback: synthesize from snapshot so the detail view always opens.
        // Worker can lose read access to the live opportunity once it leaves
        // `.open` (Firestore rules), so the lat/long snapshots taken at apply-
        // time are the only way to keep the in-progress map pin in sync with
        // the hirer's view. Coordinates are 0,0 for pre-snapshot applications;
        // `buildPins` already treats (0,0) as invalid.
        let snapshotLat = app.opportunityLocationLatitudeSnapshot ?? 0
        let snapshotLon = app.opportunityLocationLongitudeSnapshot ?? 0
        return Opportunity(
            id: app.opportunityId,
            title: app.opportunityTitleSnapshot ?? "Active Job",
            description: "",
            hirerId: app.hirerIdSnapshot ?? "",
            hirerName: app.hirerNameSnapshot ?? "",
            hirerImageData: nil,
            location: Location(latitude: snapshotLat, longitude: snapshotLon, address: app.opportunityLocationNameSnapshot ?? ""),
            locationName: app.opportunityLocationNameSnapshot ?? "",
            isVolunteer: false,
            payAmount: nil,
            jobType: app.opportunityJobTypeSnapshot ?? "",
            createdAt: app.appliedAt,
            isActive: false,
            applicantCount: 0,
            status: .inProgress,
            acceptedApplicantId: app.applicantId,
            scheduledDate: nil,
            scheduledTime: nil
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                if let opp = activeOpportunity, let app = seekerApplication {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            mapHeroCard(opp: opp, app: app)
                            statsRow(opp: opp)
                            if isStaleJob { staleJobBanner(app: app, opp: opp) }
                            // Hirer: Uber-style "where's my worker" timeline.
                            if isHirer {
                                JobStatusTimelineView(
                                    stage: hirerTimelineStage,
                                    etaText: hirerTimelineStage < 3 ? etaText(opp: opp) : nil
                                )
                            }
                            if !isHirer { journeyStatusCard }
                            // Hirer's "share the Start PIN with your worker" card.
                            // Only relevant before the seeker has tapped Job Start.
                            if isHirer && !seekerHasStartedJob {
                                hirerStartPINShareCard
                            }
                            safetyRow(app: app, opp: opp)
                            VStack(spacing: 8) {
                                completeButton(app: app, opp: opp)
                                    .disabled(!canCompleteJob)
                                    .opacity(canCompleteJob ? 1.0 : 0.55)
                                    .saturation(canCompleteJob ? 1.0 : 0.0)
                                completionBlockerHint
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                } else {
                    noActiveJobView
                }
            }
            .navigationTitle("In Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
        // The hirer's `seekerApplication` reads from `appManager.applications`,
        // which loads asynchronously. If onAppear fired before the listener
        // populated, `LiveLocationManager.startListening` was never called,
        // so `seekerJourneyStatus` stays nil → "Mark as Complete" never
        // unlocks even after the worker taps Job Start. Re-attach whenever
        // an applicant ID becomes available — preferring the live application,
        // falling back to the opportunity's `acceptedApplicantId` snapshot.
        .onChange(of: hirerListenerApplicantId) { _, applicantId in
            guard isHirer, let id = applicantId, !id.isEmpty else { return }
            LiveLocationManager.shared.startListening(seekerId: id)
        }
        // Recompute the road ETA each time the seeker's live position updates.
        .onChange(of: liveManager.seekerSnapshot?.updatedAt) { _, _ in
            if let opp = activeOpportunity { recomputeRoadETA(opp: opp) }
        }
        .alert("Ready to start the job?", isPresented: $showReadyToStartConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, I'm ready") { confirmArrivedReadyToStart() }
        } message: {
            Text("\(pendingArrivedHirerName) will get a notification to confirm too. The job starts when both of you tap ready and exchange the PIN.")
        }
        .sheet(isPresented: $showJobStartPINEntry) {
            // Seeker enters the 4-digit PIN the hirer reads off in person.
            // The `jobCoordinate` enforces a 200m geofence so people can't
            // clock in from across town.
            if let opp = activeOpportunity {
                PINEntryView(
                    jobId: opp.safeId,
                    type: .jobStart,
                    jobCoordinate: CLLocationCoordinate2D(
                        latitude: opp.location.latitude,
                        longitude: opp.location.longitude
                    ),
                    onSuccess: {
                        confirmArrivedReadyToStart()
                    }
                )
                .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showJobStartPINDisplay) {
            // Hirer reads this PIN aloud / shows the screen to the worker
            // when the worker arrives. Generated on-appear (see onAppear()).
            if let opp = activeOpportunity, let app = seekerApplication {
                NavigationView {
                    PINDisplayView(
                        jobId: opp.safeId,
                        type: .jobStart,
                        hirerId: opp.hirerId,
                        workerId: app.applicantId
                    )
                    .navigationTitle("Job Start PIN")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showJobStartPINDisplay = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showOtherProfile) {
            if let profileId = otherProfileId {
                NavigationView {
                    UserProfileView(userId: profileId)
                        .environmentObject(authManager)
                }
            }
        }
        .sheet(isPresented: $showCompletion, onDismiss: {
            skipPINOnComplete = false
            completionApp = nil
            completionOpp = nil
        }) {
            if let app = completionApp, let opp = completionOpp {
                JobCompletionSheet(opportunity: opp, application: app, skipPIN: skipPINOnComplete)
                    .environmentObject(authManager)
            }
        }
    }

    // MARK: - Hero card: map + job info merged
    private func mapHeroCard(opp: Opportunity, app: JobApplication) -> some View {
        let destCoord = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
        let pins = buildPins(destCoord: destCoord)

        return ZStack(alignment: .bottom) {
            // Map fills the card
            Map(coordinateRegion: $region, annotationItems: pins) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
                    if pin.isDestination {
                        destinationPin(emoji: jobEmoji(opp.jobType))
                    } else {
                        seekerPin
                    }
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            // Gradient overlay fading into job info
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 100)

                // Job info row
                HStack(spacing: 12) {
                    // Avatar — tappable to view the other person's profile
                    Button {
                        otherProfileId = isHirer ? app.applicantId : opp.hirerId
                        if otherProfileId?.isEmpty == false {
                            showOtherProfile = true
                        }
                    } label: {
                        Group {
                            if isHirer, let d = app.applicantImageData, let ui = UIImage(data: d) {
                                Image(uiImage: ui).resizable().scaledToFill()
                            } else if !isHirer, let d = opp.hirerImageData, let ui = UIImage(data: d) {
                                Image(uiImage: ui).resizable().scaledToFill()
                            } else {
                                Circle().fill(Color.white.opacity(0.3))
                                    .overlay(Image(systemName: "person.fill").foregroundStyle(.white))
                            }
                        }
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(opp.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: isHirer ? "person.fill" : "house.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            Text(isHirer ? app.applicantName : opp.hirerName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Directions button — only when we have a real coordinate
                    if isValidCoord(destCoord) {
                        Button {
                            openInMaps(coordinate: destCoord, name: opp.locationName)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Directions")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(CommunallyTheme.primaryGreen)
                                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.5), radius: 8, x: 0, y: 3)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 8)
                .background(Color.black.opacity(0.55))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .onAppear { fitMapRegion(destCoord: destCoord) }
    }

    // MARK: - Destination pin with emoji
    private func destinationPin(emoji: String) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.5), radius: 6, x: 0, y: 3)
                Text(emoji)
                    .font(.system(size: 22))
            }
            Triangle()
                .fill(CommunallyTheme.primaryGreen)
                .frame(width: 12, height: 8)
        }
    }

    private var seekerPin: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.25, green: 0.55, blue: 1.0))
                .frame(width: 34, height: 34)
                .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.5), radius: 6, x: 0, y: 3)
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Stats row
    private func statsRow(opp: Opportunity) -> some View {
        HStack(spacing: 10) {
            statCard(
                icon: "location.fill",
                iconColor: Color(red: 0.25, green: 0.55, blue: 1.0),
                value: distanceText(opp: opp),
                label: "Distance"
            )
            statCard(
                icon: "clock.arrow.circlepath",
                iconColor: CommunallyTheme.primaryGreen,
                value: etaText(opp: opp),
                label: "ETA"
            )
            statCard(
                icon: "timer",
                iconColor: Color(red: 0.95, green: 0.55, blue: 0.1),
                value: elapsedText,
                label: "On Job"
            )
        }
    }

    private func statCard(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CommunallyTheme.cardSurface)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Journey status (seeker only)
    /// Three states drive the visual:
    /// 1. Before scheduled start → big banner with countdown, button DISABLED
    /// 2. At/past start, not started yet → ready prompt, button ENABLED
    ///    (also flagged "running late" if 15+ min past start)
    /// 3. Started → solid green selected state, no countdown
    private var journeyStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            scheduledWindowBanner

            if journeyStatus != .arrived {
                seekerTravelControl
            }

            // Single Job Start button. Gated on the scheduled start time
            // having arrived — otherwise the seeker could clock in early and
            // skip the actual scheduled window.
            let isStarted = journeyStatus == .arrived
            let canStart = scheduledStartHasArrived || isStarted
            Button {
                if let opp = activeOpportunity {
                    pendingArrivedHirerName = opp.hirerName
                    pendingArrivedHirerId = opp.hirerId
                    pendingArrivedJobTitle = opp.title
                }
                // Open PIN entry. The geofence inside `PINEntryView` enforces
                // "you must actually be at the job location" — no more
                // clocking in from across town. On success, runs the existing
                // arrival flow (status flip + hirer notification).
                showJobStartPINEntry = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: SeekerJourneyStatus.arrived.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(SeekerJourneyStatus.arrived.displayText)
                        .font(.system(size: 13, weight: .bold, design: .default))
                }
                .foregroundStyle(isStarted ? .white : CommunallyTheme.darkGray.opacity(canStart ? 0.85 : 0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isStarted ? CommunallyTheme.primaryGreen : CommunallyTheme.cardSurface)
                        .shadow(color: isStarted ? CommunallyTheme.primaryGreen.opacity(0.3) : .black.opacity(0.04),
                                radius: isStarted ? 8 : 6, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)
            // Block re-tapping once started — every re-tap re-fired the
            // "just arrived" push to the hirer.
            .disabled(!canStart || isStarted)
            .opacity(canStart ? 1.0 : 0.55)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CommunallyTheme.cardSurface)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    /// Big bold banner that emphasises WHEN the seeker is supposed to be at
    /// the job — and changes color/copy based on whether they're early, on
    /// time, or late. Hidden gracefully for legacy jobs with no schedule.
    @ViewBuilder
    private var scheduledWindowBanner: some View {
        if let window = scheduledWindowText {
            let isStarted = journeyStatus == .arrived
            let countdown = remainingUntilScheduledStart
            let isLate = scheduledStartHasArrived && !isStarted
                && (activeOpportunity?.scheduledStartDateTime.map {
                    Date().timeIntervalSince($0) >= 15 * 60
                } ?? false)

            // Pick palette based on state
            let tint: Color = {
                if isStarted { return CommunallyTheme.primaryGreen }
                if isLate { return Color(red: 0.95, green: 0.45, blue: 0.10) } // orange
                if countdown != nil { return CommunallyTheme.darkGray.opacity(0.65) }
                return CommunallyTheme.primaryGreen
            }()

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: isStarted ? "checkmark.circle.fill"
                                      : isLate ? "exclamationmark.triangle.fill"
                                      : countdown != nil ? "clock.badge" : "hand.tap.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isStarted ? "Job in progress"
                         : isLate ? "You're running late"
                         : countdown != nil ? "Be there at \(activeOpportunity?.scheduledTime ?? "")"
                         : "Tap Job Start when you arrive")
                        .font(.system(size: 15, weight: .bold, design: .default))
                        .foregroundStyle(CommunallyTheme.darkGray)

                    Text(isStarted ? "Scheduled \(window)"
                         : isLate ? "Scheduled \(window) — get there ASAP and tap Job Start."
                         : countdown != nil ? "Scheduled \(window) · starts in \(countdown!)"
                         : "Scheduled \(window) — you can start now.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CommunallyTheme.darkGray.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tint.opacity(0.20), lineWidth: 1)
                    )
            )
        } else {
            Text("Update your status")
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Seeker travel control ("I'm on my way" live sharing)
    /// Opt-in live-location sharing while traveling to the job. Scoped to the
    /// hirer only (allowedViewers), foreground-only, and auto-stops when the
    /// seeker taps Job Start (.arrived). This is the seeker's consent step.
    @ViewBuilder
    private var seekerTravelControl: some View {
        if isSharingLocation {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sharing your live location")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(CommunallyTheme.textPrimary)
                    Text("\(activeOpportunity?.hirerName ?? "The hirer") can see you until you arrive.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CommunallyTheme.textSecondary)
                }
                Spacer()
                Button("Stop") { stopSharingLocation() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CommunallyTheme.primaryGreen.opacity(0.10))
            )
        } else {
            Button {
                startSharingLocation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("I'm on my way")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CommunallyTheme.primaryGreen)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func startSharingLocation() {
        guard let uid = userId, let opp = activeOpportunity else { return }
        let viewerId = opp.hirerId.isEmpty ? nil : opp.hirerId
        LiveLocationManager.shared.startSharing(userId: uid, status: .onTheWay, allowedViewerId: viewerId)
        withAnimation { isSharingLocation = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stopSharingLocation() {
        LiveLocationManager.shared.stopSharing()
        withAnimation { isSharingLocation = false }
    }

    // MARK: - Ready-to-start confirmation
    private func confirmArrivedReadyToStart() {
        let arrived = SeekerJourneyStatus.arrived
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            journeyStatus = arrived
        }
        if let uid = userId {
            // Pass the hirer ID as the only allowed live-location viewer.
            // Backed by the `liveLocations/{userId}` Firestore rule which
            // gates reads on `allowedViewers` to prevent any other signed-in
            // user from pulling this seeker's live GPS coordinates.
            let viewerId = pendingArrivedHirerId.isEmpty ? nil : pendingArrivedHirerId
            LiveLocationManager.shared.updateJourneyStatus(arrived, userId: uid, allowedViewerId: viewerId)
        }

        // Notify the hirer that the seeker has arrived and is ready. The
        // hirer still has to confirm (via the existing PIN exchange) before
        // the job flips to "on job" / in-progress — the PIN entry is the
        // hirer's "yes I'm ready too" confirmation.
        guard !pendingArrivedHirerId.isEmpty,
              let app = seekerApplication else { return }
        let seekerName = authManager.currentUser?.fullName ?? "Your worker"
        let arrivedNotification = AppNotification(
            id: nil,
            type: .applicationAccepted,
            title: "\(seekerName) just arrived",
            message: "They're ready to start \"\(pendingArrivedJobTitle)\". Open the job and share your PIN to begin.",
            userId: pendingArrivedHirerId,
            relatedId: app.opportunityId,
            senderName: seekerName,
            senderImageData: authManager.currentUser?.profileImageData,
            createdAt: Date(),
            isRead: false
        )
        NotificationManager.shared.saveNotification(arrivedNotification)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Safety row
    /// Visible to the hirer while the seeker is en route. Tapping opens the
    /// PIN display so the hirer can show / read the 4-digit Start PIN to the
    /// worker in person — pairs with the geofenced PIN entry on the seeker
    /// side to confirm "yes, this person is actually here."
    private var hirerStartPINShareCard: some View {
        Button {
            showJobStartPINDisplay = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Start PIN")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text("Share with your worker when they arrive")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.62))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CommunallyTheme.cardSurface)
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CommunallyTheme.primaryGreen.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func safetyRow(app: JobApplication, opp: Opportunity) -> some View {
        HStack(spacing: 10) {
            safetyButton(icon: "location.fill", label: "Share Location",
                         color: Color(red: 0.25, green: 0.55, blue: 1.0)) {
                shareLocation(app: app, opp: opp)
            }
            // Direct dial to 911 — iOS shows its own native "Call 911?"
            // confirmation, so we deliberately don't wrap this in another
            // in-app dialog. In an emergency we want one tap, not a menu.
            // The dedicated assault-report flow still lives elsewhere; this
            // button is only for "call emergency services right now."
            safetyButton(icon: "phone.fill", label: "Call 911", color: .red) {
                if let url = URL(string: "tel:911") { UIApplication.shared.open(url) }
            }
        }
    }

    private func safetyButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(label).font(.system(size: 13, weight: .bold, design: .default))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stale job banner
    private func staleJobBanner(app: JobApplication, opp: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(red: 0.90, green: 0.55, blue: 0.10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("This job has been active for \(elapsedText)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text(isHirer
                         ? "Did the worker finish? Mark it complete or contact them."
                         : "Did you finish? Message the hirer so they can wrap it up.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Only the hirer can write to the opportunity doc (firestore.rules
            // requires hirerId == auth.uid). Showing this button to the seeker
            // produced silent permission-denied writes that stranded the
            // opportunity in `.inProgress` while the application went to
            // `.completed`. Hirer-only escape hatch from now on.
            if isHirer {
                Button {
                    completionApp = app
                    completionOpp = opp
                    skipPINOnComplete = true
                    showCompletion = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                        Text("Mark as Complete")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.90, green: 0.55, blue: 0.10))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.90, green: 0.55, blue: 0.10).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 0.90, green: 0.55, blue: 0.10).opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// Shown after Job Start but before the scheduled end time. The hirer
    /// paid for the full window — we hold the complete button until then so
    /// the worker actually delivers the time, and the hirer doesn't get
    /// short-changed either. Live ticks via the elapsed timer.
    private var jobInProgressHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                if let remaining = remainingUntilScheduledEnd {
                    Text("Job in progress — \(remaining) until you can mark complete")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                } else {
                    Text("Job in progress")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                }
                Text("The job runs the full scheduled window before either side can complete it.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CommunallyTheme.primaryGreen.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CommunallyTheme.primaryGreen.opacity(0.18), lineWidth: 1)
                )
        )
    }

    /// Shown in place of the complete button before the seeker taps Job Start.
    /// Tells whoever's looking why the action isn't available yet.
    private var jobNotStartedHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
            Text(isHirer
                 ? "You'll be able to mark this complete once the worker taps Job Start."
                 : "Tap Job Start above when you're at the location. Mark as Complete will appear after.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CommunallyTheme.darkGray.opacity(0.04))
        )
    }

    // MARK: - Complete button
    private func completeButton(app: JobApplication, opp: Opportunity) -> some View {
        Button {
            completionApp = app
            completionOpp = opp
            showCompletion = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .semibold))
                Text("Mark as Complete").font(.system(size: 17, weight: .bold, design: .default))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: CommunallyTheme.buttonHeight)
            .background(
                LinearGradient(colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - No active job
    private var noActiveJobView: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(CommunallyTheme.primaryGreen.opacity(0.5))
            Text("No active job right now")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray)
            Text("When you start a job it will appear here with live tracking and safety tools.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Lifecycle
    private func onAppear() {
        startElapsedTimer()
        if isHirer, let id = hirerListenerApplicantId {
            LiveLocationManager.shared.startListening(seekerId: id)
            if let opp = activeOpportunity { recomputeRoadETA(opp: opp) }
        }
        // Hirer auto-generates the Job Start PIN once per active job, exactly
        // the way `JobCompletionView` already does for the completion PIN.
        // Seeker reads this PIN off the hirer's screen (or hears it spoken)
        // when they arrive — couples the in-person handoff with the
        // 200m geofence enforced inside `PINEntryView`.
        if isHirer,
           let opp = activeOpportunity,
           let app = seekerApplication {
            PINVerificationService.shared.observePIN(jobId: opp.safeId, type: .jobStart)
            PINVerificationService.shared.fetchPIN(jobId: opp.safeId, type: .jobStart) { pin in
                if pin == nil {
                    _ = PINVerificationService.shared.generatePIN(
                        jobId: opp.safeId,
                        type: .jobStart,
                        hirerId: opp.hirerId,
                        workerId: app.applicantId
                    )
                }
            }
        }
        // Seeker: rehydrate `journeyStatus` from the persisted live-location
        // doc so re-opening the screen after tapping Job Start doesn't show a
        // fresh "Job Start" button and let them double-trigger the flow.
        // Local @State alone resets every mount; the hirer gets persistence
        // for free via their listener, but the seeker had no equivalent.
        if !isHirer, let uid = userId {
            LiveLocationManager.shared.fetchOwnJourneyStatus(userId: uid) { status in
                if let status, status == .arrived {
                    DispatchQueue.main.async { self.journeyStatus = status }
                }
            }
        }
        if let opp = activeOpportunity {
            let coord = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
            fitMapRegion(destCoord: coord)
        }
    }

    private func onDisappear() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        if isHirer { LiveLocationManager.shared.stopListening() }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let acceptedAt = seekerApplication?.acceptedAt {
                elapsed = Date().timeIntervalSince(acceptedAt)
            }
        }
    }

    private var isStaleJob: Bool { elapsed > 5 * 3600 }

    private func isValidCoord(_ coord: CLLocationCoordinate2D) -> Bool {
        // (0,0) is the null-island fallback used when the opportunity is built from snapshots
        abs(coord.latitude) > 0.001 || abs(coord.longitude) > 0.001
    }

    private var elapsedText: String {
        let total = Int(elapsed)
        let days = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if days > 0 { return "\(days)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func distanceText(opp: Opportunity) -> String {
        let destCoord = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
        guard isValidCoord(destCoord) else { return "--" }
        if isHirer, let snap = liveManager.seekerSnapshot {
            let miles = snap.coordinate.distanceMiles(to: destCoord)
            return miles < 0.1 ? "Here" : String(format: "%.1f mi", miles)
        }
        guard let myLoc = locManager.location else { return "--" }
        let miles = myLoc.coordinate.distanceMiles(to: destCoord)
        return miles < 0.1 ? "Here" : String(format: "%.1f mi", miles)
    }

    private func etaText(opp: Opportunity) -> String {
        let destCoord = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
        guard isValidCoord(destCoord) else { return "--" }
        if isHirer, let snap = liveManager.seekerSnapshot {
            // Prefer the MKDirections road ETA; fall back to straight-line.
            if let road = roadETAMinutes { return "\(road) min" }
            return "\(snap.coordinate.etaMinutes(to: destCoord)) min"
        }
        guard let myLoc = locManager.location else { return "--" }
        return "\(myLoc.coordinate.etaMinutes(to: destCoord)) min"
    }

    /// Hirer side: ask MKDirections for a real road-network ETA from the
    /// seeker's live position to the job. Throttled naturally by the seeker's
    /// 30s broadcast cadence. Silent no-op / fallback on any failure.
    private func recomputeRoadETA(opp: Opportunity) {
        guard isHirer, let snap = liveManager.seekerSnapshot else { return }
        let dest = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
        guard isValidCoord(dest) else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: snap.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .automobile
        MKDirections(request: request).calculate { response, _ in
            guard let seconds = response?.routes.first?.expectedTravelTime else { return }
            DispatchQueue.main.async {
                self.roadETAMinutes = max(1, Int(seconds / 60))
            }
        }
    }

    private func buildPins(destCoord: CLLocationCoordinate2D) -> [JobMapPin] {
        var pins: [JobMapPin] = []
        if isValidCoord(destCoord) {
            pins.append(JobMapPin(id: "dest", coordinate: destCoord, isDestination: true))
        }
        if isHirer, let snap = liveManager.seekerSnapshot {
            pins.append(JobMapPin(id: "seeker", coordinate: snap.coordinate, isDestination: false))
        } else if !isHirer, let myLoc = locManager.location {
            pins.append(JobMapPin(id: "me", coordinate: myLoc.coordinate, isDestination: false))
        }
        return pins
    }

    private func fitMapRegion(destCoord: CLLocationCoordinate2D) {
        var coords: [CLLocationCoordinate2D] = []
        if isValidCoord(destCoord) { coords.append(destCoord) }
        if isHirer, let snap = liveManager.seekerSnapshot { coords.append(snap.coordinate) }
        else if !isHirer, let myLoc = locManager.location { coords.append(myLoc.coordinate) }
        guard coords.count > 1 else {
            if let center = coords.first {
                region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))
            }
            return
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        region = MKCoordinateRegion(center: center,
                                    span: MKCoordinateSpan(latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.5),
                                                           longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.5)))
    }

    private func openInMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func shareLocation(app: JobApplication, opp: Opportunity) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        LocationSharingService.shared.shareLocation(from: root,
                                                     userName: authManager.currentUser?.fullName ?? "Me",
                                                     jobTitle: opp.title)
    }

    private func jobEmoji(_ jobType: String) -> String {
        switch jobType.lowercased() {
        case let t where t.contains("garden"): return "🌿"
        case let t where t.contains("pet"):    return "🐾"
        case let t where t.contains("tutor"):  return "📚"
        case let t where t.contains("mov"):    return "📦"
        case let t where t.contains("paint"):  return "🎨"
        case let t where t.contains("baby"):   return "👶"
        case let t where t.contains("event"):  return "🎉"
        case let t where t.contains("clean"):  return "🧹"
        default:                               return "💼"
        }
    }
}

// MARK: - Triangle shape for map pin
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - Compact banner shown above tab bar in DashboardView
struct ActiveJobBannerCard: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var appManager  = ApplicationManager.shared
    @ObservedObject private var oppManager  = OpportunityManager.shared
    @ObservedObject private var liveManager = LiveLocationManager.shared
    @ObservedObject private var locManager  = LocationManager.shared

    @State private var elapsed: TimeInterval = 0
    @State private var elapsedTimer: Timer?
    @State private var showFullView = false
    @State private var pulse = false

    private var isHirer: Bool { authManager.currentUser?.userType == .jobHirer }
    private var userId: String? { authManager.currentUser?.id }

    private var seekerApplication: JobApplication? {
        guard let uid = userId else { return nil }
        if isHirer {
            guard let opp = hirerOpportunity else { return nil }
            return appManager.applications.first { $0.opportunityId == opp.safeId && $0.status == .accepted }
        }
        return appManager.applications.first { $0.applicantId == uid && $0.status == .accepted }
    }

    private var hirerOpportunity: Opportunity? {
        guard let uid = userId, isHirer else { return nil }
        return oppManager.opportunities
            .filter { $0.hirerId == uid && $0.status == .inProgress }
            .sorted { ($0.inProgressAt ?? $0.createdAt) > ($1.inProgressAt ?? $1.createdAt) }
            .first
    }

    private var activeOpportunity: Opportunity? {
        if isHirer { return hirerOpportunity }
        guard let app = seekerApplication else { return nil }
        // Prefer full opportunity data when available.
        if let opp = oppManager.opportunities.first(where: { $0.safeId == app.opportunityId }) {
            return opp
        }
        // Always synthesise a display-only opportunity so the banner shows even
        // when the in-progress opp hasn't landed in oppManager yet, or when
        // opportunityTitleSnapshot is nil (applications created before that field was added).
        let title = app.opportunityTitleSnapshot ?? "Active Job"
        let locationName = app.opportunityLocationNameSnapshot ?? ""
        return Opportunity(
            id: app.opportunityId,
            title: title,
            description: "",
            hirerId: app.hirerIdSnapshot ?? "",
            hirerName: app.hirerNameSnapshot ?? "",
            hirerImageData: nil,
            location: Location(latitude: 0, longitude: 0, address: locationName),
            locationName: locationName,
            isVolunteer: false,
            payAmount: nil,
            jobType: app.opportunityJobTypeSnapshot ?? "",
            createdAt: app.appliedAt,
            isActive: false,
            applicantCount: 0,
            status: .inProgress,
            acceptedApplicantId: app.applicantId,
            scheduledDate: nil,
            scheduledTime: nil
        )
    }

    var body: some View {
        Group {
            if let opp = activeOpportunity {
                Button { showFullView = true } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.25))
                                .frame(width: 28, height: 28)
                                .scaleEffect(pulse ? 1.4 : 1.0)
                                .opacity(pulse ? 0.0 : 0.5)
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                        }
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                pulse = true
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(opp.title)
                                .font(.system(size: 14, weight: .bold, design: .default))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(subtitleText(opp: opp))
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(elapsedText)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("tap to view")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.45), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showFullView) {
                    ActiveJobView().environmentObject(authManager)
                }
                .onAppear {
                    startElapsedTimer()
                    if isHirer, let id = bannerListenerApplicantId {
                        LiveLocationManager.shared.startListening(seekerId: id)
                    }
                }
                .onDisappear {
                    elapsedTimer?.invalidate()
                    elapsedTimer = nil
                }
                // Same race the In Progress sheet has: when the banner mounts
                // before `appManager.applications` populates, the `onAppear`
                // attach above no-ops and the hirer's "Mark as Complete" gate
                // never opens. Re-attach as soon as we know an applicant id.
                .onChange(of: bannerListenerApplicantId) { _, applicantId in
                    guard isHirer, let id = applicantId, !id.isEmpty else { return }
                    LiveLocationManager.shared.startListening(seekerId: id)
                }
            }
        }
        // Runs unconditionally so seekers always trigger a listener boot, even
        // before their accepted application has landed in appManager.applications.
        .task {
            if !isHirer, let uid = userId, appManager.applications.isEmpty {
                ApplicationManager.shared.startListening(for: uid)
            }
        }
    }

    /// Same fallback chain as `ActiveJobView.hirerListenerApplicantId`: prefer
    /// the live application, fall back to the opportunity snapshot.
    private var bannerListenerApplicantId: String? {
        seekerApplication?.applicantId ?? activeOpportunity?.acceptedApplicantId
    }

    private func subtitleText(opp: Opportunity) -> String {
        // Synthetic fallback opportunities have lat/lon 0,0 — skip distance calc.
        guard opp.location.latitude != 0 || opp.location.longitude != 0 else {
            return opp.locationName
        }
        let destCoord = CLLocationCoordinate2D(latitude: opp.location.latitude, longitude: opp.location.longitude)
        if isHirer, let snap = liveManager.seekerSnapshot {
            return "\(snap.journeyStatus.displayText) · \(snap.coordinate.etaMinutes(to: destCoord)) min away"
        } else if !isHirer, let myLoc = locManager.location {
            let miles = myLoc.coordinate.distanceMiles(to: destCoord)
            if miles < 0.1 { return "You're at the location" }
            return String(format: "%.1f mi · %d min away", miles, myLoc.coordinate.etaMinutes(to: destCoord))
        }
        return opp.locationName
    }

    private var elapsedText: String {
        let total = Int(elapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let acceptedAt = seekerApplication?.acceptedAt {
                elapsed = Date().timeIntervalSince(acceptedAt)
            }
        }
    }
}

//
//  PostOpportunityView.swift
//  Communally
//
//  Created for minimalistic job posting
//

import SwiftUI
import MapKit
import CoreLocation
import FirebaseAuth

struct PostOpportunityView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @FocusState private var isPayFieldFocused: Bool
    
    // Location
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var locationName: String = ""
    @State private var showLocationPicker = false
    
    // Pay (always paid now - no volunteer option)
    @State private var payAmount: String = ""
    
    // Job Type
    @State private var selectedJobType: OpportunityCategory?
    @State private var jobDescription: String = ""
    
    // Date and Time. Times default to 9 AM start / 11 AM end on today, both
    // hard-capped to the platform's 7 AM – 7 PM window on the chosen date.
    @State private var selectedDate = Date()
    @State private var selectedTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var selectedEndTime: Date = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date()) ?? Date()

    /// Hard cap: every job must start no earlier than 7 AM and end no later
    /// than 7 PM on the same calendar day. Drives both DatePicker `in:` ranges
    /// so the user can't even scroll past the bounds.
    ///
    /// 🚧 TESTING MODE — flip `testingMode` back to `false` before App Store
    /// submission. While true: lead time drops to 5 min, minimum job duration
    /// drops to 5 min, and the 7 AM–7 PM curfew is lifted so the day picker
    /// covers the full 24-hour window. The "make sense" coupling between
    /// start, end, and minimum-duration is preserved — end is still forced
    /// to land after start, and the min-duration check still fires.
    ///
    /// PRODUCTION SETTING: must be `false` for App Store submission. If you
    /// flip this back to true for further testing, ALSO flip the matching
    /// flag in OpportunityDetailView.RescheduleOpportunitySheet — both files
    /// must agree to avoid the post-flow and the reschedule-flow disagreeing
    /// on what's a valid time.
    // Production setting. Keep `false` for App Store. If you flip this true
    // for local testing, also flip the matching flag in
    // OpportunityDetailView.RescheduleOpportunitySheet so the two flows agree.
    private static let testingMode: Bool = false

    private static var dayStartHour: Int { testingMode ? 0 : 7 }
    private static var dayEndHour: Int { testingMode ? 23 : 19 }
    /// In testing mode we also push the end-of-day cap to 23:59 instead of
    /// the top of the hour so a job started at 23:55 can still legally end
    /// inside the same calendar day (5-min minimum + 23:55 start = 0:00,
    /// which we round up to 23:59 to keep the window non-empty).
    private static var dayEndMinute: Int { testingMode ? 59 : 0 }
    /// Days added to `selectedDate` before applying `dayEndHour`. 0 = same-day
    /// (production behavior — jobs end no later than 7 PM on the chosen day).
    private static let dayEndDayOffset: Int = 0

    /// Workers need a real heads-up before being expected on-site. 30 minutes
    /// is the minimum gap between "post now" and the scheduled start.
    /// Testing mode: 5 minutes so the dev can post a job and immediately
    /// step through the accept → start → complete flow.
    private static var minimumLeadTimeSeconds: TimeInterval { testingMode ? 2 * 60 : 30 * 60 }
    /// Floor on job length so the per-hour rate floor / safety + payment
    /// flows aren't gamed with sub-minute "jobs." Testing mode drops this
    /// to 2 minutes so the dev can step through the full start → complete
    /// flow without sitting on the screen for 5+ minutes per test cycle.
    private static var minimumJobDurationSeconds: TimeInterval { testingMode ? 2 * 60 : 30 * 60 }
    
    // Error handling
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Review sheet
    @State private var showReviewSheet = false
    @State private var showJobTypeSheet = false

    private var payAmountInt: Int? {
        Int(payAmount)
    }

    /// Hours covered by start → end. The hirer enters a total, so we derive the
    /// implied hourly rate to validate against per-category $/hr floors.
    private var hoursDuration: Double {
        let secs = max(0, selectedEndTime.timeIntervalSince(selectedTime))
        return secs / 3600
    }

    /// Implied hourly rate from total pay ÷ hours, or nil if either is missing.
    private var derivedHourlyRate: Double? {
        guard let total = payAmountInt, total > 0, hoursDuration > 0 else { return nil }
        return Double(total) / hoursDuration
    }

    /// Valid when a category is chosen and the implied hourly rate falls in
    /// the category's $/hr range. Hirer enters total; we enforce per-hour.
    private var isPayAmountValid: Bool {
        guard let cat = selectedJobType, let hourly = derivedHourlyRate else { return false }
        return hourly >= Double(cat.categoryPayMinimumUSD)
            && hourly <= Double(cat.categoryPayMaximumUSD)
    }
    
    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle("Post Opportunity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(CommunallyTheme.darkGray)
                    }
                }
                .sheet(isPresented: $showLocationPicker) {
                    LocationPickerView(
                        selectedLocation: $selectedLocation,
                        locationName: $locationName,
                        isPresented: $showLocationPicker,
                        homeCoordinate: {
                            guard let lat = authManager.currentUser?.verifiedHomeLatitude,
                                  let lon = authManager.currentUser?.verifiedHomeLongitude
                            else { return nil }
                            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        }()
                    )
                }
                .sheet(isPresented: $showJobTypeSheet) {
                    jobTypePickerSheet
                }
                .sheet(isPresented: $showReviewSheet) {
                    if let selectedJobType = selectedJobType {
                        ReviewOpportunityView(
                            jobType: selectedJobType,
                            locationName: locationName,
                            selectedDate: selectedDate,
                            selectedTime: selectedTime,
                            selectedEndTime: selectedEndTime,
                            isVolunteer: false, // Everything is paid now
                            payAmount: payAmount,
                            jobDescription: jobDescription,
                            onConfirm: {
                                showReviewSheet = false
                                postOpportunity()
                            },
                            onCancel: {
                                showReviewSheet = false
                            }
                        )
                    }
                }
                .alert("Can't Post This Opportunity", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
        }
    }
    
    private var mainContent: some View {
        ZStack {
            CommunallyTheme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 12) {
                fieldsCard
                postButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .onChange(of: selectedJobType) { _, newType in
            if let cat = newType, payAmount.isEmpty {
                // Suggested $/hr × default duration → reasonable starting total.
                let hours = max(1, Int(hoursDuration.rounded()))
                payAmount = "\(cat.suggestedPayUSD * hours)"
            }
        }
        .onAppear {
            // Default times in @State may already be in the past by the time
            // the user opens the form (e.g., 9 AM defaults at 9:13 PM). Snap
            // them forward so the picker opens on a valid moment.
            snapTimesIntoValidWindow()
        }
    }

    // MARK: - Compact single-card form

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            locationRow
            Divider().padding(.horizontal, 16)
            dateTimeRow
            Divider().padding(.horizontal, 16)
            payRow
            payHintRow
            Divider().padding(.horizontal, 16)
            jobTypeRow
            Divider().padding(.horizontal, 16)
            descriptionRow
        }
        .frame(maxHeight: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Soft primaryGreen halo behind the white card for a subtle glow that
        // ties the form into the green background gradient.
        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.18), radius: 22, x: 0, y: 10)
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen.opacity(0.30),
                            CommunallyTheme.primaryGreen.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    /// Live inline pay status — clears confusion when the typed amount is
    /// outside the platform minimum or the category-specific minimum.
    /// Renders immediately below the pay row; takes the user's current input
    /// + the picked job type into account.
    @ViewBuilder
    private var payHintRow: some View {
        let info = payHintInfo()
        if let info {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: info.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(info.color)
                    .padding(.top, 1)
                Text(info.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(info.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 0)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: payAmount)
        }
    }

    private struct PayHintInfo {
        let icon: String
        let text: String
        let color: Color
    }

    /// Returns the inline pay-row hint, or nil if the value is fine.
    /// Hirer enters total; the implied hourly (total ÷ hours) must clear both
    /// platform and category $/hr floors. Communally derives that math so the
    /// hirer just thinks in dollars-for-the-job.
    private func payHintInfo() -> PayHintInfo? {
        let platformMin = OpportunityCategory.platformPayMinimumUSD
        let platformMax = OpportunityCategory.platformPayMaximumUSD

        // Empty input: show the suggested total + the platform/category floor.
        if payAmount.isEmpty {
            if let cat = selectedJobType {
                let hours = max(1, Int(hoursDuration.rounded()))
                let suggestedTotal = cat.suggestedPayUSD * hours
                return PayHintInfo(
                    icon: "info.circle.fill",
                    text: "Suggested total ~$\(suggestedTotal) for \(cat.rawValue) (min $\(cat.categoryPayMinimumUSD)/hr).",
                    color: CommunallyTheme.darkGray.opacity(0.55)
                )
            }
            return PayHintInfo(
                icon: "info.circle.fill",
                text: "Enter a total payment amount (min $\(platformMin)/hr).",
                color: CommunallyTheme.darkGray.opacity(0.55)
            )
        }

        guard let total = payAmountInt, total > 0 else {
            return PayHintInfo(
                icon: "exclamationmark.circle.fill",
                text: "Enter a whole-dollar amount.",
                color: .red
            )
        }

        guard let hourly = derivedHourlyRate, hoursDuration > 0 else {
            return PayHintInfo(
                icon: "exclamationmark.circle.fill",
                text: "Pick start and end times so we can calculate $/hr.",
                color: .red
            )
        }

        let hourlyRounded = Int(hourly.rounded())

        if hourly < Double(platformMin) {
            return PayHintInfo(
                icon: "exclamationmark.circle.fill",
                text: "That works out to ~$\(hourlyRounded)/hr. Communally requires at least $\(platformMin)/hr.",
                color: .red
            )
        }
        if hourly > Double(platformMax) {
            return PayHintInfo(
                icon: "exclamationmark.circle.fill",
                text: "That works out to ~$\(hourlyRounded)/hr. Max allowed is $\(platformMax)/hr.",
                color: .red
            )
        }
        if let cat = selectedJobType {
            if hourly < Double(cat.categoryPayMinimumUSD) {
                return PayHintInfo(
                    icon: "exclamationmark.circle.fill",
                    text: "~$\(hourlyRounded)/hr is below the \(cat.rawValue) floor of $\(cat.categoryPayMinimumUSD)/hr. Raise the total or shorten the time.",
                    color: .red
                )
            }
            if hourly > Double(cat.categoryPayMaximumUSD) {
                return PayHintInfo(
                    icon: "exclamationmark.circle.fill",
                    text: "~$\(hourlyRounded)/hr is above the \(cat.rawValue) cap of $\(cat.categoryPayMaximumUSD)/hr. Lower the total or extend the time.",
                    color: .red
                )
            }
        }

        // In range — green confirmation showing the implied hourly so the
        // hirer can see what the seeker will see.
        return PayHintInfo(
            icon: "checkmark.circle.fill",
            text: "Looks good — ~$\(hourlyRounded)/hr for the seeker.",
            color: CommunallyTheme.primaryGreen
        )
    }

    private var locationRow: some View {
        Button { showLocationPicker = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .frame(width: 24)
                Text("Where")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 48, alignment: .leading)
                Text(locationName.isEmpty ? "Select location..." : locationName)
                    .font(.system(size: 15, weight: locationName.isEmpty ? .regular : .medium))
                    .foregroundColor(locationName.isEmpty ? CommunallyTheme.darkGray.opacity(0.38) : CommunallyTheme.darkGray)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// 7 AM – 7 PM window on the currently selected day. When today is
    /// selected, the lower bound is clamped to "now" so the user can't
    /// schedule a start time that's already in the past (build-6 bug: hirer
    /// posted a today-9 AM job at 9:13 PM and it was accepted).
    private var dayWindow: ClosedRange<Date> {
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: Self.dayStartHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let endAnchor = cal.date(byAdding: .day, value: Self.dayEndDayOffset, to: selectedDate) ?? selectedDate
        // `dayEndMinute` is 0 in production (top-of-hour cap, e.g. 19:00) and
        // 59 in testing mode (so the window goes to 23:59 — letting a job
        // start late at night still leave room for the 5-min minimum length).
        let dayEnd = cal.date(bySettingHour: Self.dayEndHour, minute: Self.dayEndMinute, second: 0, of: endAnchor) ?? endAnchor
        let now = Date()
        let lower = cal.isDate(selectedDate, inSameDayAs: now) ? max(dayStart, now) : dayStart
        // Clamp to a non-empty range so SwiftUI doesn't crash on inversion
        // when today's window has already closed.
        return min(lower, dayEnd)...dayEnd
    }

    /// True when today is selected but every minute of the day's allowed
    /// posting window has already passed. UI uses this to nudge the hirer to
    /// pick tomorrow. In testing mode the window stretches to 23:59 so this
    /// effectively never fires until just before midnight.
    private var todaysWindowHasClosed: Bool {
        let cal = Calendar.current
        guard cal.isDate(selectedDate, inSameDayAs: Date()) else { return false }
        let endAnchor = cal.date(byAdding: .day, value: Self.dayEndDayOffset, to: selectedDate) ?? selectedDate
        let dayEnd = cal.date(bySettingHour: Self.dayEndHour, minute: Self.dayEndMinute, second: 0, of: endAnchor) ?? endAnchor
        return Date() >= dayEnd
    }

    /// End time picker range: from start time onward, capped at the day's
    /// upper bound (7 PM in production, 23:59 in testing mode). Always
    /// clamped to a non-empty range so SwiftUI doesn't crash on inversion.
    private var endTimeWindow: ClosedRange<Date> {
        let cap = dayWindow.upperBound
        let lower = min(selectedTime, cap)
        return lower...cap
    }

    /// Caption shown under the date pickers. Switches between the prod-curfew
    /// message and a testing-mode message so the copy doesn't lie to the
    /// hirer about what's actually allowed.
    private var timeWindowHelperText: String {
        if todaysWindowHasClosed {
            return Self.testingMode
                ? "Today's window has closed — pick tomorrow or later."
                : "Today's 7 AM–7 PM window has closed — pick tomorrow or later."
        }
        if Self.testingMode {
            let durationMin = Int(Self.minimumJobDurationSeconds / 60)
            let leadMin = Int(Self.minimumLeadTimeSeconds / 60)
            return "🚧 Testing: any hour, \(durationMin)-min minimum length, \(leadMin)-min lead time."
        }
        return "Jobs run between 7 AM and 7 PM."
    }

    private var dateTimeRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.orange)
                    .frame(width: 24)
                Text("When")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 48, alignment: .leading)
                DatePicker("", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Spacer()
            }
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .frame(width: 24)
                Text("Time")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 48, alignment: .leading)
                DatePicker("", selection: $selectedTime, in: dayWindow, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Text("→").foregroundColor(.gray.opacity(0.6))
                DatePicker("", selection: $selectedEndTime, in: endTimeWindow, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Spacer()
            }
            HStack(spacing: 6) {
                Image(systemName: todaysWindowHasClosed ? "exclamationmark.circle.fill" : "info.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(todaysWindowHasClosed ? .red : CommunallyTheme.primaryGreen.opacity(0.6))
                Text(timeWindowHelperText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(todaysWindowHasClosed ? .red : CommunallyTheme.darkGray.opacity(0.55))
                Spacer()
            }
            .padding(.leading, 84)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: selectedDate) { _, newDay in
            // Re-anchor times to the selected day so the `in:` range matches
            // what the user just picked. Preserves hour/minute, swaps day.
            selectedTime = Self.combine(day: newDay, time: selectedTime)
            selectedEndTime = Self.combine(day: newDay, time: selectedEndTime)
            // Snap forward if the selected time has already passed today.
            // Without this the picker silently allowed past start times.
            snapTimesIntoValidWindow()
        }
        .onChange(of: selectedTime) { _, newStart in
            // Keep end > start. Bump end to a sensible default ahead of the
            // new start: the larger of "an hour" or "the minimum allowed job
            // length", so in testing mode (5-min minimum) the auto-bump is
            // still an hour, but if the user has explicitly chosen a tighter
            // window the floor at least respects the duration minimum.
            if selectedEndTime <= newStart {
                let defaultLength = max(3600, Self.minimumJobDurationSeconds)
                let bumped = newStart.addingTimeInterval(defaultLength)
                selectedEndTime = min(bumped, dayWindow.upperBound)
            } else if selectedEndTime.timeIntervalSince(newStart) < Self.minimumJobDurationSeconds {
                // User dragged start forward past where end is; nudge end so
                // length still clears the minimum-duration check.
                let nudged = newStart.addingTimeInterval(Self.minimumJobDurationSeconds)
                selectedEndTime = min(nudged, dayWindow.upperBound)
            }
        }
    }

    /// Pulls `selectedTime` and `selectedEndTime` into the current `dayWindow`.
    /// Called whenever the date changes or the view appears so that picking
    /// today after 9 AM doesn't leave the time at 9 AM (which is in the past).
    private func snapTimesIntoValidWindow() {
        let window = dayWindow
        if selectedTime < window.lowerBound { selectedTime = window.lowerBound }
        if selectedEndTime <= selectedTime {
            let defaultLength = max(3600, Self.minimumJobDurationSeconds)
            selectedEndTime = min(selectedTime.addingTimeInterval(defaultLength), window.upperBound)
        }
        if selectedEndTime > window.upperBound { selectedEndTime = window.upperBound }
    }

    private static func combine(day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dayParts = cal.dateComponents([.year, .month, .day], from: day)
        let timeParts = cal.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dayParts.year
        merged.month = dayParts.month
        merged.day = dayParts.day
        merged.hour = timeParts.hour
        merged.minute = timeParts.minute
        return cal.date(from: merged) ?? day
    }

    private var payRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .frame(width: 24)
            Text("Pay")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 48, alignment: .leading)
            Text("$")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(CommunallyTheme.primaryGreen)
            TextField("50", text: $payAmount)
                .font(.system(size: 18, weight: .semibold))
                .keyboardType(.numberPad)
                .focused($isPayFieldFocused)
                .foregroundColor(CommunallyTheme.darkGray)
                .frame(maxWidth: 70)
                .onChange(of: payAmount) { _, newValue in
                    payAmount = sanitizePayAmount(newValue)
                }
            Text("USD")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
            Text("+ 5% fee")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    private var jobTypeRow: some View {
        Button { showJobTypeSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .frame(width: 24)
                Text("Type")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 48, alignment: .leading)
                if let t = selectedJobType {
                    Text(t.emoji).font(.system(size: 18))
                    Text(t.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                } else {
                    Text("Select type...")
                        .font(.system(size: 15))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.38))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var descriptionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .frame(width: 24)
                .padding(.top, 2)
            Text("Details")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 48, alignment: .leading)
                .padding(.top, 2)
            ZStack(alignment: .topLeading) {
                if jobDescription.isEmpty {
                    Text("Describe what you need help with...")
                        .font(.system(size: 15))
                        .foregroundColor(.gray.opacity(0.38))
                        .padding(.top, 2)
                }
                TextEditor(text: $jobDescription)
                    .font(.system(size: 15))
                    .foregroundColor(.black)
                    .frame(minHeight: 80, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
    }

    private var jobTypePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(OpportunityCategory.allCases) { type in
                    Button {
                        selectedJobType = type
                        showJobTypeSheet = false
                    } label: {
                        HStack(spacing: 14) {
                            Text(type.emoji)
                                .font(.system(size: 26))
                                .frame(width: 36, alignment: .center)
                            Text(type.rawValue)
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            if selectedJobType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(CommunallyTheme.primaryGreen)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Color.white)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CommunallyTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Job type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showJobTypeSheet = false
                    }
                    .foregroundStyle(CommunallyTheme.darkGray)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Post Button
    private var postButton: some View {
        Button(action: {
            if let err = payValidationErrorMessage() {
                errorMessage = err
                showError = true
                return
            }
            if StripeConfig.requireStripeIdentityForPaidPosts,
               authManager.currentUser?.userType == .jobHirer,
               authManager.currentUser?.isStripeIdentityVerified != true {
                errorMessage = "Paid listings require Stripe ID verification. Open Profile → Account Settings → Verify government ID."
                showError = true
                return
            }
            showReviewSheet = true
        }) {
            HStack(spacing: 12) {
                Text("Review & Post")
                    .font(CommunallyTheme.bodyFont)
                    .fontWeight(.bold)
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Group {
                    if canPost {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                CommunallyTheme.primaryGreen,
                                CommunallyTheme.secondaryGreen
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                CommunallyTheme.darkGray.opacity(0.3),
                                CommunallyTheme.darkGray.opacity(0.2)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .cornerRadius(16)
            .shadow(color: canPost ? CommunallyTheme.primaryGreen.opacity(0.4) : .clear, radius: 18, x: 0, y: 10)
            .shadow(color: canPost ? .black.opacity(0.1) : .clear, radius: 10, x: 0, y: 5)
        }
        .disabled(!canPost)
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Computed Properties
    private var canPost: Bool {
        selectedLocation != nil &&
        !locationName.isEmpty &&
        !payAmount.isEmpty &&
        isPayAmountValid &&
        !jobDescription.isEmpty &&
        selectedJobType != nil
    }
    
    // Cost calculations
    private var baseAmount: Double {
        Double(payAmount) ?? 0.0
    }
    
    private func sanitizePayAmount(_ input: String) -> String {
        String(input.filter { $0.isNumber })
    }

    /// Computed start/end timestamps for the in-progress post — used both by
    /// the validator (to reject a job that overlaps with one this hirer
    /// already has on the books) and by anything else that needs the absolute
    /// scheduled window.
    private var newJobStartDateTime: Date {
        Self.combine(day: selectedDate, time: selectedTime)
    }
    private var newJobEndDateTime: Date {
        Self.combine(day: selectedDate, time: selectedEndTime)
    }

    /// Returns the title of an existing opportunity by this hirer whose
    /// scheduled window overlaps the new job's window, or nil if there's no
    /// conflict. Only considers `.open` and `.inProgress` opportunities —
    /// completed/cancelled are out of scope.
    private func conflictingScheduledJobTitle() -> String? {
        guard let currentUser = authManager.currentUser else { return nil }
        let myActive = opportunityManager.opportunities.filter {
            $0.hirerId == currentUser.id && ($0.status == .open || $0.status == .inProgress)
        }
        for opp in myActive {
            guard let oStart = opp.scheduledStartDateTime,
                  let oEnd = opp.scheduledEndDateTime else { continue }
            // Two ranges overlap iff start1 < end2 && start2 < end1
            if newJobStartDateTime < oEnd && oStart < newJobEndDateTime {
                return opp.title
            }
        }
        return nil
    }

    private func payValidationErrorMessage() -> String? {
        guard let cat = selectedJobType else { return "Choose a job category." }
        guard let total = payAmountInt, total > 0 else { return "Enter a total payment amount." }
        // Block overlapping bookings — a hirer can have multiple jobs, but
        // not two jobs running at the same time (intuitive scheduling).
        if let conflict = conflictingScheduledJobTitle() {
            return "This time overlaps with your job \"\(conflict)\". Pick a different time or shorten this job."
        }
        // Today's window already over (e.g., posting at 11 PM for today).
        if todaysWindowHasClosed {
            return Self.testingMode
                ? "Today's window has closed. Pick tomorrow or later for the date."
                : "It's past 7 PM today. Pick tomorrow or later for the date."
        }
        // Past start time (today, but the picked time has already passed).
        if selectedTime < Date() {
            return "Start time has already passed. Pick a time in the future."
        }
        // Minimum lead time — workers need a real heads-up before being
        // expected on-site. 30 min in production, 5 min in testing mode.
        let leadTime = selectedTime.timeIntervalSinceNow
        if leadTime < Self.minimumLeadTimeSeconds {
            let mins = Int(Self.minimumLeadTimeSeconds / 60)
            return "Pick a start time at least \(mins) minutes from now so workers can plan to be there."
        }
        // Day-window hard cap. Belt-and-suspenders since the picker is bounded.
        // In testing mode the window is the full 24h so this rarely trips.
        if !dayWindow.contains(selectedTime) {
            return Self.testingMode
                ? "Start time is outside today's allowed window."
                : "Start time must be between 7 AM and 7 PM."
        }
        if !dayWindow.contains(selectedEndTime) {
            return Self.testingMode
                ? "End time is outside today's allowed window."
                : "End time must be between 7 AM and 7 PM."
        }
        if selectedEndTime <= selectedTime {
            return "End time must be after the start time."
        }
        // Floor on job length. 30 min in production (so per-hour rate floors
        // and the safety/payment flows aren't gamed by 5-minute "jobs"),
        // 5 min in testing mode so a dev can step through the whole flow
        // quickly without waiting half an hour for an in-progress job.
        if selectedEndTime.timeIntervalSince(selectedTime) < Self.minimumJobDurationSeconds {
            let mins = Int(Self.minimumJobDurationSeconds / 60)
            return "Jobs must be at least \(mins) minutes long. Stretch the end time."
        }
        guard let hourly = derivedHourlyRate else {
            return "Pick start and end times so we can verify the hourly rate."
        }
        let hourlyRounded = Int(hourly.rounded())
        let platformMin = OpportunityCategory.platformPayMinimumUSD
        let platformMax = OpportunityCategory.platformPayMaximumUSD
        if hourly < Double(platformMin) {
            return "$\(total) over \(String(format: "%.1f", hoursDuration))h works out to ~$\(hourlyRounded)/hr. Communally requires at least $\(platformMin)/hr."
        }
        if hourly > Double(platformMax) {
            return "$\(total) over \(String(format: "%.1f", hoursDuration))h works out to ~$\(hourlyRounded)/hr. Communally allows up to $\(platformMax)/hr."
        }
        if hourly < Double(cat.categoryPayMinimumUSD) {
            return "$\(total) over \(String(format: "%.1f", hoursDuration))h works out to ~$\(hourlyRounded)/hr. \(cat.rawValue) requires at least $\(cat.categoryPayMinimumUSD)/hr."
        }
        if hourly > Double(cat.categoryPayMaximumUSD) {
            return "$\(total) over \(String(format: "%.1f", hoursDuration))h works out to ~$\(hourlyRounded)/hr. \(cat.rawValue) allows up to $\(cat.categoryPayMaximumUSD)/hr."
        }
        return nil
    }
    
    // MARK: - Actions
    private func postOpportunity() {
        guard let selectedLocation = selectedLocation,
              let selectedJobType = selectedJobType,
              let currentUser = authManager.currentUser else {
            Log.debug("❌ postOpportunity: missing required data")
            return
        }
        
        if let moderationError = ContentModerationService.shared.validateJobPost(
            title: selectedJobType.rawValue,
            description: jobDescription
        ) {
            errorMessage = moderationError.localizedDescription
            showError = true
            return
        }
        
        if let payErr = payValidationErrorMessage() {
            errorMessage = payErr
            showError = true
            return
        }

        if !GeoAppConstants.isCoordinateInUS(selectedLocation) {
            errorMessage = "Communally is US-only right now. Choose a location in the United States."
            showError = true
            return
        }
        
        if let homeLat = currentUser.verifiedHomeLatitude,
           let homeLon = currentUser.verifiedHomeLongitude {
            let home = CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)
            if GeoAppConstants.distanceMeters(from: home, to: selectedLocation) > GeoAppConstants.discoveryRadiusMeters {
                errorMessage = "Job location must be within 5 miles of your verified home address."
                showError = true
                return
            }
        }
        
        let location = Location(
            latitude: selectedLocation.latitude,
            longitude: selectedLocation.longitude,
            address: locationName
        )
        
        // Format time strings. Anchor both to the chosen calendar day so the
        // stored times don't drift if the user picked the date last.
        let anchoredStart = Self.combine(day: selectedDate, time: selectedTime)
        let anchoredEnd = Self.combine(day: selectedDate, time: selectedEndTime)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let formattedTime = timeFormatter.string(from: anchoredStart)
        let formattedEndTime = timeFormatter.string(from: anchoredEnd)
        
        // Use the Firebase Auth uid as the hirerId — falling back to the
        // local user id used to mask permission failures. If Firebase Auth
        // isn't ready we now surface that explicitly instead of writing a
        // doc the server will silently reject.
        guard let hirerId = Auth.auth().currentUser?.uid, hirerId == currentUser.id else {
            errorMessage = "Your secure session isn't ready yet. Sign out and sign back in, then try again."
            showError = true
            return
        }

        LoadingOverlayManager.shared.show("Posting your job…")
        opportunityManager.postOpportunity(
            title: selectedJobType.rawValue,
            description: jobDescription,
            location: location,
            locationName: locationName,
            isVolunteer: false, // Everything is paid now
            payAmount: payAmount,
            jobType: selectedJobType.rawValue,
            hirerId: hirerId,
            hirerName: currentUser.fullName,
            hirerImageData: currentUser.profileImageData,
            scheduledDate: selectedDate,
            scheduledTime: formattedTime,
            scheduledEndTime: formattedEndTime,
            payIsHourly: false
        ) { error in
            LoadingOverlayManager.shared.hide()
            if let error = error {
                errorMessage = error.localizedDescription
                showError = true
                return
            }
            Log.debug("📤 Successfully posted opportunity!")
            dismiss()
        }
    }
}

// MARK: - Review Opportunity View
struct ReviewOpportunityView: View {
    let jobType: OpportunityCategory
    let locationName: String
    let selectedDate: Date
    let selectedTime: Date
    let selectedEndTime: Date
    let isVolunteer: Bool
    let payAmount: String
    let jobDescription: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: selectedTime)) – \(formatter.string(from: selectedEndTime))"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 14) {
                    // Compact header
                    HStack(spacing: 12) {
                        Text(jobType.emoji).font(.system(size: 38))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Review Post")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(CommunallyTheme.darkGray)
                            Text(jobType.rawValue)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // Compact review card
                    VStack(spacing: 0) {
                        reviewRow(icon: "mappin.circle.fill", iconColor: CommunallyTheme.primaryGreen, label: "Where", value: locationName)
                        Divider().padding(.horizontal, 14)
                        reviewRow(icon: "calendar", iconColor: .orange, label: "Date", value: selectedDate.formatted(date: .abbreviated, time: .omitted))
                        Divider().padding(.horizontal, 14)
                        reviewRow(icon: "clock.fill", iconColor: .orange, label: "Time", value: formattedTimeRange)
                        Divider().padding(.horizontal, 14)
                        reviewRow(icon: "dollarsign.circle.fill", iconColor: CommunallyTheme.primaryGreen, label: "Pay", value: "$\(payAmount) total")
                        Divider().padding(.horizontal, 14)
                        reviewRow(icon: "text.alignleft", iconColor: CommunallyTheme.primaryGreen, label: "Notes", value: jobDescription)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                    .padding(.horizontal, 20)

                    Spacer()

                    // Buttons
                    VStack(spacing: 8) {
                        Button(action: onConfirm) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Confirm & Post")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(14)
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: onCancel) {
                            Text("Go Back & Edit")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
                    }
                }
            }
        }
    }

    private func reviewRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 1)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 1)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)
                .lineLimit(3)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Location Picker View
struct LocationPickerView: View {
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Binding var isPresented: Bool
    var homeCoordinate: CLLocationCoordinate2D? = nil

    @State private var searchText = ""
    @State private var region: MKCoordinateRegion
    @State private var cameraPosition: MapCameraPosition
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @ObservedObject private var locationManager = LocationManager.shared

    init(selectedLocation: Binding<CLLocationCoordinate2D?>, locationName: Binding<String>, isPresented: Binding<Bool>, homeCoordinate: CLLocationCoordinate2D? = nil) {
        self._selectedLocation = selectedLocation
        self._locationName = locationName
        self._isPresented = isPresented
        self.homeCoordinate = homeCoordinate
        
        // If there's already a selected location, use it
        if let location = selectedLocation.wrappedValue {
            let initialRegion = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            self._region = State(initialValue: initialRegion)
            self._cameraPosition = State(initialValue: .region(initialRegion))
        } else {
            let defaultRegion = MKCoordinateRegion(
                center: GeoAppConstants.usMapCenter,
                span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
            )
            self._region = State(initialValue: defaultRegion)
            self._cameraPosition = State(initialValue: .region(defaultRegion))
        }
    }
    
    @State private var showOutsideUSAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map View
                mapView
                
                // Dimmed overlay when searching
                if isSearching && !searchResults.isEmpty {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            searchText = ""
                            searchResults = []
                            isSearching = false
                        }
                }
                
                // Overlay UI
                VStack(spacing: 0) {
                    // Welcome hint card (shows briefly)
                    if selectedLocation == nil && searchText.isEmpty {
                        welcomeHintCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Search Bar at top
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, selectedLocation == nil && searchText.isEmpty ? 8 : 8)
                        .zIndex(100)
                    
                    // Search Results
                    if isSearching && !searchResults.isEmpty {
                        searchResultsList
                            .zIndex(99)
                    }
                    
                    Spacer()
                    
                    // Location info card
                    if selectedLocation != nil && !isSearching {
                        locationInfoCard
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Instruction text with animation
                    if !isSearching {
                        instructionText
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Confirm button
                    if !isSearching {
                        confirmButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSearching)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedLocation != nil)
                
                // Quick action buttons
                if !isSearching {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                currentLocationButton
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 240)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            
                            Text("Select Location")
                                .font(.system(size: 18, weight: .bold, design: .default))
                                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                        }
                        
                        Text("United States only · drag map or search")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                    }
                }
            }
            .onAppear {
                centerOnUserLocation()
            }
            .alert("US only", isPresented: $showOutsideUSAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pick a location inside the United States.")
            }
        }
    }
    
    // MARK: - Welcome Hint Card
    private var welcomeHintCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Tip!")
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Text("Search above or drag the map to select your location")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.2), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Map View
    private var mapView: some View {
        Map(position: $cameraPosition) {
            if let home = homeCoordinate {
                Annotation("", coordinate: home, anchor: .bottom) {
                    HomePinView()
                        .allowsHitTesting(false)
                }
            }
        }
            .onMapCameraChange { context in
                region = context.region
                // Update selected location as user drags the map
                selectedLocation = context.region.center
                // Debounce location name updates to avoid too many geocoding requests
                updateLocationNameDebounced(for: context.region.center)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .ignoresSafeArea()
            .overlay(centerPin)
            .overlay(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.72, blue: 0.38).opacity(0.12),
                        Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            )
    }
    
    // Debounce timer for location updates
    @State private var locationUpdateTimer: Timer?
    
    private func updateLocationNameDebounced(for coordinate: CLLocationCoordinate2D) {
        // Cancel previous timer
        locationUpdateTimer?.invalidate()
        
        // Create new timer to update after 0.5 seconds of no movement
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            updateLocationName(for: coordinate)
        }
    }
    
    private var centerPin: some View {
        VStack(spacing: 0) {
            ZStack {
                // Animated rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(CommunallyTheme.primaryGreen.opacity(0.3), lineWidth: 3)
                        .frame(width: CGFloat(60 + index * 30), height: CGFloat(60 + index * 30))
                        .scaleEffect(1.0 + (Double(index) * 0.2))
                        .opacity(0.4 - (Double(index) * 0.1))
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: selectedLocation != nil
                        )
                }
                
                // Outer pulsing glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CommunallyTheme.primaryGreen.opacity(0.4),
                                CommunallyTheme.primaryGreen.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(selectedLocation != nil ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: selectedLocation != nil)
                
                // Pin background circle
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 12, x: 0, y: 6)
                
                // Pin icon with bounce animation
                Image(systemName: selectedLocation != nil ? "mappin.circle.fill" : "mappin.circle")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                CommunallyTheme.primaryGreen,
                                CommunallyTheme.lightGreen
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .scaleEffect(selectedLocation != nil ? 1.0 : 1.15)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: selectedLocation != nil)
            }
            
            // Animated pin shadow/point
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 12
                    )
                )
                .frame(width: 28, height: 12)
                .blur(radius: 3)
                .offset(y: -5)
                .scaleEffect(selectedLocation != nil ? 1.0 : 1.1)
                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: selectedLocation != nil)
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Search icon with gradient background and pulse
                ZStack {
                    // Pulse effect
                    if searchText.isEmpty {
                        Circle()
                            .fill(CommunallyTheme.primaryGreen.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .scaleEffect(1.1)
                            .opacity(0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: searchText.isEmpty)
                    }
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    CommunallyTheme.primaryGreen,
                                    CommunallyTheme.lightGreen
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: searchText.isEmpty ? "magnifyingglass" : "magnifyingglass.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: searchText.isEmpty)
                }
                
                // Text field
                TextField("Search: IKEA, Starbucks, or address...", text: $searchText)
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .onChange(of: searchText) {
                        if !searchText.isEmpty {
                            performSearch(query: searchText)
                        } else {
                            searchResults = []
                            isSearching = false
                        }
                    }
                
                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                        isSearching = false
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                                .frame(width: 30, height: 30)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        CommunallyTheme.primaryGreen.opacity(0.3),
                                        CommunallyTheme.lightGreen.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.25), radius: 18, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
            )
        }
    }
    
    // MARK: - Search Results List
    private var searchResultsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(searchResults, id: \.self) { item in
                    Button(action: {
                        selectSearchResult(item)
                    }) {
                        HStack(spacing: 14) {
                            // Location icon
                            ZStack {
                                Circle()
                                    .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                            }
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name ?? "Unknown Location")
                                    .font(.system(size: 16, weight: .bold, design: .default))
                                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                
                                if let address = item.placemark.title {
                                    Text(address)
                                        .font(.system(size: 14, weight: .medium, design: .default))
                                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            // Arrow icon
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.3))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.1), radius: 8, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.98))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Location Info Card
    private var locationInfoCard: some View {
        HStack(spacing: 14) {
            // Animated checkmark icon
            ZStack {
                Circle()
                    .fill(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Circle()
                    .stroke(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)
                    .scaleEffect(1.2)
                    .opacity(0.5)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: locationName.isEmpty)
                
                Image(systemName: locationName.isEmpty ? "location.magnifyingglass" : "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: locationName.isEmpty)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text(locationName.isEmpty ? "Finding address..." : "Location Ready!")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                
                Text(locationName.isEmpty ? "Move map to select" : locationName)
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            // Edit icon
            if !locationName.isEmpty {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.2), radius: 15, x: 0, y: 8)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        )
    }
    
    // MARK: - Instruction Text
    private var instructionText: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: selectedLocation != nil ? "hand.thumbsup.fill" : "hand.tap.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedLocation != nil ? "Great! Location selected" : "How to select")
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray)

                Text(selectedLocation != nil ? "Tap 'Confirm' below to continue" : "Drag map to move pin • Search for a place")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.10), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Current Location Button
    private var currentLocationButton: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            centerOnUserLocation()
        }) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.2))
                    .frame(width: 58, height: 58)
                    .blur(radius: 8)
                
                // Button background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(red: 0.98, green: 0.98, blue: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                
                Image(systemName: "location.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Confirm Button
    private var confirmButton: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .heavy)
            impactMed.impactOccurred()
            confirmLocation()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm Location")
                        .font(.system(size: 18, weight: .bold, design: .default))
                    
                    if selectedLocation != nil && !locationName.isEmpty {
                        Text("Tap to continue")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .opacity(0.85)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(
                Group {
                    if selectedLocation != nil && !locationName.isEmpty {
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.8, blue: 0.4),
                                Color(red: 0.4, green: 0.85, blue: 0.5)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.7, blue: 0.7),
                                Color(red: 0.75, green: 0.75, blue: 0.75)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .cornerRadius(20)
            .shadow(
                color: selectedLocation != nil ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.5) : Color.gray.opacity(0.3),
                radius: 20,
                x: 0,
                y: 10
            )
            .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
        }
        .disabled(selectedLocation == nil || locationName.isEmpty)
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedLocation != nil)
    }
    
    // MARK: - Helper Functions
    private func performSearch(query: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let response = response {
                searchResults = response.mapItems
                isSearching = true
            }
        }
    }
    
    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        
        // Animate to location
        withAnimation(.easeInOut(duration: 0.5)) {
            region.center = coordinate
            cameraPosition = .region(region)
        }
        
        selectedLocation = coordinate
        locationName = item.name ?? item.placemark.title ?? ""
        
        // Clear search
        searchText = ""
        searchResults = []
        isSearching = false
    }
    
    private func centerOnUserLocation() {
        if let location = locationManager.location,
           GeoAppConstants.isCoordinateInUS(location.coordinate) {
            withAnimation(.easeInOut(duration: 0.5)) {
                region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
                cameraPosition = .region(region)
            }
            selectedLocation = location.coordinate
            updateLocationName(for: location.coordinate)
        } else {
            let r = MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
            region = r
            cameraPosition = .region(r)
            selectedLocation = r.center
        }
    }
    
    private func updateLocationName(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                var components: [String] = []
                if let name = placemark.name {
                    components.append(name)
                }
                if let locality = placemark.locality {
                    components.append(locality)
                }
                locationName = components.joined(separator: ", ")
            }
        }
    }
    
    private func confirmLocation() {
        selectedLocation = region.center
        guard GeoAppConstants.isCoordinateInUS(region.center) else {
            showOutsideUSAlert = true
            return
        }
        if locationName.isEmpty {
            updateLocationName(for: region.center)
        }
        isPresented = false
    }
}

// MARK: - Preview
#Preview {
    PostOpportunityView()
}

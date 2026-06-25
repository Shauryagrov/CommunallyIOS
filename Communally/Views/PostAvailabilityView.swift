//
//  PostAvailabilityView.swift
//  Communally
//
//  Seeker-side mirror of PostOpportunityView. Lets a seeker publish an
//  "I'm available" listing that hirers within 5 miles can discover. Form
//  is intentionally shorter than the hirer post-job flow — most seekers
//  are filling this out on a phone in spare moments, not at a desk.
//

import SwiftUI
import CoreLocation

struct PostAvailabilityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var availabilityManager = AvailabilityManager.shared
    @ObservedObject private var locationManager = LocationManager.shared

    // Form state
    @State private var selectedCategories: Set<OpportunityCategory> = []
    @State private var selectedDate: Date = Date()
    @State private var startTime: Date = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime: Date = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var hourlyRateText: String = "20"
    @State private var note: String = ""

    // UI state
    @State private var isPosting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showSuccess: Bool = false

    @FocusState private var rateFocused: Bool
    @FocusState private var noteFocused: Bool

    // MARK: - Derived

    private var hourlyRateInt: Int? { Int(hourlyRateText) }

    /// The highest per-category floor of any selected category. If a seeker
    /// picks Gardening ($18 min) + Tutoring ($20 min), the post must clear
    /// $20/hr.
    private var effectiveMinRate: Int {
        selectedCategories.map(\.categoryPayMinimumUSD).max()
            ?? OpportunityCategory.platformPayMinimumUSD
    }

    /// Symmetric — lowest of the selected categories' caps, so a single
    /// post can't claim $100/hr for cleaning by piggy-backing tutoring.
    private var effectiveMaxRate: Int {
        selectedCategories.map(\.categoryPayMaximumUSD).min()
            ?? OpportunityCategory.platformPayMaximumUSD
    }

    private var isRateValid: Bool {
        guard let r = hourlyRateInt else { return false }
        return r >= effectiveMinRate && r <= effectiveMaxRate
    }

    private var canSubmit: Bool {
        !selectedCategories.isEmpty
            && isRateValid
            && endTime > startTime
            && !isPosting
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                whatSection
                whenSection
                rateSection
                noteSection
                postSection
            }
            .navigationTitle("Post Availability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't post", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("You're on the board!", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Hirers nearby will see your availability. We'll let you know if anyone reaches out.")
            }
        }
    }

    // MARK: - Sections

    private var whatSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick everything you're up for. You can choose more than one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(OpportunityCategory.allCases) { cat in
                        categoryChip(cat)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("What can you do?")
        }
    }

    private func categoryChip(_ cat: OpportunityCategory) -> some View {
        let selected = selectedCategories.contains(cat)
        return Button {
            withAnimation(.snappy) {
                if selected { selectedCategories.remove(cat) }
                else { selectedCategories.insert(cat) }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Text(cat.emoji)
                Text(cat.rawValue)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? CommunallyTheme.primaryGreen.opacity(0.18) : Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? CommunallyTheme.primaryGreen : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .foregroundColor(selected ? CommunallyTheme.accentGreen : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cat.rawValue), \(selected ? "selected" : "not selected")")
    }

    private var whenSection: some View {
        Section {
            DatePicker("Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
            DatePicker("End", selection: $endTime, in: startTime..., displayedComponents: .hourAndMinute)
        } header: {
            Text("When are you free?")
        } footer: {
            if endTime <= startTime {
                Text("End time has to be after start.")
                    .foregroundStyle(.red)
            }
        }
    }

    private var rateSection: some View {
        Section {
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Hourly rate", text: $hourlyRateText)
                    .keyboardType(.numberPad)
                    .focused($rateFocused)
                Text("/hr")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Your rate")
        } footer: {
            if selectedCategories.isEmpty {
                Text("Pick a category first to see the suggested range.")
            } else if let r = hourlyRateInt, !isRateValid {
                Text("\(r) is outside the $\(effectiveMinRate)–$\(effectiveMaxRate)/hr range for the categories you picked.")
                    .foregroundStyle(.red)
            } else {
                Text("Suggested: $\(effectiveMinRate)–$\(effectiveMaxRate)/hr based on your categories.")
            }
        }
    }

    private var noteSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("e.g. \"I've done 15+ moves, comfortable with heavy lifting\"")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .focused($noteFocused)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
            }
        } header: {
            Text("Add a note (optional)")
        }
    }

    private var postSection: some View {
        Section {
            Button {
                submit()
            } label: {
                HStack {
                    Spacer()
                    if isPosting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Post Availability")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(CommunallyTheme.primaryGreen)
            .disabled(!canSubmit)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    // MARK: - Submit

    private func submit() {
        guard let user = authManager.currentUser else {
            errorMessage = "Sign in again to post."
            showError = true
            return
        }
        guard let rate = hourlyRateInt, isRateValid else {
            errorMessage = "That rate isn't in the allowed range yet."
            showError = true
            return
        }
        guard let (loc, label) = resolveLocation(for: user) else {
            errorMessage = "We need your neighborhood to put you on the map. Set your home address in Profile, or turn on Location, and try again."
            showError = true
            return
        }

        rateFocused = false
        noteFocused = false
        isPosting = true

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        availabilityManager.postAvailability(
            seekerId: user.id,
            seekerName: "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces),
            seekerImageData: user.profileImageData,
            location: loc,
            locationName: label,
            categories: selectedCategories.map(\.rawValue).sorted(),
            hourlyRate: rate,
            scheduledDate: selectedDate,
            scheduledTime: formatter.string(from: startTime),
            scheduledEndTime: formatter.string(from: endTime),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : note.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { error in
            isPosting = false
            if let error = error {
                errorMessage = error.localizedDescription
                showError = true
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccess = true
            }
        }
    }

    /// Mirrors `MapPresenceService.realCoordinate` — verified home wins, then
    /// onboarding location, then live GPS. Returns nil if none are available
    /// so we can show a friendly "set your area first" error instead of
    /// silently dropping a post at (0, 0).
    private func resolveLocation(for user: User) -> (Location, String)? {
        if let lat = user.verifiedHomeLatitude, let lon = user.verifiedHomeLongitude {
            return (
                Location(latitude: lat, longitude: lon, address: user.verifiedHomeAddress),
                user.verifiedHomeAddress ?? "Near home"
            )
        }
        if let loc = user.location {
            return (loc, loc.address ?? "My area")
        }
        if let live = locationManager.location?.coordinate {
            return (
                Location(latitude: live.latitude, longitude: live.longitude, address: nil),
                "Near me"
            )
        }
        return nil
    }
}

#Preview {
    PostAvailabilityView()
        .environmentObject(AuthenticationManager.shared)
}

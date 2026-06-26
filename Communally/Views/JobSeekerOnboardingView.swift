import SwiftUI

struct JobSeekerOnboardingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool? = nil
    @State private var usernameCheckTask: DispatchWorkItem? = nil
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()

    private var age: Int {
        User.ageFromDateOfBirth(dateOfBirth)
    }
    @State private var termsAccepted = false
    @State private var parentalConsentGiven = false
    @State private var selectedSkills: Set<String> = []
    @State private var description = ""
    @State private var locationPermissionGranted = false
    @State private var currentStep = 0
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showCameraAlert = false
    @State private var showPhotoOptions = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showModerationAlert = false
    @State private var moderationMessage = ""
    /// COPPA hard block — fires when the picked DOB resolves to under 13.
    /// Tapping OK signs the user out, kicking them back to AuthenticationView
    /// so no in-progress onboarding state lingers for a rejected minor.
    @State private var showCoppaBlockAlert = false
    @State private var confettiTrigger = 0

    private var totalSteps: Int { 4 }

    /// Same categories as posting an opportunity (`OpportunityCategory`).
    private var availableSkills: [String] { OpportunityCategory.allTitles }

    var body: some View {
        ZStack {
            OnboardingFlowBackground()

            VStack(spacing: 0) {
                OnboardingHeaderBar(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    showBackToSelection: currentStep == 0,
                    onBackToSelection: { dismiss() }
                )

                TabView(selection: $currentStep) {
                    seekerProfileStep
                        .tag(0)
                    seekerSelfieStep
                        .tag(1)
                    seekerSkillsStep
                        .tag(2)
                    seekerLocationStep
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingBottomBar(
                    showBack: currentStep > 0,
                    isLastStep: currentStep == totalSteps - 1,
                    canProceed: seekerCanProceed,
                    isLoading: false,
                    onBack: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            currentStep -= 1
                        }
                    },
                    onContinue: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        if currentStep == totalSteps - 1 {
                            completeOnboarding()
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                currentStep += 1
                            }
                        }
                    }
                )
            }

            ConfettiView(trigger: $confettiTrigger)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $profileImage, sourceType: imageSourceType)
        }
        .sheet(isPresented: $showTerms) {
            NavigationView { TermsAndConditionsView() }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationView { PrivacyPolicyView() }
        }
        .confirmationDialog("Add Photo", isPresented: $showPhotoOptions, titleVisibility: .hidden) {
            Button("Take Photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    imageSourceType = .camera
                    showingImagePicker = true
                } else {
                    showCameraAlert = true
                }
            }
            Button("Choose from Library") {
                imageSourceType = .photoLibrary
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Camera Not Available", isPresented: $showCameraAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Camera is not available on this device.")
        }
        .alert("Please Update This Text", isPresented: $showModerationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(moderationMessage)
        }
        .alert("Age requirement", isPresented: $showCoppaBlockAlert) {
            Button("OK") { authManager.signOut() }
        } message: {
            Text("Communally is for users 13 and older. We aren't able to create an account based on the birthdate you entered.")
        }
        .onChange(of: dateOfBirth) { _, _ in
            if age >= 18 {
                parentalConsentGiven = false
            }
            if age < AppAgeRequirements.coppaMinimumAge {
                showCoppaBlockAlert = true
            }
        }
        .onChange(of: currentStep) { _, _ in
            // Dismiss the keyboard whenever the user moves to a new step so
            // the new step's content isn't hidden behind the input pad.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
        .onAppear {
            // App Store Guideline 4: when the user signed in with Apple,
            // the ASAuthorizationAppleIDCredential includes fullName on
            // the first sign-in. AuthenticationManager already stores
            // those values on the User model before onboarding starts.
            // Pre-fill the text fields from currentUser so we aren't
            // making the user retype data Apple already gave us. Fields
            // remain editable in case Apple's value is "Apple"/"User"
            // (the fallback when the user picked "Hide My Name") or
            // the user just wants to correct it.
            if let user = authManager.currentUser {
                if firstName.isEmpty, user.firstName != "Apple" {
                    firstName = user.firstName
                }
                if lastName.isEmpty, user.lastName != "User" {
                    lastName = user.lastName
                }
            }
        }
    }


    // MARK: - Parent notice (under-18 seekers)

    private var parentApprovalNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "message.badge.filled.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Parent approval — next step")
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray)
                Text("After you finish this, you'll send your parent a quick approval link via Messages.")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CommunallyTheme.primaryGreen.opacity(0.08))
        )
    }

    // MARK: - Step 0: Profile (matches hirer reference)

    private var seekerProfileStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                OnboardingStepTitle(emoji: "👋", title: "Create Your Profile")
                OnboardingProfilePhotoPicker(image: $profileImage) {
                    showPhotoOptions = true
                }
                OnboardingNameFields(firstName: $firstName, lastName: $lastName)
                OnboardingUsernameField(
                    username: $username,
                    isChecking: isCheckingUsername,
                    isAvailable: usernameAvailable
                ) { checkUsernameAvailability($0) }
                OnboardingDateOfBirthRow(dateOfBirth: $dateOfBirth, minimumAge: AppAgeRequirements.minimumUserAge, compact: true)
                OnboardingInfoNote(
                    text: "15+ only. We don’t supervise jobs—use good judgment; call emergency services if you need help.",
                    compact: true
                )
                if age < 18 {
                    parentApprovalNotice
                }
                OnboardingTermsAgreementRow(
                    accepted: $termsAccepted,
                    onOpenTerms: { showTerms = true },
                    onOpenPrivacy: { showPrivacy = true },
                    includePrivacyLinks: true,
                    compact: true
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 1: Selfie / face photo

    private var seekerSelfieStep: some View {
        OnboardingSelfieStep(
            image: $profileImage,
            age: age,
            onTakeSelfie: {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    imageSourceType = .camera
                    showingImagePicker = true
                } else {
                    showCameraAlert = true
                }
            },
            onChoosePhoto: {
                imageSourceType = .photoLibrary
                showingImagePicker = true
            }
        )
    }

    // MARK: - Step 2: Skills

    private var seekerSkillsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                seekerSkillsHeader
                seekerSkillsCard
            }
            .padding(.bottom, 24)
        }
    }

    private var seekerSkillsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                stepIconBadge(systemName: "wrench.and.screwdriver.fill")
                Text("What can you help with?")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Pick at least 3.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    // MARK: - Step 2: Location

    private var seekerLocationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                seekerLocationHeader
                seekerLocationCard
                if age < 18 {
                    parentApprovalNotice
                        .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var seekerLocationHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Final step")
                .font(.system(size: 12, weight: .bold, design: .default))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.12)))

            HStack(alignment: .center, spacing: 10) {
                stepIconBadge(systemName: "location.fill")
                Text("Where are you?")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("So we can show jobs near you.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    /// Shared circular gradient icon used by both skills and location step
    /// headers — keeps the visual rhythm of the onboarding flow consistent.
    private func stepIconBadge(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                .frame(width: 38, height: 38)
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var seekerSkillsCounterChip: some View {
        let count = selectedSkills.count
        let met = count >= 3
        return HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "number.circle.fill")
                .font(.system(size: 12, weight: .bold))
            Text("\(count) of 3+ selected")
                .font(.system(size: 12, weight: .bold, design: .default))
        }
        .foregroundColor(met ? CommunallyTheme.primaryGreen : CommunallyTheme.darkGray.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(met
                      ? CommunallyTheme.primaryGreen.opacity(0.14)
                      : Color.gray.opacity(0.10))
        )
    }

    private var seekerSkillsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Categories", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                Spacer(minLength: 8)
                seekerSkillsCounterChip
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(availableSkills, id: \.self) { skill in
                    let on = selectedSkills.contains(skill)
                    Button {
                        // Selection haptic — distinct from the medium impact
                        // used by Continue / Back so the user can feel the
                        // difference between "picked" and "advanced step".
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                            if on {
                                selectedSkills.remove(skill)
                            } else {
                                selectedSkills.insert(skill)
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(skill)
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(CommunallyTheme.darkGray)
                                .multilineTextAlignment(.center)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(on ? CommunallyTheme.primaryGreen : CommunallyTheme.midGray)
                                .symbolEffect(.bounce, value: on)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.horizontal, 12)
                        .background(
                            on
                                ? CommunallyTheme.primaryGreen.opacity(0.10)
                                : Color.white
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    on
                                        ? CommunallyTheme.primaryGreen.opacity(0.55)
                                        : Color.black.opacity(0.10),
                                    lineWidth: on ? 1.5 : 1.25
                                )
                        )
                        .scaleEffect(on ? 1.02 : 1.0)
                        .shadow(color: on ? CommunallyTheme.primaryGreen.opacity(0.18) : .clear,
                                radius: on ? 8 : 0, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 22)
    }

    private var seekerLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your location")
                        .font(.system(size: 15, weight: .bold, design: .default))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    Text("So we can show jobs nearby on the map.")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: requestLocationPermission) {
                HStack(spacing: 8) {
                    Image(systemName: locationPermissionGranted ? "checkmark.circle.fill" : "location.fill")
                    Text(locationPermissionGranted ? "Location enabled" : "Continue")
                }
                .font(.system(size: 15, weight: .bold, design: .default))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(locationPermissionGranted)
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 22)
    }

    // MARK: - Validation

    private var seekerCanProceed: Bool {
        switch currentStep {
        case 0:
            // The dedicated selfie step (case 1) now collects the photo, so
            // step 0 only validates name / username / age / terms.
            return !firstName.isEmpty && !lastName.isEmpty
                && !username.isEmpty && usernameAvailable == true
                && termsAccepted
                && age >= AppAgeRequirements.coppaMinimumAge
                && age >= AppAgeRequirements.minimumUserAge
        case 1:
            // Selfie / face-photo step — a photo is required to continue.
            return profileImage != nil
        case 2:
            return selectedSkills.count >= 3
        case 3:
            // App Store Guideline 5.1.5 — the app must remain functional
            // without location services. Previously this required
            // `locationPermissionGranted`, which trapped users who denied
            // the permission on a wall they could not get past. Now the
            // location step is informational: tapping the in-step button
            // requests permission, but the bottom-bar Continue is always
            // available so users who deny (or skip entirely) can still
            // finish onboarding. Downstream features that need location
            // (map radius filtering, "near me" badges) degrade gracefully
            // — `completeOnboarding` already maps `LocationManager.shared
            // .location` to nil when no fix exists.
            return true
        default:
            return false
        }
    }

    private func checkUsernameAvailability(_ username: String) {
        usernameCheckTask?.cancel()

        guard !username.isEmpty, username.count >= 3 else {
            usernameAvailable = nil
            isCheckingUsername = false
            return
        }

        isCheckingUsername = true
        usernameAvailable = nil

        let task = DispatchWorkItem {
            UserDatabase.shared.checkUsernameAvailability(username) { isAvailable in
                DispatchQueue.main.async {
                    self.usernameAvailable = isAvailable
                    self.isCheckingUsername = false
                }
            }
        }

        usernameCheckTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: task)
    }

    private func requestLocationPermission() {
        LocationManager.shared.requestLocationPermission { granted in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.locationPermissionGranted = granted
                }
            }
        }
    }

    private func completeOnboarding() {
        guard let currentUser = authManager.currentUser else { return }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty,
           let moderationError = ContentModerationService.shared.validateProfileText(trimmedDescription) {
            moderationMessage = moderationError.localizedDescription
            showModerationAlert = true
            return
        }

        // Celebrate before flipping to the dashboard.
        confettiTrigger += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let updatedUser = User(
            id: currentUser.id,
            email: currentUser.email,
            username: username,
            firstName: firstName,
            lastName: lastName,
            age: age,
            dateOfBirth: dateOfBirth,
            userType: .jobSeeker,
            profileImageURL: currentUser.profileImageURL,
            profileImageData: profileImage?.jpegData(compressionQuality: 0.8),
            skills: Array(selectedSkills),
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            location: LocationManager.shared.location.map { location in
                Location(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    address: nil
                )
            },
            createdAt: currentUser.createdAt,
            parentalConsentGiven: age < 18 ? true : nil,
            hasCompletedOnboarding: true,
            acceptedTermsDate: Date(),
            acceptedPrivacyDate: Date(),
            lastUsernameChange: Date(),
            lastNameChange: Date(),
            stripeCustomerId: nil,
            stripeConnectAccountId: nil,
            stripeConnectActive: nil,
            stripeConnectDetailsSubmitted: nil,
            bankAccountConnected: nil,
            stripeConnectedAccountId: nil,
            appleUserId: currentUser.appleUserId,
            legalFirstNameOnId: nil,
            legalLastNameOnId: nil,
            identityDocumentURL: nil,
            identityVerificationSubmittedAt: nil,
            verifiedHomeAddress: nil,
            verifiedHomeLatitude: nil,
            verifiedHomeLongitude: nil,
            stripeIdentityVerified: nil,
            stripeIdentityVerifiedAt: nil,
            stripeIdentityLastSessionId: nil,
            qualificationAttachments: nil,
            parentEmail: nil,
            parentName: nil,
            parentApprovalToken: nil,
            isParentalApproved: age < 18 ? false : nil,
            parentApprovalDate: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            authManager.completeOnboarding(user: updatedUser)
        }
    }
}

#Preview {
    JobSeekerOnboardingView()
        .environmentObject(AuthenticationManager.shared)
}

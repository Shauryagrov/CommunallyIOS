//
//  JobHirerOnboardingView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import UIKit
import GoogleSignIn
import CoreLocation

struct JobHirerOnboardingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()

    private var age: Int {
        User.ageFromDateOfBirth(dateOfBirth)
    }
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var username = ""
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool? = nil
    @State private var usernameCheckTask: DispatchWorkItem? = nil
    @State private var hasLocation: Bool = true
    @State private var termsAccepted: Bool = false
    @State private var hirerFinalTermsAccepted: Bool = false
    @State private var locationPermissionGranted: Bool = false
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showCameraAlert = false
    @State private var showPhotoOptions = false
    @State private var bio = ""
    @State private var legalFirstName = ""
    @State private var legalLastName = ""
    /// Shown under legal name fields on the verification step.
    @State private var verificationNameInlineError: String?
    /// Shown on the verification step under the home map card.
    @State private var verificationAddressInlineError: String?
    /// Shown on step 4 (Location & policies) when something fails at Complete.
    @State private var finalSubmitInlineError: String?
    @State private var verificationUnderstanding = false
    @State private var verificationHomeAddress = ""
    @State private var verifiedHomeCoordinate: CLLocationCoordinate2D?
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showModerationAlert = false
    @State private var moderationMessage = ""
    /// COPPA hard block — fires when the picked DOB resolves to under 13.
    /// Tapping OK signs the user out, kicking them back to AuthenticationView.
    /// Hirers already need 18+, so this is defense-in-depth in case a hirer
    /// somehow lands here with an under-13 DOB picker state.
    @State private var showCoppaBlockAlert = false
    @State private var confettiTrigger = 0

    var totalSteps: Int { 5 }
    
    var body: some View {
        ZStack {
            OnboardingFlowBackground()

            VStack(spacing: 0) {
                OnboardingHeaderBar(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    showBackToSelection: currentStep == 0,
                    onBackToSelection: {
                        let impactLight = UIImpactFeedbackGenerator(style: .light)
                        impactLight.impactOccurred()
                        dismiss()
                    }
                )

                TabView(selection: $currentStep) {
                    profileCreationStep.tag(0)
                    hirerLegalNameStep.tag(1)
                    hirerHomeAddressStep.tag(2)
                    hirerBioStep.tag(3)
                    hirerLocationTermsStep.tag(4)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingBottomBar(
                    showBack: currentStep > 0,
                    isLastStep: currentStep == totalSteps - 1,
                    canProceed: canProceed,
                    isLoading: false,
                    onBack: {
                        let impactLight = UIImpactFeedbackGenerator(style: .light)
                        impactLight.impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            currentStep -= 1
                        }
                    },
                    onContinue: {
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                        if currentStep == totalSteps - 1 {
                            completeOnboarding()
                        } else {
                            guard canProceed else { return }
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
        .confirmationDialog("Choose Photo", isPresented: $showPhotoOptions, titleVisibility: .hidden) {
            Button("Take Photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    imageSourceType = .camera
                    showingImagePicker = true
                } else {
                    showCameraAlert = true
                }
            }
            Button("Choose Photo") {
                imageSourceType = .photoLibrary
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) { }
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
        .alert("Camera Not Available", isPresented: $showCameraAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Camera is not available on this device. Please use 'Choose Photo' instead or test on a physical device.")
        }
        .alert("Please Update This Text", isPresented: $showModerationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moderationMessage)
        }
        .alert("Age requirement", isPresented: $showCoppaBlockAlert) {
            Button("OK") { authManager.signOut() }
        } message: {
            Text("Communally is for users 13 and older. We aren't able to create an account based on the birthdate you entered.")
        }
        .onChange(of: dateOfBirth) { _, _ in
            if age < AppAgeRequirements.coppaMinimumAge {
                showCoppaBlockAlert = true
            }
        }
        .onChange(of: currentStep) { _, newStep in
            // Dismiss the keyboard whenever the user moves to a new step so
            // the new step's content isn't hidden behind the input pad.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            if newStep == 4 {
                finalSubmitInlineError = nil
                let status = LocationManager.shared.authorizationStatus
                if status == .notDetermined {
                    requestLocationPermission()
                } else {
                    refreshLocationPermissionState()
                }
            }
        }
        .onAppear {
            refreshLocationPermissionState()
        }
        .onChange(of: hirerFinalTermsAccepted) { _, _ in
            finalSubmitInlineError = nil
        }
        .onChange(of: legalFirstName) { _, _ in
            verificationNameInlineError = nil
        }
        .onChange(of: legalLastName) { _, _ in
            verificationNameInlineError = nil
        }
        .onChange(of: verifiedHomeCoordinate?.latitude) { _, _ in
            if verificationAddressInlineError?.hasPrefix("Map:") == true {
                verificationAddressInlineError = nil
            }
        }
        .onChange(of: verifiedHomeCoordinate?.longitude) { _, _ in
            if verificationAddressInlineError?.hasPrefix("Map:") == true {
                verificationAddressInlineError = nil
            }
        }
    }
    
    // MARK: - Profile Creation Step
    private var profileCreationStep: some View {
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
                OnboardingDateOfBirthRow(dateOfBirth: $dateOfBirth, minimumAge: AppAgeRequirements.minimumHirerAge, compact: true)
                OnboardingInfoNote(text: "You must be 18+ to post opportunities.", compact: true)
                OnboardingTermsAgreementRow(
                    accepted: $termsAccepted,
                    onOpenTerms: { showTerms = true },
                    onOpenPrivacy: { showPrivacy = true },
                    includePrivacyLinks: false,
                    compact: true
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Verification step 1 — legal name only
    private var hirerLegalNameStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verification — 1 of 2")
                        .font(.system(size: 12, weight: .bold, design: .default))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.12)))

                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                                .frame(width: 38, height: 38)
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        Text("What's your legal name?")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("It has to match your government ID exactly. We use this to keep workers safe.")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    Label("Legal name on ID", systemImage: "person.text.rectangle")
                        .font(.system(size: 15, weight: .bold, design: .default))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    HStack(spacing: 10) {
                        TextField("First name", text: $legalFirstName)
                            .textFieldStyle(OnboardingOutlinedTextFieldStyle())
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                        TextField("Last name", text: $legalLastName)
                            .textFieldStyle(OnboardingOutlinedTextFieldStyle())
                            .textContentType(.familyName)
                            .autocorrectionDisabled()
                    }
                    if let verificationNameInlineError {
                        Text(verificationNameInlineError)
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(Color.red.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
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

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    Text("Stored securely. Only used for trust & safety — never shared, never sold.")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Verification step 2 — home address + accuracy confirmation
    private var hirerHomeAddressStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Almost there — 2 of 2")
                        .font(.system(size: 12, weight: .bold, design: .default))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.12)))

                    Text("Where do you live?")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                    Text("Drop a pin on your home so workers know they're meeting a real person nearby.")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    Label("Home address", systemImage: "house.fill")
                        .font(.system(size: 15, weight: .bold, design: .default))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    Text("Tap the map or My location — your address fills in automatically.")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    AddressSearchWithMiniMap(
                        addressLine: $verificationHomeAddress,
                        resolvedCoordinate: $verifiedHomeCoordinate
                    )
                    if let verificationAddressInlineError {
                        Text(verificationAddressInlineError)
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(Color.red.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
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

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        verificationUnderstanding.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: verificationUnderstanding ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(verificationUnderstanding ? CommunallyTheme.primaryGreen : Color(red: 0.75, green: 0.75, blue: 0.75))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This is accurate")
                                .font(.system(size: 14, weight: .bold, design: .default))
                                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                            Text("Communally may review your submission to protect workers.")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(verificationUnderstanding ? CommunallyTheme.primaryGreen.opacity(0.08) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(verificationUnderstanding ? CommunallyTheme.primaryGreen.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
        }
    }
    
    // MARK: - Bio (own step)
    private var hirerBioStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingStepTitle(emoji: "✍️", title: "Tell workers about you")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your bio (optional)")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    Text("A short intro helps workers understand who you are. You can skip this and add it later from your profile.")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                    ZStack(alignment: .topLeading) {
                        if bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Short, friendly intro…")
                                .font(.system(size: 15, weight: .regular, design: .default))
                                .foregroundStyle(Color(red: 0.62, green: 0.62, blue: 0.62))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $bio)
                            .frame(height: 140)
                            .padding(6)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.10), radius: 10, x: 0, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CommunallyTheme.primaryGreen.opacity(0.28), lineWidth: 1)
                    )

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        bio = ""
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            currentStep += 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Skip for now")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(CommunallyTheme.primaryGreen)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Location & Terms (own step)
    private var hirerLocationTermsStep: some View {
        ScrollView {
            VStack(spacing: 16) {
            VStack(spacing: 11) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Location & policies")
                    .font(.system(size: 19, weight: .bold, design: .default))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                Text("Allow location for the map, then accept policies below.")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                if let finalSubmitInlineError {
                    Text(finalSubmitInlineError)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(Color.red.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                        .padding(.horizontal, 4)
                }
                Button(action: requestLocationPermission) {
                    HStack(spacing: 8) {
                        Image(systemName: locationPermissionGranted ? "checkmark.circle.fill" : "location.fill")
                        Text(locationPermissionGranted ? "Location enabled" : "Allow location access")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use current location")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                        Text("General area for nearby gigs")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $hasLocation)
                        .labelsHidden()
                        .tint(CommunallyTheme.primaryGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.1), radius: 10, x: 0, y: 4)
                )
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            hirerFinalTermsAccepted.toggle()
                        }
                    } label: {
                        Image(systemName: hirerFinalTermsAccepted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(hirerFinalTermsAccepted ? CommunallyTheme.primaryGreen : Color(red: 0.78, green: 0.78, blue: 0.78))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("I accept the Terms, Privacy Policy, and safety notice.")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button { showTerms = true } label: {
                                Text("Terms")
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                                    .foregroundStyle(CommunallyTheme.primaryGreen)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            Text("·")
                                .foregroundStyle(Color(red: 0.55, green: 0.55, blue: 0.55))
                            Button { showPrivacy = true } label: {
                                Text("Privacy")
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                                    .foregroundStyle(CommunallyTheme.primaryGreen)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text("Communally connects users but does not supervise jobs or guarantee safety. You’re responsible for lawful postings and using emergency services when needed.")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(red: 0.48, green: 0.48, blue: 0.48))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CommunallyTheme.primaryGreen.opacity(0.06))
                    )
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 20)
        }
        }
    }

    private func requestLocationPermission() {
        LocationManager.shared.requestLocationPermission { granted in
            DispatchQueue.main.async {
                self.locationPermissionGranted = granted
                if granted {
                    if self.finalSubmitInlineError?.hasPrefix("Location:") == true {
                        self.finalSubmitInlineError = nil
                    }
                } else {
                    self.finalSubmitInlineError = "Location: turn on location access to continue."
                }
            }
        }
    }

    private func refreshLocationPermissionState() {
        let status = LocationManager.shared.authorizationStatus
        locationPermissionGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }
    
    // MARK: - Computed Properties
    private func checkUsernameAvailability(_ username: String) {
        // Cancel any pending check
        usernameCheckTask?.cancel()
        
        // Reset if empty or too short
        guard !username.isEmpty, username.count >= 3 else {
            usernameAvailable = nil
            isCheckingUsername = false
            return
        }
        
        // Show checking state immediately
        isCheckingUsername = true
        usernameAvailable = nil
        
        // Create debounced task (wait 0.8 seconds after user stops typing)
        let task = DispatchWorkItem {
            // Perform async check without blocking
            UserDatabase.shared.checkUsernameAvailability(username) { isAvailable in
                DispatchQueue.main.async {
                    self.usernameAvailable = isAvailable
                    self.isCheckingUsername = false
                }
            }
        }
        
        usernameCheckTask = task
        
        // Execute after delay (debounce)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0: // Profile Creation
            // Profile photo is now optional — the dashboard "Complete profile"
            // card prompts the user to add one later.
            return !firstName.isEmpty && !lastName.isEmpty && !username.isEmpty
                && (usernameAvailable == true)
                && age >= AppAgeRequirements.coppaMinimumAge
                && age >= AppAgeRequirements.minimumHirerAge
                && termsAccepted
        case 1: // Legal name
            return !legalFirstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !legalLastName.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: // Home address + accuracy confirmation
            return verifiedHomeCoordinate != nil && verificationUnderstanding
        case 3: // Bio (optional) — always proceedable
            return true
        case 4: // Location + Policies
            return locationPermissionGranted && hirerFinalTermsAccepted
        default:
            return false
        }
    }
    
    // MARK: - Actions
    private func completeOnboarding() {
        guard let currentUser = authManager.currentUser else { return }

        verificationNameInlineError = nil
        verificationAddressInlineError = nil
        finalSubmitInlineError = nil

        let resolvedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Hirer on Communally."
            : bio.trimmingCharacters(in: .whitespacesAndNewlines)

        if let moderationError = ContentModerationService.shared.validateProfileText(resolvedBio) {
            moderationMessage = moderationError.localizedDescription
            showModerationAlert = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                currentStep = 3
            }
            return
        }

        let lf = legalFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ll = legalLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lf.isEmpty, !ll.isEmpty else {
            verificationNameInlineError = "Name: enter your first and last name exactly as on your ID."
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                currentStep = 1
            }
            return
        }

        guard let coordinate = verifiedHomeCoordinate,
              GeoAppConstants.isCoordinateInUS(coordinate) else {
            verificationAddressInlineError = "Map: tap your home (or My location). The pin must be inside the United States."
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                currentStep = 2
            }
            return
        }

        guard locationPermissionGranted else {
            finalSubmitInlineError = "Location: turn on location access to complete onboarding."
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { currentStep = 3 }
            return
        }

        let trimmedAddress = verificationHomeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressLineForProfile = trimmedAddress.isEmpty
            ? String(format: "%.5f°, %.5f°", coordinate.latitude, coordinate.longitude)
            : trimmedAddress

        let updatedUser = User(
            id: currentUser.id,
            email: currentUser.email,
            username: username,
            firstName: firstName,
            lastName: lastName,
            age: age,
            dateOfBirth: dateOfBirth,
            userType: .jobHirer,
            profileImageURL: currentUser.profileImageURL,
            profileImageData: profileImage?.jpegData(compressionQuality: 0.8),
            skills: [],
            description: resolvedBio,
            location: hasLocation ? Location(latitude: 0, longitude: 0, address: "Current Location") : nil,
            createdAt: currentUser.createdAt,
            parentalConsentGiven: nil,
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
            legalFirstNameOnId: lf,
            legalLastNameOnId: ll,
            identityDocumentURL: nil,
            identityVerificationSubmittedAt: Date(),
            verifiedHomeAddress: addressLineForProfile,
            verifiedHomeLatitude: coordinate.latitude,
            verifiedHomeLongitude: coordinate.longitude,
            stripeIdentityVerified: currentUser.stripeIdentityVerified,
            stripeIdentityVerifiedAt: currentUser.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: currentUser.stripeIdentityLastSessionId,
            qualificationAttachments: currentUser.qualificationAttachments,
            profileBannerImageData: currentUser.profileBannerImageData,
            pronouns: currentUser.pronouns,
            bioAttachmentData: currentUser.bioAttachmentData,
            parentEmail: currentUser.parentEmail,
            parentName: currentUser.parentName,
            parentApprovalToken: currentUser.parentApprovalToken,
            isParentalApproved: currentUser.isParentalApproved,
            parentApprovalDate: currentUser.parentApprovalDate
        )

        confettiTrigger += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            authManager.completeOnboarding(user: updatedUser)
        }
    }
}

// MARK: - Image Picker
/// How the picked image is processed. `UIImagePickerController` only offers a
/// **square** on-device crop. Profile photos use that square as-is (circle in UI).
/// Cover banners use the same square crop, then `communallyAsWideBannerFromCroppedImage`
/// maps it to a wide header so framing matches what the user chose.
enum ImagePickerCropMode: Equatable {
    case profile
    case banner
    case unmodified
}

// MARK: - UIImage (banner)
extension UIImage {
    /// Center-crop to a wide banner aspect (`width:height`, e.g. 3.2 ≈ app cover).
    /// Used when the user does not use the system crop (fallback).
    func communallyCroppedToBannerAspect(widthOverHeight: CGFloat = 3.2) -> UIImage? {
        guard size.width > 0, size.height > 0, widthOverHeight > 0 else { return self }
        let imageAspect = size.width / size.height
        let targetAspect = widthOverHeight
        var cropW: CGFloat
        var cropH: CGFloat
        if imageAspect > targetAspect {
            cropH = size.height
            cropW = cropH * targetAspect
        } else {
            cropW = size.width
            cropH = cropW / targetAspect
        }
        let x = (size.width - cropW) / 2.0
        let y = (size.height - cropH) / 2.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = self.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropW, height: cropH), format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(x: -x, y: -y, width: size.width, height: size.height))
        }
    }
    
    /// Map the system **square** crop (or any image) to a wide banner: scale to **aspect fill**
    /// a fixed output size, then clip. Matches how the profile header displays the banner
    /// and avoids a “random zoom” from center-slicing a full portrait.
    func communallyAsWideBannerFromCroppedImage(
        widthOverHeight: CGFloat = 3.2,
        outputWidth: CGFloat = 1200
    ) -> UIImage? {
        guard size.width > 0, size.height > 0, widthOverHeight > 0 else { return nil }
        let outW = outputWidth
        let outH = outW / widthOverHeight
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(self.scale, 3.0)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: format)
        return renderer.image { _ in
            let scale = max(outW / size.width, outH / size.height)
            let scaledW = size.width * scale
            let scaledH = size.height * scale
            let x = (outW - scaledW) / 2
            let y = (outH - scaledH) / 2
            self.draw(in: CGRect(x: x, y: y, width: scaledW, height: scaledH))
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    var cropMode: ImagePickerCropMode = .profile

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        switch cropMode {
        case .profile, .banner:
            // Square crop UI for both: avatars use the square as-is; cover photos are
            // converted to a wide banner with `communallyAsWideBannerFromCroppedImage`.
            picker.allowsEditing = true
        case .unmodified:
            picker.allowsEditing = false
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let result: UIImage?
            switch parent.cropMode {
            case .profile:
                if let edited = info[.editedImage] as? UIImage {
                    result = edited
                } else if let original = info[.originalImage] as? UIImage {
                    result = original
                } else {
                    result = nil
                }
            case .banner:
                // Prefer the system square crop, then map to a wide header banner.
                if let edited = info[.editedImage] as? UIImage {
                    result = edited.communallyAsWideBannerFromCroppedImage()
                } else if let original = info[.originalImage] as? UIImage {
                    result = original.communallyCroppedToBannerAspect()
                } else {
                    result = nil
                }
            case .unmodified:
                result = info[.originalImage] as? UIImage
            }
            parent.image = result
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    JobHirerOnboardingView()
        .environmentObject(AuthenticationManager.shared)
}

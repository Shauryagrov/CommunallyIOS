//
//  EditProfileView.swift
//  Communally
//
//  Profile editing screen - update name, photo, skills, bio
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import LocalAuthentication
import CoreLocation

struct EditProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let user: User
    
    @State private var username: String
    @State private var firstName: String
    @State private var lastName: String
    @State private var pronouns: String
    @State private var bio: String
    @State private var skills: [String]
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showCameraAlert = false
    @State private var isSaving = false
    @State private var showSuccessAlert = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool? = nil
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var showNameRestrictionAlert = false
    @State private var showUsernameRestrictionAlert = false
    @State private var showModerationAlert = false
    @State private var moderationMessage = ""
    @State private var dateOfBirth: Date
    @State private var bioAttachments: [UIImage]
    @State private var showBioAttachmentPicker = false
    // Home address change
    @State private var showHomeChangeUnlocked = false
    @State private var showHomeBiometricDenied = false
    @State private var newHomeAddress: String = ""
    @State private var newHomeCoordinate: CLLocationCoordinate2D? = nil
    @State private var bioAttachmentPickerIndex: Int = 0
    @State private var fullscreenAttachment: UIImage? = nil
    
    init(user: User) {
        self.user = user
        _username = State(initialValue: user.username ?? "")
        _firstName = State(initialValue: user.firstName)
        _lastName = State(initialValue: user.lastName)
        _pronouns = State(initialValue: user.pronouns ?? "")
        _bio = State(initialValue: user.description ?? "")
        let fallbackDOB = Calendar.current.date(byAdding: .year, value: -user.age, to: Date()) ?? Date()
        _dateOfBirth = State(initialValue: user.dateOfBirth ?? fallbackDOB)
        let validSkills = user.skills.filter { OpportunityCategory.allTitles.contains($0) }
        _skills = State(initialValue: validSkills)
        if let imageData = user.profileImageData,
           let image = UIImage(data: imageData) {
            _profileImage = State(initialValue: image)
        } else {
            _profileImage = State(initialValue: nil)
        }
        _bioAttachments = State(initialValue: user.bioAttachmentData.compactMap { UIImage(data: $0) })
    }

    private let pronounOptions = ["He/Him", "She/Her", "Prefer not to say", "Other"]

    private var pronounsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pronouns")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)

            Text("Optional — shown next to your @username.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.68))

            Menu {
                ForEach(pronounOptions, id: \.self) { option in
                    Button(option) { pronouns = option }
                }
                Divider()
                Button("Clear", role: .destructive) { pronouns = "" }
            } label: {
                HStack {
                    Text(pronouns.isEmpty ? "Select pronouns" : pronouns)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(pronouns.isEmpty ? CommunallyTheme.darkGray.opacity(0.4) : CommunallyTheme.darkGray)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private var bioAttachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bio Photos")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Spacer()
                Text("\(bioAttachments.count)/3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
            }

            Text("Up to 3 photos shown on your profile. Tap to enlarge.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    if i < bioAttachments.count {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: bioAttachments[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { fullscreenAttachment = bioAttachments[i] }

                            Button {
                                bioAttachments.remove(at: i)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                        }
                    } else {
                        Button {
                            bioAttachmentPickerIndex = i
                            showBioAttachmentPicker = true
                        } label: {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 88, height: 88)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.35))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .fullScreenCover(item: $fullscreenAttachment) { img in
            FullscreenImageView(image: img)
        }
    }
    
    private var profilePhotoSection: some View {
        VStack(spacing: 16) {
            Text("Profile Photo")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Current Photo
            Group {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                        )
                        .overlay(
                            Circle()
                                .stroke(CommunallyTheme.primaryGreen.opacity(0.85), lineWidth: 2)
                                .padding(2)
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
                } else {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.92))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        )
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 10, x: 0, y: 5)
                }
            }
            
            // Photo Buttons
            HStack(spacing: 12) {
                Button(action: {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        imageSourceType = .camera
                        showingImagePicker = true
                    } else {
                        showCameraAlert = true
                    }
                }) {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(CommunallyTheme.lightGray)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button(action: {
                    imageSourceType = .photoLibrary
                    showingImagePicker = true
                }) {
                    Label("Library", systemImage: "photo.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(CommunallyTheme.primaryGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    /// Username + name are now permanent — set during onboarding and can't be
    /// changed. The previous editable+cooldown UI was producing user-facing
    /// errors ("Cannot Change Name — please wait 10 more days") and the user
    /// asked for the affordance to be removed entirely.
    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Username")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
            }

            HStack(spacing: 4) {
                Text("@")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                Text(user.username ?? "")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CommunallyTheme.darkGray.opacity(0.05))
            )

            Text("Set when you signed up. Usernames can't be changed.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Name")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
            }

            HStack(spacing: 4) {
                Text(user.fullName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CommunallyTheme.darkGray.opacity(0.05))
            )

            Text("Set when you signed up. Names can't be changed.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private var editProfileDOBRange: ClosedRange<Date> {
        let minYears = user.userType == .jobHirer ? AppAgeRequirements.minimumHirerAge : AppAgeRequirements.minimumUserAge
        let maxBirth = Calendar.current.date(byAdding: .year, value: -minYears, to: Date()) ?? Date()
        let minBirth = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
        return minBirth...maxBirth
    }

    private var resolvedAgeForEdit: Int {
        User.ageFromDateOfBirth(dateOfBirth)
    }

    private var dateOfBirthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date of birth")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)

            Text("Your listed age updates automatically (currently \(resolvedAgeForEdit)).")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.75))

            DatePicker(
                "",
                selection: $dateOfBirth,
                in: editProfileDOBRange,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(user.userType == .jobSeeker ? "About" : "Bio")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if user.userType == .jobSeeker {
                Text("Short summary — like a LinkedIn headline. Add experience, studies, or what you’re looking for. You can attach certificates or a résumé below.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            TextEditor(text: $bio)
                .frame(height: user.userType == .jobSeeker ? 120 : 100)
                .padding(8)
                .scrollContentBackground(.hidden)   // hides TextEditor's own dark-mode bg
                .foregroundColor(.black)
                .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var homeAddressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .foregroundColor(CommunallyTheme.primaryGreen)
                Text("Home Address")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
            }

            let displayAddress: String? = (!newHomeAddress.isEmpty) ? newHomeAddress : user.verifiedHomeAddress
            if let addr = displayAddress {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(CommunallyTheme.primaryGreen)
                        .font(.system(size: 16))
                    Text(addr)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No home address set.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
            }

            if showHomeChangeUnlocked {
                AddressSearchWithMiniMap(addressLine: $newHomeAddress, resolvedCoordinate: $newHomeCoordinate)
                    .padding(.top, 4)
            } else {
                Button { verifyAndShowHomeChange() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 16))
                        Text("Change Home Address")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(CommunallyTheme.primaryGreen.opacity(0.35), lineWidth: 1.5)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    )
                }
                .buttonStyle(.plain)
            }

            if showHomeBiometricDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Biometric verification is required to change your home address.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private func verifyAndShowHomeChange() {
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        context.evaluatePolicy(policy, localizedReason: "Verify your identity to change your home address") { success, _ in
            DispatchQueue.main.async {
                if success {
                    showHomeChangeUnlocked = true
                    showHomeBiometricDenied = false
                } else {
                    showHomeBiometricDenied = true
                }
            }
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(user.userType == .jobSeeker ? "Work I’m interested in" : "Kinds of help I post about")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)

            Text(user.userType == .jobSeeker
                 ? "Job categories you’re open to — same list as job posts. Tap to add or remove."
                 : "Same categories as when someone posts a job on Communally. Tap to add or remove.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(OpportunityCategory.allTitles, id: \.self) { title in
                    let selected = skills.contains(title)
                    Button {
                        if selected {
                            skills.removeAll { $0 == title }
                        } else {
                            skills.append(title)
                        }
                    } label: {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(selected ? .white : CommunallyTheme.darkGray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .padding(.horizontal, 8)
                            .background(
                                selected
                                    ? AnyView(CommunallyTheme.buttonGradient)
                                    : AnyView(Color.white)
                            )
                            .cornerRadius(CommunallyTheme.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius)
                                    .stroke(selected ? Color.clear : Color.black.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    profilePhotoSection
                    usernameSection
                    nameSection
                    pronounsSection
                    dateOfBirthSection
                    bioSection
                    bioAttachmentsSection
                    if user.userType == .jobHirer || user.verifiedHomeAddress != nil {
                        homeAddressSection
                    }
                    skillsSection
                }
                .padding()
            }
            .background(CommunallyTheme.backgroundGradient)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                // Save in the top-right so users don't have to scroll all the
                // way down. Disabled when canSave is false; spinner while saving.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveProfile()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .disabled(isSaving || !canSave)
                    .accessibilityLabel("Save profile")
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $profileImage, cropMode: .profile)
        }
        .sheet(isPresented: $showBioAttachmentPicker) {
            BioAttachmentPicker { picked in
                if bioAttachments.count < 3 {
                    bioAttachments.append(picked)
                }
            }
        }
        .alert("Camera Not Available", isPresented: $showCameraAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Camera is not available on this device. Please use 'Choose Photo' instead.")
        }
        .alert("Profile Updated!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your profile has been successfully updated.")
        }
        .alert("Cannot Change Name", isPresented: $showNameRestrictionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can only change your name every 10 days. Please wait \(user.daysUntilNameChange) more days.")
        }
        .alert("Cannot Change Username", isPresented: $showUsernameRestrictionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can only change your username every 14 days. Please wait \(user.daysUntilUsernameChange) more days.")
        }
        .alert("Please Update This Text", isPresented: $showModerationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(moderationMessage)
        }
    }


    private var canSave: Bool {
        let nameValid = !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
                       !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        
        // Check if username is valid (if changed)
        if username != user.username && !username.isEmpty {
            return nameValid && usernameAvailable == true && user.canChangeUsername
        }
        
        return nameValid
    }
    
    private var isNameChanged: Bool {
        firstName.trimmingCharacters(in: .whitespaces) != user.firstName ||
        lastName.trimmingCharacters(in: .whitespaces) != user.lastName
    }
    
    private var isUsernameChanged: Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        return !trimmedUsername.isEmpty && trimmedUsername != user.username
    }
    
    private func checkUsernameAvailability() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        
        // Cancel previous check
        usernameCheckTask?.cancel()
        
        // If empty or same as current, skip check
        if trimmedUsername.isEmpty || trimmedUsername == user.username {
            usernameAvailable = nil
            isCheckingUsername = false
            return
        }
        
        // Start checking
        isCheckingUsername = true
        usernameAvailable = nil
        
        usernameCheckTask = Task {
            // Debounce - wait 500ms
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Check if task was cancelled
            if Task.isCancelled { return }
            
            // Check availability with completion handler
            UserDatabase.shared.checkUsernameAvailability(trimmedUsername) { isAvailable in
                if !Task.isCancelled {
                    self.usernameAvailable = isAvailable
                    self.isCheckingUsername = false
                }
            }
        }
    }
    
    private func saveProfile() {
        // Check restrictions
        if isNameChanged && !user.canChangeName {
            showNameRestrictionAlert = true
            return
        }
        
        if isUsernameChanged && !user.canChangeUsername {
            showUsernameRestrictionAlert = true
            return
        }
        
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBio.isEmpty,
           let moderationError = ContentModerationService.shared.validateProfileText(trimmedBio) {
            moderationMessage = moderationError.localizedDescription
            showModerationAlert = true
            return
        }
        
        isSaving = true
        LoadingOverlayManager.shared.show("Saving your profile…")

        // Update user data
        var imageData: Data? = user.profileImageData
        if let image = profileImage {
            imageData = image.jpegData(compressionQuality: 0.7)
        }
        
        // Custom banner uploads removed — always nil so everyone gets the
        // brand-green default gradient. Old corrupted banners are cleared
        // automatically the next time the user saves their profile.
        let bannerData: Data? = nil


        // Determine new change dates
        let newLastUsernameChange = isUsernameChanged ? Date() : user.lastUsernameChange
        let newLastNameChange = isNameChanged ? Date() : user.lastNameChange
        
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedPronouns = pronouns.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAge = User.ageFromDateOfBirth(dateOfBirth)

        // Create updated user
        let updatedUser = User(
            id: user.id,
            email: user.email,
            username: trimmedUsername.isEmpty ? user.username : trimmedUsername,
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            age: newAge,
            dateOfBirth: dateOfBirth,
            userType: user.userType,
            profileImageURL: user.profileImageURL,
            profileImageData: imageData,
            skills: skills,
            description: trimmedBio.isEmpty ? nil : trimmedBio,
            location: user.location,
            createdAt: user.createdAt,
            parentalConsentGiven: newAge < 18 ? user.parentalConsentGiven : nil,
            hasCompletedOnboarding: user.hasCompletedOnboarding,
            acceptedTermsDate: user.acceptedTermsDate,
            acceptedPrivacyDate: user.acceptedPrivacyDate,
            lastUsernameChange: newLastUsernameChange,
            lastNameChange: newLastNameChange,
            stripeCustomerId: user.stripeCustomerId,
            stripeConnectAccountId: user.stripeConnectAccountId,
            stripeConnectActive: user.stripeConnectActive,
            stripeConnectDetailsSubmitted: user.stripeConnectDetailsSubmitted,
            bankAccountConnected: user.bankAccountConnected,
            stripeConnectedAccountId: user.stripeConnectedAccountId,
            appleUserId: user.appleUserId,
            legalFirstNameOnId: user.legalFirstNameOnId,
            legalLastNameOnId: user.legalLastNameOnId,
            identityDocumentURL: user.identityDocumentURL,
            identityVerificationSubmittedAt: user.identityVerificationSubmittedAt,
            verifiedHomeAddress: (showHomeChangeUnlocked && !newHomeAddress.isEmpty) ? newHomeAddress : user.verifiedHomeAddress,
            verifiedHomeLatitude: (showHomeChangeUnlocked && newHomeCoordinate != nil) ? newHomeCoordinate?.latitude : user.verifiedHomeLatitude,
            verifiedHomeLongitude: (showHomeChangeUnlocked && newHomeCoordinate != nil) ? newHomeCoordinate?.longitude : user.verifiedHomeLongitude,
            stripeIdentityVerified: user.stripeIdentityVerified,
            stripeIdentityVerifiedAt: user.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: user.stripeIdentityLastSessionId,
            qualificationAttachments: user.qualificationAttachments,
            profileBannerImageData: bannerData,
            pronouns: trimmedPronouns.isEmpty ? nil : trimmedPronouns,
            bioAttachmentData: bioAttachments.compactMap { $0.jpegData(compressionQuality: 0.65) },
            // Preserve parental approval state across edits — without these
            // an under-18 seeker editing their profile would lose approval.
            parentEmail: user.parentEmail,
            parentName: user.parentName,
            parentApprovalToken: user.parentApprovalToken,
            isParentalApproved: user.isParentalApproved,
            parentApprovalDate: user.parentApprovalDate
        )

        // Save to database
        authManager.updateUser(updatedUser)
        
        // Show success and dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            LoadingOverlayManager.shared.hide()
            showSuccessAlert = true
        }
    }
}

// MARK: - Bio attachment photo picker

struct BioAttachmentPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: BioAttachmentPicker
        init(_ parent: BioAttachmentPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onPick(img)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Fullscreen image viewer

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

struct FullscreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, Color.black.opacity(0.5))
                    .padding(20)
            }
        }
    }
}

// MARK: - Custom Text Field Style
struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.black) // typed text always visible
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
    }
}

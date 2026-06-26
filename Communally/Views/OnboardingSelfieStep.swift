//
//  OnboardingSelfieStep.swift
//  Communally
//
//  Dedicated onboarding step for the profile face-photo. Branches on age:
//    • 18+   → live front-camera selfie (primary), library as fallback
//    • <18   → upload a clear face photo from the library (no live camera)
//
//  The parent owns the actual UIImagePickerController presentation (so the
//  existing camera-availability + permission alerts keep working); this view
//  just renders the step and calls back via onTakeSelfie / onChoosePhoto.
//

import SwiftUI

struct OnboardingSelfieStep: View {
    @Binding var image: UIImage?
    let age: Int
    var onTakeSelfie: () -> Void
    var onChoosePhoto: () -> Void

    private var isAdult: Bool { age >= 18 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingStepTitle(
                    emoji: isAdult ? "🤳" : "📸",
                    title: isAdult ? "Take a Selfie" : "Add Your Photo"
                )

                Text(isAdult
                     ? "This becomes your profile photo so neighbors know who they're meeting. A clear photo of your face builds trust."
                     : "Upload a clear photo of your face. This becomes your profile photo so neighbors know who they're meeting.")
                    .font(CommunallyTheme.secondaryText)
                    .foregroundColor(CommunallyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                photoPreview
                    .padding(.vertical, 6)

                VStack(spacing: 10) {
                    if isAdult {
                        primaryButton(
                            title: image == nil ? "Take Selfie" : "Retake Selfie",
                            systemImage: "camera.fill",
                            action: onTakeSelfie
                        )
                        Button(action: onChoosePhoto) {
                            Text("Choose from library instead")
                                .font(CommunallyTheme.secondaryText)
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                    } else {
                        primaryButton(
                            title: image == nil ? "Choose Photo" : "Choose Different Photo",
                            systemImage: "photo.on.rectangle",
                            action: onChoosePhoto
                        )
                    }
                }
                .padding(.horizontal, 24)

                Text(isAdult
                     ? "Make sure your face is clearly visible and well-lit."
                     : "Photos with a clear, visible face help keep Communally safe.")
                    .font(CommunallyTheme.captionText)
                    .foregroundColor(CommunallyTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var photoPreview: some View {
        ZStack {
            Circle()
                .fill(CommunallyTheme.lightGray)
                .frame(width: 180, height: 180)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 70))
                    .foregroundColor(CommunallyTheme.midGray)
            }

            Circle()
                .strokeBorder(CommunallyTheme.primaryGreen.opacity(0.45), lineWidth: 3)
                .frame(width: 180, height: 180)
        }
        .overlay(alignment: .bottomTrailing) {
            if image != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .background(Circle().fill(CommunallyTheme.surface))
                    .offset(x: -8, y: -8)
            }
        }
        .accessibilityLabel(image == nil ? "No photo selected yet" : "Photo selected")
    }

    private func primaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(CommunallyTheme.primaryGreen)
        .controlSize(.large)
    }
}

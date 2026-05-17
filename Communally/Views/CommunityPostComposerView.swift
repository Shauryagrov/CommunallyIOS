//
//  CommunityPostComposerView.swift
//  Communally
//
//  Photo + caption composer used to create a CommunityPost. Photo-only
//  (no video) for build 6 — keeps storage costs predictable while we
//  decide on the moderation pipeline. Re-uses `ImagePicker` from the
//  shared component layer (same one onboarding uses).
//

import SwiftUI
import UIKit

struct CommunityPostComposerView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var manager = CommunityPostManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pickedImage: UIImage?
    @State private var caption: String = ""
    @State private var showImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showSourceSheet = false
    @State private var showCameraUnavailable = false
    @State private var inlineError: String?

    private let captionLimit = 280

    private var canPost: Bool {
        // Photo OR non-empty caption — both optional individually, just need
        // at least one of the two so we don't ship empty posts.
        let hasCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (pickedImage != nil || hasCaption) && !manager.isPosting
    }

    private var cityHint: String {
        guard let city = authManager.currentUser?.homeCity, !city.isEmpty else {
            return "Verify your home address first"
        }
        return "Visible only in \(city)"
    }

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        photoPickerCard
                        captionCard
                        if let inlineError {
                            errorBanner(inlineError)
                        }
                        scopeRow
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) {
                        if manager.isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Post")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .disabled(!canPost)
                    .foregroundColor(canPost ? CommunallyTheme.primaryGreen : CommunallyTheme.darkGray.opacity(0.35))
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showSourceSheet, titleVisibility: .hidden) {
                Button("Take Photo") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        imageSource = .camera
                        showImagePicker = true
                    } else {
                        showCameraUnavailable = true
                    }
                }
                Button("Choose Photo") {
                    imageSource = .photoLibrary
                    showImagePicker = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $pickedImage, sourceType: imageSource)
            }
            .alert("Camera Not Available", isPresented: $showCameraUnavailable) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Camera isn't available on this device. Use 'Choose Photo' instead.")
            }
        }
    }

    // MARK: - Sections

    private var photoPickerCard: some View {
        Button {
            showSourceSheet = true
        } label: {
            ZStack {
                if let image = pickedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            // Subtle "tap to change" hint
                            Text("Change")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .padding(10)
                        }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                        Text("Add a photo (optional)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        Text("Tap to attach · or post text-only")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CommunallyTheme.primaryGreen.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if caption.isEmpty {
                    Text("Say something to your neighbors…")
                        .font(.system(size: 15))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $caption)
                    .frame(minHeight: 110)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(CommunallyTheme.darkGray)
                    .onChange(of: caption) { _, newValue in
                        if newValue.count > captionLimit {
                            caption = String(newValue.prefix(captionLimit))
                        }
                        inlineError = nil
                    }
            }
            HStack {
                Spacer()
                Text("\(caption.count) / \(captionLimit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                    .padding(.trailing, 10)
                    .padding(.bottom, 6)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CommunallyTheme.primaryGreen.opacity(0.18), lineWidth: 1)
        )
    }

    private var scopeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(CommunallyTheme.primaryGreen)
            Text(cityHint)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CommunallyTheme.primaryGreen.opacity(0.08))
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.red.opacity(0.85))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func post() {
        guard let user = authManager.currentUser else {
            inlineError = "You need to sign in first."
            return
        }
        // Photo is optional now — encode it if present, send nil otherwise.
        var photoData: Data? = nil
        if let image = pickedImage {
            guard let encoded = image.jpegData(compressionQuality: 0.82) else {
                inlineError = "Couldn't read that photo — try another one."
                return
            }
            photoData = encoded
        }
        manager.createPost(author: user, photoData: photoData, caption: caption) { result in
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            case .failure(let err):
                inlineError = err.localizedDescription
            }
        }
    }
}

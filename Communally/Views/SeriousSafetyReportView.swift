//
//  SeriousSafetyReportView.swift
//  Communally
//
//  Dedicated report flow for sexual assault, physical assault, or violence.
//  Step 1: Immediate safety / emergency services
//  Step 2: Crisis support lines
//  Step 3: Report form → immediate account suspension + admin alert
//

import SwiftUI

// MARK: - Main flow

struct SeriousSafetyReportView: View {
    let reportedUserId: String
    let reportedUserName: String
    let relatedJobId: String?
    let relatedJobTitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 1
    @State private var reportType: ReportType = .sexualAssault
    @State private var descriptionText: String = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var submitError: String?

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepIndicator

                        Group {
                            switch step {
                            case 1: immediacySafetyStep
                            case 2: crisisResourcesStep
                            default: reportFormStep
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Safety Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("Report Submitted", isPresented: $submitted) {
            Button("OK") { dismiss() }
        } message: {
            Text("We have received your report. \(reportedUserName)'s account has been flagged for immediate review and they can no longer contact you. If you are in danger, please call 999 or your local emergency number.")
        }
        .alert("Couldn't Submit", isPresented: Binding(get: { submitError != nil }, set: { if !$0 { submitError = nil } })) {
            Button("OK", role: .cancel) { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { n in
                Capsule()
                    .fill(step >= n ? Color.red : Color.gray.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Step 1: Are you safe right now?

    private var immediacySafetyStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundColor(.red)
                }

                Text("Are you safe right now?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .multilineTextAlignment(.center)

                Text("Your safety comes first. If you are in immediate danger, call 999 or your local emergency services right now.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Emergency call button — very prominent
            emergencyCallButton

            // I'm now safe
            VStack(spacing: 14) {
                Text("If you are now safe and want to report what happened:")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation { step = 2 }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("I'm Safe — Continue Report")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                colors: [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.82)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                    )
                }

                Button("Close — I'll do this later") { dismiss() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Step 2: Crisis resources

    private var crisisResourcesStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))

                Text("Support Is Available")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)

                Text("You are not alone. These confidential services are free and available 24/7.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                crisisLine(
                    name: "Emergency Services",
                    subtitle: "Police / Ambulance",
                    phone: "999",
                    color: .red,
                    icon: "phone.badge.plus.fill"
                )
                crisisLine(
                    name: "Rape Crisis England & Wales",
                    subtitle: "Freephone · 24/7",
                    phone: "08088029999",
                    color: Color(red: 0.7, green: 0.1, blue: 0.4),
                    icon: "phone.fill"
                )
                crisisLine(
                    name: "RAINN National Hotline",
                    subtitle: "US: Sexual Assault · 24/7",
                    phone: "18006564673",
                    color: Color(red: 0.55, green: 0.1, blue: 0.6),
                    icon: "phone.fill"
                )
                crisisLine(
                    name: "National Domestic Abuse Helpline",
                    subtitle: "Freephone · 24/7",
                    phone: "08082000247",
                    color: Color(red: 0.85, green: 0.45, blue: 0.1),
                    icon: "phone.fill"
                )
                crisisLine(
                    name: "Victim Support",
                    subtitle: "UK — free, confidential",
                    phone: "08081689111",
                    color: Color(red: 0.2, green: 0.4, blue: 0.8),
                    icon: "phone.fill"
                )
            }

            VStack(spacing: 12) {
                Text("When you're ready, continue to file your report. This will immediately flag the user's account.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation { step = 3 }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Continue to Report")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.red)
                    )
                }

                Button { withAnimation { step = 1 } } label: {
                    Text("Back")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Step 3: Report form

    private var reportFormStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Report Type")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)

                VStack(spacing: 10) {
                    criticalTypeButton(.sexualAssault)
                    criticalTypeButton(.physicalAssault)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Reporting")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)

                Text(reportedUserName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.08))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What happened?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)

                Text("Describe what occurred. Include date, time, and location if possible. You do not need to include any details you're not comfortable sharing.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)

                TextEditor(text: $descriptionText)
                    .foregroundColor(.black)
                    .scrollContentBackground(.hidden)
                    .frame(height: 130)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    )
            }

            // What happens next
            VStack(alignment: .leading, spacing: 10) {
                Text("What happens when you submit:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)

                VStack(alignment: .leading, spacing: 8) {
                    nextStepRow(icon: "person.fill.xmark", text: "\(reportedUserName) is immediately blocked from contacting you", color: .red)
                    nextStepRow(icon: "lock.shield.fill", text: "Their account is flagged for emergency review", color: .orange)
                    nextStepRow(icon: "envelope.badge.fill", text: "Communally's admin team is alerted immediately", color: Color(red: 0.2, green: 0.4, blue: 0.8))
                    nextStepRow(icon: "checkmark.shield.fill", text: "Your identity remains confidential", color: CommunallyTheme.primaryGreen)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                )
            }

            Button(action: submitReport) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Submit Report Now")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSubmitting || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
                              ? Color.gray.opacity(0.45)
                              : Color.red)
                )
            }
            .disabled(isSubmitting || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("Your report is completely confidential. We will never show your identity to the reported person.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button { withAnimation { step = 2 } } label: {
                Text("Back")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sub-components

    private var emergencyCallButton: some View {
        Button {
            if let url = URL(string: "tel:999") { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 44, height: 44)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Call 999 — Emergency")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("Police · Ambulance · Fire")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.85, green: 0.1, blue: 0.1), Color(red: 0.65, green: 0.05, blue: 0.05)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .shadow(color: Color.red.opacity(0.45), radius: 16, x: 0, y: 8)
            )
        }
    }

    private func crisisLine(name: String, subtitle: String, phone: String, color: Color, icon: String) -> some View {
        Button {
            if let url = URL(string: "tel:\(phone)") { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "phone.arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func criticalTypeButton(_ type: ReportType) -> some View {
        Button { reportType = type } label: {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(reportType == type ? .white : .red)
                    .frame(width: 30)

                Text(type.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(reportType == type ? .white : CommunallyTheme.darkGray)

                Spacer()

                if reportType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(reportType == type ? Color.red : Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    private func nextStepRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Submit

    private func submitReport() {
        guard !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSubmitting = true
        submitError = nil

        SafetyManager.shared.submitCriticalSafetyReport(
            reportedUserId: reportedUserId,
            reportedUserName: reportedUserName,
            type: reportType,
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            relatedJobId: relatedJobId,
            relatedJobTitle: relatedJobTitle
        ) { success, error in
            DispatchQueue.main.async {
                isSubmitting = false
                if success {
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                    submitted = true
                } else {
                    submitError = error ?? "An error occurred. Please try again."
                }
            }
        }
    }
}

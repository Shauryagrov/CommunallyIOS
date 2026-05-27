//
//  WelcomeTutorialView.swift
//  Communally
//
//  Friendly post-onboarding tutorial starring Bambu the panda.
//  Shown once after a user completes onboarding (tracked via UserDefaults).
//  Can be re-played from Profile → Settings → "Replay tutorial".
//
//  Slides differ by user role:
//    - .jobSeeker → "find gigs, apply, get paid" arc
//    - .jobHirer  → "post a job, pick a person, pay safely" arc
//
//  Last slide CTA dismisses and writes the seen-flag.
//

import SwiftUI

struct WelcomeTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    let userType: UserType
    let userFirstName: String?

    @State private var pageIndex: Int = 0
    private var slides: [TutorialSlide] { Self.slides(for: userType, firstName: userFirstName) }

    var body: some View {
        ZStack {
            // Soft cream + green ambient background
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.98, blue: 0.94),
                    Color(red: 1.00, green: 0.98, blue: 0.93)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Floating soft blobs for warmth
            Circle()
                .fill(Color(red: 0.74, green: 0.94, blue: 0.78).opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: -260)
            Circle()
                .fill(Color(red: 0.99, green: 0.87, blue: 0.78).opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 140, y: 240)

            VStack(spacing: 0) {
                // Skip button (top-right) — disappears on the last slide so the
                // primary action is the "Let's go" button.
                HStack {
                    Spacer()
                    if pageIndex < slides.count - 1 {
                        Button("Skip") { complete() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.46, blue: 0.42))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(Color.white.opacity(0.7))
                            )
                            .padding(.trailing, 18)
                            .padding(.top, 14)
                    } else {
                        // keep height stable
                        Color.clear.frame(width: 1, height: 40)
                    }
                }

                TabView(selection: $pageIndex) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        slideView(slide)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: pageIndex)

                // Page dots + primary CTA
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(0..<slides.count, id: \.self) { i in
                            Capsule()
                                .fill(i == pageIndex
                                      ? CommunallyTheme.primaryGreen
                                      : Color(red: 0.85, green: 0.88, blue: 0.85))
                                .frame(width: i == pageIndex ? 26 : 8, height: 8)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pageIndex)
                        }
                    }

                    Button(action: next) {
                        HStack(spacing: 8) {
                            Text(pageIndex == slides.count - 1 ? "Let's go" : "Next")
                                .font(.system(size: 16, weight: .semibold))
                            if pageIndex < slides.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [
                                        CommunallyTheme.primaryGreen,
                                        Color(red: 0.082, green: 0.502, blue: 0.282)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4),
                                        radius: 16, x: 0, y: 8)
                        )
                    }
                    .padding(.horizontal, 24)
                    .buttonStyle(InteractiveButtonStyle(scaleAmount: 0.97, hapticStyle: .medium))
                }
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Slide layout

    @ViewBuilder
    private func slideView(_ slide: TutorialSlide) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            ZStack {
                // Halo behind Bambu
                Circle()
                    .fill(slide.accent.opacity(0.18))
                    .frame(width: 280, height: 280)
                    .blur(radius: 8)
                BambuMascotView(size: 220, waving: slide.waving)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                // Eyebrow / tag
                Text(slide.eyebrow)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(slide.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(slide.accent.opacity(0.12))
                    )

                Text(slide.title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CommunallyTheme.darkGray)
                    .padding(.horizontal, 28)

                Text(slide.body)
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.36, green: 0.40, blue: 0.36))
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func next() {
        if pageIndex < slides.count - 1 {
            withAnimation(.easeInOut(duration: 0.32)) {
                pageIndex += 1
            }
        } else {
            complete()
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: WelcomeTutorialView.seenKey(for: userType))
        dismiss()
    }

    // MARK: - Persistence key

    /// Stored separately by role so a user who switches role gets the matching tutorial.
    static func seenKey(for userType: UserType) -> String {
        switch userType {
        case .jobSeeker: return "communally.tutorial.seen.seeker"
        case .jobHirer:  return "communally.tutorial.seen.hirer"
        }
    }

    static func hasSeen(for userType: UserType) -> Bool {
        UserDefaults.standard.bool(forKey: seenKey(for: userType))
    }

    static func resetSeenFlag(for userType: UserType) {
        UserDefaults.standard.removeObject(forKey: seenKey(for: userType))
    }
}

// MARK: - Slide content

private struct TutorialSlide {
    let eyebrow: String
    let title: String
    let body: String
    let accent: Color
    let waving: Bool
}

extension WelcomeTutorialView {
    // `fileprivate` because the return type `TutorialSlide` is `private` to
    // this file — Swift requires the function's access level be no broader
    // than its result type.
    fileprivate static func slides(for userType: UserType, firstName: String?) -> [TutorialSlide] {
        let name = firstName?.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let hello = name.isEmpty ? "Hey friend" : "Hey \(name)"
        let green   = CommunallyTheme.primaryGreen
        let peach   = Color(red: 0.97, green: 0.45, blue: 0.09)
        let butter  = Color(red: 0.97, green: 0.62, blue: 0.20)
        let sky     = Color(red: 0.20, green: 0.55, blue: 0.85)

        switch userType {
        case .jobSeeker:
            return [
                TutorialSlide(
                    eyebrow: "MEET BAMBU",
                    title: "\(hello)! I'm Bambu 🌿",
                    body: "Your guide to Communally. I'll show you how to find gigs near you and start earning — it takes a minute.",
                    accent: green,
                    waving: true
                ),
                TutorialSlide(
                    eyebrow: "STEP 1",
                    title: "See what's nearby",
                    body: "Open the map to see every gig within 5 miles. Tap any pin to see the job, the hirer, and the pay.",
                    accent: sky,
                    waving: false
                ),
                TutorialSlide(
                    eyebrow: "STEP 2",
                    title: "Apply in one tap",
                    body: "Like a gig? Tap apply. It starts a chat with the hirer right inside the app — your phone number stays private.",
                    accent: butter,
                    waving: false
                ),
                TutorialSlide(
                    eyebrow: "STEP 3",
                    title: "Get paid, same day",
                    body: "Finish the job, both sides confirm, then tap claim. Money lands in your bank. That's it. 🎉",
                    accent: green,
                    waving: true
                ),
            ]

        case .jobHirer:
            return [
                TutorialSlide(
                    eyebrow: "MEET BAMBU",
                    title: "\(hello)! I'm Bambu 🌿",
                    body: "Your guide to Communally. I'll show you how to find help in your neighborhood in three quick steps.",
                    accent: green,
                    waving: true
                ),
                TutorialSlide(
                    eyebrow: "STEP 1",
                    title: "Post what you need",
                    body: "Pick a category, set a fair hourly rate, choose a time window. Done in 30 seconds.",
                    accent: peach,
                    waving: false
                ),
                TutorialSlide(
                    eyebrow: "STEP 2",
                    title: "Pick from real neighbors",
                    body: "Every applicant is verified. Browse ratings, reviews and skills, then choose who you like.",
                    accent: sky,
                    waving: false
                ),
                TutorialSlide(
                    eyebrow: "STEP 3",
                    title: "Pay safely, when it's done",
                    body: "Funds are held in escrow and only released when both sides confirm the job is complete. No awkward Venmo back-and-forth.",
                    accent: green,
                    waving: true
                ),
            ]
        }
    }
}

#Preview("Seeker tutorial") {
    WelcomeTutorialView(userType: .jobSeeker, userFirstName: "Alex")
}

#Preview("Hirer tutorial") {
    WelcomeTutorialView(userType: .jobHirer, userFirstName: "Jordan")
}

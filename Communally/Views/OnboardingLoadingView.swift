//
//  OnboardingLoadingView.swift
//  Communally
//
//  First-launch rollup shown the very first time a user lands on the
//  dashboard. Spins the logo, cycles through cheeky copy, fills a progress
//  bar, then dismisses via the `onFinish` callback.
//

import SwiftUI

struct OnboardingLoadingView: View {
    /// Called when the rollup finishes (~3.8s in). Caller dismisses the cover.
    var onFinish: () -> Void = {}

    @State private var progress: Double = 0.0
    @State private var messageIndex = 0
    @State private var logoSpin = false
    @State private var haloRotation = false
    @State private var orbDrift = false
    @State private var entered = false

    private let messages: [String] = [
        "Spinning up your account…",
        "Hyping your vibe ✨",
        "Calibrating neighborhood energy…",
        "Loading the goods…",
        "Almost there bestie…",
        "Lock in 🔥"
    ]

    /// Total time the screen is on screen, in seconds.
    private let duration: Double = 3.8

    var body: some View {
        ZStack {
            // Brand green gradient — deep emerald → primary green → light mint.
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.30, blue: 0.18),
                    Color(red: 0.10, green: 0.55, blue: 0.34),
                    Color(red: 0.18, green: 0.78, blue: 0.50),
                    Color(red: 0.55, green: 0.95, blue: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft floating green glows — same vibe family.
            Circle()
                .fill(Color(red: 0.55, green: 0.95, blue: 0.72).opacity(0.65))
                .frame(width: 360)
                .blur(radius: 90)
                .offset(x: orbDrift ? -120 : -180, y: orbDrift ? -200 : -260)
                .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: orbDrift)

            Circle()
                .fill(Color(red: 0.20, green: 0.85, blue: 0.55).opacity(0.55))
                .frame(width: 320)
                .blur(radius: 80)
                .offset(x: orbDrift ? 180 : 140, y: orbDrift ? 220 : 280)
                .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: orbDrift)

            Circle()
                .fill(Color(red: 0.78, green: 0.99, blue: 0.86).opacity(0.45))
                .frame(width: 280)
                .blur(radius: 70)
                .offset(x: orbDrift ? -40 : 40, y: orbDrift ? 60 : 120)
                .animation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true), value: orbDrift)

            VStack(spacing: 38) {
                Spacer()

                // Spinning logo with rainbow halo
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.95, green: 0.40, blue: 0.85),
                                    Color(red: 0.35, green: 0.65, blue: 1.00),
                                    Color(red: 0.30, green: 0.95, blue: 0.70),
                                    Color(red: 1.00, green: 0.78, blue: 0.30),
                                    Color(red: 0.95, green: 0.40, blue: 0.85)
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 22)
                        .opacity(0.85)
                        .rotationEffect(.degrees(haloRotation ? 360 : 0))
                        .animation(.linear(duration: 6.0).repeatForever(autoreverses: false), value: haloRotation)

                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 170, height: 170)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.30), lineWidth: 1.5)
                        )

                    Image("CommunallyLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(logoSpin ? 360 : 0))
                        .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: logoSpin)
                        .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 6)
                }
                .scaleEffect(entered ? 1.0 : 0.85)
                .opacity(entered ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.78), value: entered)

                // Cheeky message — fades in as it changes
                Text(messages[messageIndex])
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(-0.3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .id(messageIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                // Progress bar + percentage
                VStack(spacing: 10) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 8)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.00, green: 0.78, blue: 0.30),
                                            Color(red: 0.95, green: 0.40, blue: 0.85),
                                            Color(red: 0.35, green: 0.65, blue: 1.00)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 8)
                                .shadow(color: Color(red: 0.95, green: 0.40, blue: 0.85).opacity(0.55), radius: 8, x: 0, y: 0)
                                .animation(.easeInOut(duration: 0.25), value: progress)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, 50)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .monospacedDigit()
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear { startLoading() }
    }

    private func startLoading() {
        logoSpin = true
        haloRotation = true
        orbDrift = true
        entered = true

        // Drive progress smoothly to 100% over `duration`.
        let tickInterval: Double = 0.04
        let totalTicks = Int(duration / tickInterval)
        let increment = 1.0 / Double(totalTicks)
        var ticks = 0

        Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { timer in
            ticks += 1
            let nextProgress = min(1.0, Double(ticks) * increment)
            progress = nextProgress

            // Cycle messages roughly evenly across the bar.
            let segment = 1.0 / Double(messages.count)
            let targetIndex = min(messages.count - 1, Int(nextProgress / segment))
            if targetIndex != messageIndex {
                withAnimation(.easeInOut(duration: 0.35)) {
                    messageIndex = targetIndex
                }
            }

            if nextProgress >= 1.0 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFinish()
                }
            }
        }
    }
}

#Preview {
    OnboardingLoadingView(onFinish: {})
}

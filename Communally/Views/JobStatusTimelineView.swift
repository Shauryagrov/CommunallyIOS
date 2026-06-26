//
//  JobStatusTimelineView.swift
//  Communally
//
//  Uber-style status timeline shown to the HIRER while a seeker travels to an
//  accepted job: Accepted → On the way → Nearby → Arrived. Driven by
//  `stage` (0...3), which ActiveJobView derives from the seeker's live
//  journey status + distance. Pure presentation — no data access.
//

import SwiftUI

struct JobStatusTimelineView: View {
    /// 0 = Accepted, 1 = On the way, 2 = Nearby, 3 = Arrived.
    let stage: Int
    /// Optional "12 min" ETA shown next to the current step (hidden once arrived).
    var etaText: String? = nil

    private struct Step { let title: String; let icon: String }
    private let steps: [Step] = [
        Step(title: "Accepted", icon: "checkmark"),
        Step(title: "On the way", icon: "car.fill"),
        Step(title: "Nearby", icon: "mappin.and.ellipse"),
        Step(title: "Arrived", icon: "flag.checkered")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Worker status")
                    .font(CommunallyTheme.sectionHeader)
                    .foregroundColor(CommunallyTheme.textPrimary)
                Spacer()
                if let etaText, stage < 3 {
                    Label(etaText, systemImage: "clock.arrow.circlepath")
                        .font(CommunallyTheme.captionText)
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
            }
            .padding(.bottom, 12)

            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                row(idx: idx, step: step)
            }
        }
        .communallyCard()
    }

    @ViewBuilder
    private func row(idx: Int, step: Step) -> some View {
        let isDone = idx <= stage
        let isCurrent = idx == stage
        HStack(alignment: .top, spacing: 12) {
            // Node + connector
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isDone ? CommunallyTheme.primaryGreen : CommunallyTheme.lightGray)
                        .frame(width: 30, height: 30)
                    if isCurrent && stage < 3 {
                        Circle()
                            .strokeBorder(CommunallyTheme.primaryGreen.opacity(0.35), lineWidth: 4)
                            .frame(width: 38, height: 38)
                    }
                    Image(systemName: step.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isDone ? .white : CommunallyTheme.midGray)
                }
                if idx < steps.count - 1 {
                    Rectangle()
                        .fill(idx < stage ? CommunallyTheme.primaryGreen : CommunallyTheme.lightGray)
                        .frame(width: 3, height: 22)
                }
            }

            Text(step.title)
                .font(.system(size: 15, weight: isCurrent ? .bold : .medium))
                .foregroundColor(isDone ? CommunallyTheme.textPrimary : CommunallyTheme.textSecondary)
                .padding(.top, 5)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title)\(isDone ? ", done" : "")")
    }
}

#Preview {
    VStack(spacing: 16) {
        JobStatusTimelineView(stage: 1, etaText: "12 min")
        JobStatusTimelineView(stage: 3)
    }
    .padding()
}

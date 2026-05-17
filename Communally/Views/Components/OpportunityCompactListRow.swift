//
//  OpportunityCompactListRow.swift
//  Communally
//
//  Shared compact row for hirer "My Jobs" and seeker opportunity browse.
//

import SwiftUI

struct OpportunityCompactListRow: View {
    let opportunity: Opportunity
    let subtitle: String
    /// When true, the subtitle renders as a brand-green call-to-action chip
    /// (bold, with an inbox icon) instead of muted gray body text. Used by
    /// the hirer's "Open" tab so "Review N applicant" doesn't get lost in the
    /// row.
    var subtitleHighlight: Bool = false
    /// When true, shows the applicant capsule (person.2 + count).
    var showApplicantBadge: Bool = false
    /// When true, replaces the chevron with a green "Applied" pill so the
    /// seeker sees at a glance which jobs they've already applied for.
    var hasAlreadyApplied: Bool = false
    var onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(JobTypeHelper.emoji(for: opportunity.jobType))
                        .font(.system(size: 28))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(opportunity.title)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .lineLimit(1)

                        if subtitleHighlight {
                            HStack(spacing: 5) {
                                Image(systemName: "tray.full.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(subtitle)
                                    .font(.system(size: 12, weight: .bold, design: .default))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.30), radius: 4, x: 0, y: 2)
                        } else {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 6) {
                            Text(opportunity.displayPay)
                                .font(.system(size: 14, weight: .bold, design: .default))
                                .foregroundColor(CommunallyTheme.primaryGreen)

                            if let label = opportunity.expiryLabel {
                                Text(label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(opportunity.expiresSoon ? .orange : .red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill((opportunity.expiresSoon ? Color.orange : Color.red).opacity(0.12))
                                    )
                            }
                        }
                    }

                    Spacer(minLength: 6)

                    if hasAlreadyApplied {
                        appliedBadge
                    } else if showApplicantBadge && opportunity.applicantCount > 0 {
                        applicantBadge(count: opportunity.applicantCount)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.gray.opacity(0.45))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CommunallyTheme.lightGray, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.red.opacity(0.92)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appliedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Applied")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.2)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.25))
        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 5, x: 0, y: 2)
    }

    private func applicantBadge(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .bold))
            Text("\(count)")
                .font(.system(size: 15, weight: .bold, design: .default))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.55, blue: 0.2),
                            Color(red: 1.0, green: 0.4, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: Color.orange.opacity(0.45), radius: 5, x: 0, y: 2)
    }
}

extension Opportunity {
    /// City/area line plus relative time — matches map-card privacy for seekers.
    var compactListSubtitleSeeker: String {
        let short = Opportunity.shortGeneralLocation(locationName)
        return "\(short) · \(timeAgo)"
    }

    static func shortGeneralLocation(_ fullName: String) -> String {
        let components = fullName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count >= 2 {
            return components.suffix(2).joined(separator: ", ")
        }
        return fullName
    }
}

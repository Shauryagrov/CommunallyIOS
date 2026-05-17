//
//  TermsAndConditionsView.swift
//  Communally
//
//  Created by Cursor on 11/30/25.
//

import SwiftUI

struct TermsAndConditionsView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terms and Conditions")
                            .font(.system(size: 28, weight: .bold, design: .default))
                        
                        Text("Last Updated: April 29, 2026")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // Introduction
                    Section {
                        SectionTitle(title: "1. Acceptance of Terms")
                        SectionBody(text: """
                        By accessing or using Communally ("Communally," "we," "our," or "us"), you agree to these Terms of Service. Communally is a technology platform that helps users discover opportunities, communicate, and arrange local services. If you do not agree, do not use the app.
                        """)
                    }
                    
                    // User Accounts
                    Section {
                        SectionTitle(title: "2. User Accounts and Eligibility")
                        SectionBody(text: """
                        • You must be at least 15 years old to use Communally.
                        • Users under 18 must have any required parent or guardian approval.
                        • You must provide accurate, current, and complete information.
                        • You are responsible for activity that occurs through your account.
                        • You must keep your sign-in credentials secure.
                        • We may suspend, limit, or terminate accounts at any time if we believe a user creates risk, violates these Terms, or misuses the platform.
                        """)
                    }
                    
                    // User Conduct
                    Section {
                        SectionTitle(title: "3. User Conduct and Prohibited Activities")
                        SectionBody(text: """
                        You may not:
                        • post false, misleading, dangerous, or unlawful opportunities
                        • impersonate any person or entity
                        • harass, threaten, exploit, stalk, or harm another user
                        • request or provide illegal services
                        • attempt to scam, defraud, or manipulate another user
                        • collect personal information from other users except as needed for a legitimate transaction
                        • move minors into unsafe situations, hidden locations, transportation-only situations, or any situation that violates applicable law
                        • interfere with the security, integrity, or normal operation of Communally
                        """)
                    }
                    
                    // Zero Tolerance Safety Policy
                    Section {
                        SectionTitle(title: "3A. Zero Tolerance: Assault & Violence")
                        // Red banner
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text("Communally has a strict zero-tolerance policy for sexual assault, physical assault, and any form of violence.")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.9)))

                        SectionBody(text: """
                        Any user who commits, attempts, or facilitates sexual assault, physical assault, rape, or any violent act against another user will be:

                        • Immediately suspended from Communally pending investigation
                        • Permanently banned upon confirmation of the incident
                        • Reported to law enforcement if required by applicable law
                        • Subject to civil and criminal liability

                        If you have been assaulted:
                        1. Call emergency services (999 in the UK, 911 in the US) immediately if you are in danger.
                        2. Use the SOS button or "Report Safety Incident" inside the app to flag the person immediately — their account will be suspended while we investigate.
                        3. Contact the Rape Crisis helpline (0808 802 9999), RAINN (1-800-656-4673), or Victim Support (0808 168 9111) for confidential support.

                        Communally will cooperate fully with law enforcement investigations and preserve all relevant records as required by law.
                        """)
                    }

                    // Job Postings
                    Section {
                        SectionTitle(title: "4. Job Postings and Opportunities")
                        SectionBody(text: """
                        • Communally does not employ job seekers, hire workers, supervise work, direct performance, provide transportation, inspect job sites, or guarantee any opportunity.
                        • Users are solely responsible for screening, selecting, contracting with, and paying each other.
                        • Users are solely responsible for complying with all laws relating to minors, labor, taxes, permits, wages, insurance, and safety.
                        • Job posters are responsible for accurate listings, lawful conduct, and safe working conditions.
                        • Job seekers are responsible for deciding whether an opportunity is appropriate and safe for them.
                        """)
                    }
                    
                    // Payments and Transactions
                    Section {
                        SectionTitle(title: "5. Payments and Transactions")
                        SectionBody(text: """
                        • Payment features may be offered through third-party providers such as Stripe.
                        • We may facilitate payment collection, holding, release, or refunds through those providers, but we are not a bank, money transmitter, escrow company, insurer, or fiduciary.
                        • All disputes concerning job quality, attendance, scope, or user conduct remain between the users except to the limited extent we choose to assist.
                        • Users are responsible for taxes, reporting, and compliance obligations related to payments.
                        """)
                    }
                    
                    // Safety and Security
                    Section {
                        SectionTitle(title: "6. Safety and Security")
                        SectionBody(text: """
                        • Communally may offer safety-related tools such as verification flows, reporting, trusted contact sharing, alerts, PIN check-ins, and other informational features.
                        • These features are provided for convenience only and may fail, be delayed, be incomplete, or be unavailable.
                        • Communally is not a law-enforcement agency, emergency service, transportation provider, background-check company, or on-site supervisor.
                        • Users must use independent judgment and take their own precautions before, during, and after any interaction arranged through the app.
                        """)
                    }
                    
                    // Content and Intellectual Property
                    Section {
                        SectionTitle(title: "7. Content and Intellectual Property")
                        SectionBody(text: """
                        • You retain ownership of content you submit, but you grant Communally a non-exclusive, worldwide, royalty-free license to host, store, reproduce, modify for formatting, display, and distribute that content to operate and improve the platform.
                        • You represent that you have the rights needed to submit your content.
                        • We may remove content at any time.
                        • The Communally app, brand, design, and software are owned by us or our licensors and may not be copied except as allowed by law.
                        """)
                    }
                    
                    // Liability and Disclaimers
                    Section {
                        SectionTitle(title: "8. Liability and Disclaimers")
                        SectionBody(text: """
                        • THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, TO THE MAXIMUM EXTENT PERMITTED BY LAW.
                        • We do not guarantee the identity, honesty, qualifications, intentions, conduct, solvency, safety, legality, or performance of any user or opportunity.
                        • We are not responsible for offline interactions, injury, death, kidnapping, assault, theft, fraud, property damage, lost profits, emotional distress, or any other harm arising out of or related to user interactions, opportunities, payments, or use of the app, to the maximum extent permitted by law.
                        • To the maximum extent permitted by law, Communally's total liability for any claim relating to the app will not exceed the greater of $100 or the amount you paid us, if any, in the 12 months before the event giving rise to the claim.
                        • You assume all risk arising from contact with other users and from participation in any opportunity found through the app.
                        • You agree to defend, indemnify, and hold harmless Communally and its officers, owners, employees, and contractors from claims, damages, losses, and expenses, including attorneys' fees, arising out of your content, conduct, transactions, law violations, or breach of these Terms.
                        """)
                    }
                    
                    // Dispute Resolution
                    Section {
                        SectionTitle(title: "9. Dispute Resolution")
                        SectionBody(text: """
                        • Users are responsible for resolving disputes directly with one another unless the law requires otherwise.
                        • We may, but are not required to, review or help address disputes.
                        • To the maximum extent permitted by law, disputes between you and Communally will be resolved by binding individual arbitration, and you waive any right to participate in a class action, except where such waiver is prohibited.
                        """)
                    }
                    
                    // Termination
                    Section {
                        SectionTitle(title: "10. Account Termination")
                        SectionBody(text: """
                        • You may stop using Communally at any time.
                        • We may suspend, restrict, or terminate access immediately for safety, legal, fraud, moderation, or business reasons.
                        • Certain sections of these Terms will survive termination, including payment obligations, dispute provisions, disclaimers, liability limits, and indemnity obligations.
                        """)
                    }
                    
                    // Changes to Terms
                    Section {
                        SectionTitle(title: "11. Changes to Terms")
                        SectionBody(text: """
                        • We may update these Terms from time to time.
                        • Updated Terms may be posted in the app or otherwise provided to users.
                        • Your continued use after an update becomes effective means you accept the updated Terms.
                        """)
                    }
                    
                    // Governing Law
                    Section {
                        SectionTitle(title: "12. Governing Law")
                        SectionBody(text: """
                        These Terms are governed by the laws of the state and country identified by Communally as its principal place of business, excluding conflict-of-law rules, except where applicable law requires otherwise.
                        """)
                    }
                    
                    // Contact Information
                    Section {
                        SectionTitle(title: "13. Contact Information")
                        SectionBody(text: """
                        Questions about these Terms may be sent to:

                        Email: communallyapp@gmail.com
                        Instagram: @communallyapp

                        By using Communally, you acknowledge that you have read and agree to these Terms of Service.
                        """)
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CommunallyTheme.secondaryGreen)
                }
            }
        }
    }
}

// MARK: - Helper Components
struct SectionTitle: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .bold, design: .default))
            .foregroundColor(.primary)
            .padding(.top, 4)
    }
}

struct SectionBody: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.primary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    TermsAndConditionsView()
}



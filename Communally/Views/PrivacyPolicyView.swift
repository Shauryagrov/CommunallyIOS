//
//  PrivacyPolicyView.swift
//  Communally
//
//  Created by Cursor on 11/30/25.
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy Policy")
                            .font(.system(size: 28, weight: .bold, design: .default))
                        
                        Text("Last Updated: April 29, 2026")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // Introduction
                    Section {
                        SectionTitle(title: "1. Introduction")
                        SectionBody(text: """
                        This Privacy Policy explains how Communally ("Communally," "we," "our," or "us") collects, uses, shares, and stores information when you use our app. By using Communally, you agree to the practices described in this Privacy Policy.
                        """)
                    }
                    
                    // Information We Collect
                    Section {
                        SectionTitle(title: "2. Information We Collect")
                        SectionBody(text: """
                        We may collect:
                        • account details such as your name, email address, date of birth or age, username, and profile photo
                        • profile details such as skills, descriptions, preferences, ratings, and account settings
                        • content you create, including job posts, applications, messages, reports, and support requests
                        • transaction details related to payment flows, payout status, refunds, and connected payment accounts
                        • location information if you grant permission or if you manually provide location-related information
                        • device, log, diagnostic, and usage information, such as app version, device type, and crash or performance data
                        • information received from third parties you use to sign in or receive payments, such as Google, Firebase, Apple, or Stripe
                        """)
                    }
                    
                    // How We Use Your Information
                    Section {
                        SectionTitle(title: "3. How We Use Your Information")
                        SectionBody(text: """
                        We may use your information to:
                        • create and manage accounts
                        • show job opportunities, profiles, and applications
                        • enable messaging, notifications, ratings, and safety-related features
                        • facilitate payment and payout flows through third-party providers
                        • detect, investigate, and help prevent fraud, abuse, unsafe behavior, or violations of our Terms
                        • personalize and improve the app
                        • provide customer support
                        • comply with legal obligations and enforce our rights
                        """)
                    }
                    
                    // Information Sharing
                    Section {
                        SectionTitle(title: "4. How We Share Your Information")
                        SectionBody(text: """
                        We may share information:
                        • with other users when needed for the platform to function, such as profile details, job posts, applications, ratings, and messages
                        • with service providers that help operate the app, such as hosting, database, authentication, analytics, communication, customer support, and payment providers
                        • with parents or guardians where our product flow or applicable law requires parental approval or involvement
                        • when required by law, legal process, or to protect the rights, safety, or property of users, Communally, or others — including sharing information with law enforcement when we believe a user has been the victim of assault, violence, or a serious crime
                        • as part of a merger, acquisition, financing, sale of assets, or similar business transaction
                        """)
                    }

                    // Safety & Law Enforcement
                    Section {
                        SectionTitle(title: "4A. Safety Reports & Law Enforcement Cooperation")
                        SectionBody(text: """
                        When a user submits a safety report alleging sexual assault, physical assault, or violence, Communally will:

                        • Immediately suspend the reported user's account pending investigation
                        • Preserve all relevant account data, messages, location records, and activity logs related to the incident
                        • Cooperate fully with law enforcement agencies, providing records when served with a valid legal process or when we reasonably believe disclosure is necessary to prevent imminent harm
                        • Not notify the accused user that a critical safety report has been filed against them or that their data is being preserved

                        The identity of the reporting user will be kept confidential to the fullest extent permitted by law. If you have experienced an assault, please also contact emergency services (999 in the UK, 911 in the US) and/or one of the following support organisations:
                        • Rape Crisis England & Wales: 0808 802 9999 (24/7, free)
                        • RAINN (US): 1-800-656-4673 (24/7)
                        • Victim Support (UK): 0808 168 9111 (24/7, free)
                        • National Domestic Abuse Helpline (UK): 0808 2000 247 (24/7, free)
                        """)
                    }
                    
                    // Data Security
                    Section {
                        SectionTitle(title: "5. Data Security")
                        SectionBody(text: """
                        We use reasonable administrative, technical, and organizational safeguards designed to protect information. However, no system is perfectly secure, and we cannot guarantee absolute security.
                        """)
                    }
                    
                    // Your Privacy Rights
                    Section {
                        SectionTitle(title: "6. Your Privacy Rights")
                        SectionBody(text: """
                        Depending on where you live, you may have rights to access, correct, delete, or request a copy of certain personal information. You may also manage some information directly in the app. To submit a privacy request, contact communallyapp@gmail.com.
                        """)
                    }
                    
                    // Location Data
                    Section {
                        SectionTitle(title: "7. Location Information")
                        SectionBody(text: """
                        • We may use location information to show nearby opportunities, improve relevance, support safety-related features, or help users describe where services will take place.
                        • Location-based features may rely on device permissions, approximate location, or address information supplied by users.
                        • You can limit location permissions in your device settings, but some features may not work correctly without them.
                        """)
                    }
                    
                    // Children's Privacy
                    Section {
                        SectionTitle(title: "8. Children's Privacy")
                        SectionBody(text: """
                        • Communally is not intended for children under 15.
                        • Where required by our product flow or applicable law, users under 18 must obtain parent or guardian approval.
                        • If we learn that an account was created in violation of age requirements, we may suspend or delete the account and associated data.
                        """)
                    }
                    
                    // Data Retention
                    Section {
                        SectionTitle(title: "9. Data Retention")
                        SectionBody(text: """
                        We retain information for as long as reasonably necessary for the purposes described in this Policy, including to operate the app, maintain records, investigate abuse, comply with legal obligations, resolve disputes, and enforce our agreements. Retention periods may vary depending on the type of information and applicable law.
                        """)
                    }
                    
                    // Third-Party Services
                    Section {
                        SectionTitle(title: "10. Third-Party Services")
                        SectionBody(text: """
                        Communally uses third-party services that may process data on our behalf or in connection with features you choose to use. These may include Google, Firebase, Apple, Stripe, hosting providers, analytics tools, and messaging or support vendors. Their handling of information is governed by their own terms and privacy notices.
                        """)
                    }
                    
                    // California Privacy Rights
                    Section {
                        SectionTitle(title: "11. California Privacy Rights (CCPA / CPRA)")
                        SectionBody(text: """
                        If you are a California resident, you have rights under the California Consumer Privacy Act (CCPA) and California Privacy Rights Act (CPRA), including the right to:
                        • Know what personal information we collect and how it is used
                        • Delete your personal information (subject to exceptions)
                        • Correct inaccurate personal information
                        • Opt-out of the sale or sharing of your personal information

                        We do not sell your personal information for money. To exercise your rights or submit a "Do Not Sell or Share My Personal Information" request, email communallyapp@gmail.com with subject line "California Privacy Request". You may also use the "Do Not Sell My Info" link in the app's profile screen. We will not discriminate against you for exercising these rights.
                        """)
                    }
                    
                    // GDPR Rights
                    Section {
                        SectionTitle(title: "12. European Privacy Rights (GDPR)")
                        SectionBody(text: """
                        If laws such as the GDPR apply to you, you may have additional privacy rights, including rights of access, correction, deletion, portability, objection, restriction, and complaint to a supervisory authority, subject to applicable conditions and exceptions.
                        """)
                    }
                    
                    // Cookies and Tracking
                    Section {
                        SectionTitle(title: "13. Cookies and Tracking")
                        SectionBody(text: """
                        Our app and service providers may use identifiers, logs, local storage, and similar technologies to support authentication, security, preferences, analytics, and app functionality.
                        """)
                    }
                    
                    // Changes to Privacy Policy
                    Section {
                        SectionTitle(title: "14. Changes to This Policy")
                        SectionBody(text: """
                        We may update this Privacy Policy from time to time. If we make changes, we may update the date above and provide additional notice where appropriate. Your continued use of Communally after the updated Policy takes effect means you accept the revised Policy.
                        """)
                    }
                    
                    // Contact Information
                    Section {
                        SectionTitle(title: "15. Contact Us")
                        SectionBody(text: """
                        For privacy questions or requests:

                        Email: communallyapp@gmail.com
                        Instagram: @communallyapp
                        """)
                    }
                    
                    // Consent
                    Section {
                        SectionBody(text: """
                        By using Communally, you acknowledge this Privacy Policy.
                        """)
                        .padding(.top, 8)
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

#Preview {
    PrivacyPolicyView()
}



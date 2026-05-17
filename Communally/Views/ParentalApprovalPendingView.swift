import SwiftUI

struct ParentalApprovalPendingView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.99, blue: 0.95), .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(CommunallyTheme.secondaryGreen)

                Text("Waiting for Parent Approval")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .multilineTextAlignment(.center)

                Text("Your account is almost ready. Ask your parent/guardian to approve your account from the email link.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Check Again") {
                    if let user = authManager.currentUser {
                        authManager.updateUser(user)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(CommunallyTheme.secondaryGreen)

                Button("Sign Out") {
                    authManager.signOut()
                }
                .font(.footnote.weight(.semibold))

                Spacer()
            }
            .padding(24)
        }
    }
}

#Preview {
    ParentalApprovalPendingView()
        .environmentObject(AuthenticationManager.shared)
}

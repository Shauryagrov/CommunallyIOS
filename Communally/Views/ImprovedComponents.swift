//
//  ImprovedComponents.swift
//  Communally
//
//  Professional UI components for smooth user experience
//

import SwiftUI

// MARK: - Professional Loading States

struct LoadingOverlay: View {
    let message: String
    
    init(message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white)
                
                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
        }
    }
}

struct SuccessOverlay: View {
    let message: String
    let action: () -> Void
    
    init(message: String = "Success!", action: @escaping () -> Void = {}) {
        self.message = message
        self.action = action
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    action()
                }
            
            VStack(spacing: 20) {
                AnimatedCheckmark(size: 70, color: CommunallyTheme.primaryGreen)
                
                Text(message)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
            )
            .scaleIn()
        }
    }
}

// MARK: - Professional Empty States

struct ProfessionalEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CommunallyTheme.primaryGreen.opacity(0.15),
                                CommunallyTheme.primaryGreen.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            .scaleIn()
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .multilineTextAlignment(.center)
                
                Text(message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 30)
            }
            .fadeIn(delay: 0.2)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text(actionTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .cardShadow(color: CommunallyTheme.primaryGreen, opacity: 0.3, radius: 12)
                }
                .smoothButton()
                .fadeIn(delay: 0.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Enhanced Buttons

struct EnhancedActionButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    let color: Color
    let action: () -> Void
    
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        color: Color = CommunallyTheme.primaryGreen,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.3))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .cardShadow()
            )
        }
        .smoothButton()
    }
}

// MARK: - Toast Notifications

struct ToastView: View {
    let icon: String
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success, error, info, warning
        
        var color: Color {
            switch self {
            case .success: return CommunallyTheme.primaryGreen
            case .error: return .red
            case .info: return .blue
            case .warning: return .orange
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .success: return CommunallyTheme.primaryGreen.opacity(0.1)
            case .error: return Color.red.opacity(0.1)
            case .info: return Color.blue.opacity(0.1)
            case .warning: return Color.orange.opacity(0.1)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(type.color)
            
            Text(message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(CommunallyTheme.darkGray)
            
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(type.color.opacity(0.3), lineWidth: 1)
                )
                .cardShadow(radius: 15)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Section Headers

struct SectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionTitle: String?
    
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.actionTitle = actionTitle
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                }
            }
            
            Spacer()
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
                .smoothButton()
            }
        }
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon: String
    let title: String
    let message: String
    let color: Color
    
    init(
        icon: String,
        title: String,
        message: String,
        color: Color = .blue
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray)
                
                Text(message)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Skeleton Loaders

struct SkeletonCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 150, height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 10)
                }
                
                Spacer()
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 60)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .cardShadow()
        )
        .shimmer(isLoading: true)
    }
}

// MARK: - Confirmation Dialog

struct ConfirmationDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmAction: () -> Void
    let cancelAction: () -> Void
    let isDestructive: Bool
    
    init(
        title: String,
        message: String,
        confirmTitle: String = "Confirm",
        isDestructive: Bool = false,
        confirmAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
        self.confirmAction = confirmAction
        self.cancelAction = cancelAction
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelAction()
                }
            
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 20)
                
                VStack(spacing: 12) {
                    Button(action: confirmAction) {
                        Text(confirmTitle)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .cardShadow(color: CommunallyTheme.primaryGreen, opacity: 0.3, radius: 12, y: 6)
                    }
                    .smoothButton()
                    
                    Button(action: cancelAction) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(CommunallyTheme.primaryGreen, lineWidth: 2)
                                    )
                            )
                            .cardShadow()
                    }
                    .smoothButton()
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
            )
            .padding(.horizontal, 40)
            .scaleIn()
        }
    }
}


//
//  SafetyCheckInView.swift
//  Communally
//
//  Safety check-in prompt for active job monitoring
//

import SwiftUI

struct SafetyCheckInView: View {
    @ObservedObject private var safetyService = SafetyMonitoringService.shared
    @Environment(\.dismiss) var dismiss
    
    let reason: String
    
    var body: some View {
        ZStack {
            // Urgent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Alert card
                VStack(spacing: 24) {
                    // Alert level indicator
                    ZStack {
                        Circle()
                            .fill(alertColor.opacity(0.2))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: alertIcon)
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(alertColor)
                    }
                    .padding(.top, 32)
                    
                    VStack(spacing: 12) {
                        Text("Safety Check-In")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Text(reason)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        // I'm Safe button
                        Button(action: {
                            safetyService.respondToCheckIn(status: .safe)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 20, weight: .bold))
                                Text("I'm Safe")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                        }
                        .interactiveButton()
                        
                        // Need More Time button
                        Button(action: {
                            safetyService.respondToCheckIn(status: .extending)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("I'm Safe, Need More Time")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(CommunallyTheme.primaryGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(CommunallyTheme.primaryGreen, lineWidth: 2)
                            )
                            .cornerRadius(14)
                        }
                        .interactiveButton()
                        
                        // Emergency button
                        Button(action: {
                            safetyService.respondToCheckIn(status: .needsHelp)
                            // Keep modal open to show emergency response
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("I Need Help!")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red)
                            .cornerRadius(14)
                        }
                        .interactiveButton()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .background(Color.white)
                .cornerRadius(28)
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .interactiveDismissDisabled() // Prevent dismissing without response
    }
    
    private var alertColor: Color {
        switch safetyService.alertLevel {
        case .normal:
            return CommunallyTheme.primaryGreen
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
    
    private var alertIcon: String {
        switch safetyService.alertLevel {
        case .normal:
            return "checkmark.shield.fill"
        case .warning:
            return "exclamationmark.shield.fill"
        case .critical:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Safety Status Indicator (Floating Badge)

struct SafetyStatusIndicator: View {
    /// Circular icon for the dashboard toolbar; full capsule when `false`.
    var compact: Bool = false

    @ObservedObject private var safetyService = SafetyMonitoringService.shared
    @State private var showCheckIn = false
    @State private var pulse = false
    
    var body: some View {
        Group {
            if safetyService.isMonitoring {
                Button(action: {
                    if safetyService.needsCheckIn {
                        showCheckIn = true
                    }
                }) {
                    Group {
                        if compact {
                            ZStack {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 44, height: 44)
                                Image(systemName: statusIcon)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            )
                            .scaleEffect(pulse ? 1.06 : 1.0)
                            .shadow(color: statusColor.opacity(0.45), radius: pulse ? 10 : 5, x: 0, y: 2)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: statusIcon)
                                    .font(.system(size: 14, weight: .bold))
                                
                                Text(statusText)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(statusColor)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .scaleEffect(pulse ? 1.1 : 1.0)
                            .shadow(color: statusColor.opacity(0.5), radius: pulse ? 15 : 8, x: 0, y: 4)
                        }
                    }
                }
                .onChange(of: safetyService.needsCheckIn) { _, needsCheckIn in
                    if needsCheckIn {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                        showCheckIn = true
                    } else {
                        pulse = false
                    }
                }
                .fullScreenCover(isPresented: $showCheckIn) {
                    SafetyCheckInView(reason: checkInReason)
                }
            }
        }
    }
    
    private var statusIcon: String {
        if safetyService.needsCheckIn {
            return "exclamationmark.circle.fill"
        }
        
        switch safetyService.alertLevel {
        case .normal:
            return "shield.checkered"
        case .warning:
            return "shield.fill"
        case .critical:
            return "exclamationmark.shield.fill"
        }
    }
    
    private var statusText: String {
        if safetyService.needsCheckIn {
            return "Check-In Required"
        }
        return "Protected"
    }
    
    private var statusColor: Color {
        if safetyService.needsCheckIn {
            return .red
        }
        
        switch safetyService.alertLevel {
        case .normal:
            return CommunallyTheme.primaryGreen
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
    
    private var checkInReason: String {
        switch safetyService.alertLevel {
        case .normal:
            return "Quick safety check-in. How's everything going?"
        case .warning:
            return "We detected something unusual. Are you safe?"
        case .critical:
            return "⚠️ URGENT: Please confirm you're safe!"
        }
    }
}

#Preview {
    SafetyCheckInView(reason: "Your job is running longer than expected. Are you safe?")
}

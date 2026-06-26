//
//  PINVerificationView.swift
//  Communally
//
//  PIN verification UI components
//

import SwiftUI
import CoreLocation

// MARK: - PIN Display View (For Hirer)

struct PINDisplayView: View {
    let jobId: String
    let type: PINVerificationType
    var hirerId: String = ""
    var workerId: String = ""
    @ObservedObject var pinService = PINVerificationService.shared
    @State private var timeRemaining: String = ""
    @State private var timer: Timer?
    
    var pin: JobPIN? {
        pinService.getActivePIN(jobId: jobId, type: type) ?? pinService.getPIN(jobId: jobId, type: type)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(CommunallyTheme.primaryGreen)

                Text(type.rawValue)
                    .font(.headline)
                    .foregroundColor(CommunallyTheme.darkGray)
                
                Spacer()
                
                if let pin = pin {
                    Text(timeRemaining)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            
            if let pin = pin {
                if pin.status == .verified {
                    // Verified State
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("PIN Verified!")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("Worker has confirmed their presence")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else if pin.status == .failed {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("PIN locked")
                            .font(.headline)
                        Text("Too many wrong attempts. Generate a new PIN and share it with your worker.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: regeneratePIN) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Generate New PIN")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(CommunallyTheme.primaryGreen)
                            .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    // Show PIN
                    VStack(spacing: 16) {
                        Text("Your PIN Code")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 14) {
                            ForEach(Array(pin.pin.enumerated()), id: \.offset) { index, digit in
                                Text(String(digit))
                                    .font(.system(size: 44, weight: .bold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                    .frame(width: 64, height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white)
                                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(CommunallyTheme.primaryGreen.opacity(0.35), lineWidth: 2)
                                    )
                            }
                        }
                        
                        Text("Share this PIN with the worker")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(CommunallyTheme.primaryGreen.opacity(0.06))
                    )
                }
                
                // Regenerate Button
                if pin.status == .pending && !pin.isExpired {
                    Button(action: regeneratePIN) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Generate New PIN")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }
            } else {
                // No PIN - let hirer generate one
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No active PIN")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if !hirerId.isEmpty && !workerId.isEmpty {
                        Button {
                            _ = pinService.generatePIN(
                                jobId: jobId,
                                type: type,
                                hirerId: hirerId,
                                workerId: workerId
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Generate PIN")
                            }
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(CommunallyTheme.primaryGreen)
                            .cornerRadius(12)
                        }
                    } else {
                        Text("PIN will appear after worker is accepted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 40)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.18), radius: 18, x: 0, y: 8)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
        .padding()
        .onAppear {
            startTimer()
            pinService.observePIN(jobId: jobId, type: type)
            pinService.fetchPIN(jobId: jobId, type: type) { _ in }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let pin = pin, !pin.isExpired {
                timeRemaining = pin.formattedRemainingTime
            } else {
                timeRemaining = "Expired"
            }
        }
    }
    
    private func regeneratePIN() {
        _ = pinService.regeneratePIN(jobId: jobId, type: type)
    }
}

// MARK: - PIN Entry View (For Worker)

struct PINEntryView: View {
    let jobId: String
    let type: PINVerificationType
    /// When set, the seeker must be within `geofenceRadiusMeters` of this
    /// coordinate to verify the PIN. Used for the "are you actually here?"
    /// check on job-start so people can't confirm from across town.
    var jobCoordinate: CLLocationCoordinate2D? = nil
    var geofenceRadiusMeters: CLLocationDistance = 200
    let onSuccess: () -> Void

    @ObservedObject var pinService = PINVerificationService.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var enteredPIN: String = ""
    @State private var isVerifying = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var isSuccess = false
    @Environment(\.dismiss) private var dismiss
    
    var canSubmit: Bool {
        return enteredPIN.count == 4 && !isVerifying
    }
    
    private var observedPIN: JobPIN? {
        pinService.getPIN(jobId: jobId, type: type)
    }
    
    private var isPINLockedOut: Bool {
        observedPIN?.status == .failed
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Force a clean white canvas regardless of device dark mode so
                // the PIN screen looks identical on every phone.
                Color.white.ignoresSafeArea()
            Group {
                if isPINLockedOut {
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 110, height: 110)
                            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                        }
                        Text("Too many attempts")
                            .font(.title2.bold())
                            .foregroundColor(CommunallyTheme.darkGray)
                        Text("Ask your hirer to open this job and tap Generate New PIN. When they share the new code, try again here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Close") {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 160)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LinearGradient(colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen], startPoint: .leading, endPoint: .trailing))
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(CommunallyTheme.primaryGreen.opacity(0.10))
                            .frame(width: 64, height: 64)
                        Image(systemName: type.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                    }

                    Text(type.rawValue)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(CommunallyTheme.darkGray)

                    Text("Enter the PIN from the hirer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // PIN Input Display
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
                                .frame(width: 54, height: 66)

                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    enteredPIN.count > index ? CommunallyTheme.primaryGreen : Color.gray.opacity(0.18),
                                    lineWidth: enteredPIN.count > index ? 2.5 : 1.5
                                )
                                .frame(width: 54, height: 66)

                            if enteredPIN.count > index {
                                Text(String(Array(enteredPIN)[index]))
                                    .font(.system(size: 28, weight: .bold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                            }
                        }
                    }
                }

                // Number Pad
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(1...3, id: \.self) { col in
                                let number = row * 3 + col
                                NumberButton(number: String(number)) {
                                    addDigit(String(number))
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Color.clear
                            .frame(width: 68, height: 68)

                        NumberButton(number: "0") {
                            addDigit("0")
                        }

                        Button(action: deleteDigit) {
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                .frame(width: 68, height: 68)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 3)
                                )
                        }
                    }
                }
                .padding(.bottom, 8)
            }
                }
            }
            }
            .navigationTitle("Enter PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(isSuccess ? "Success" : "Error", isPresented: $showResult) {
                Button("OK") {
                    if isSuccess {
                        onSuccess()
                        dismiss()
                    }
                }
            } message: {
                Text(resultMessage)
            }
            .onAppear {
                pinService.observePIN(jobId: jobId, type: type)
                pinService.fetchPIN(jobId: jobId, type: type) { _ in }
            }
        }
    }
    
    private func addDigit(_ digit: String) {
        guard enteredPIN.count < 4 else { return }
        enteredPIN += digit
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Auto-submit when 4 digits entered
        if enteredPIN.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                verifyPIN()
            }
        }
    }
    
    private func deleteDigit() {
        guard !enteredPIN.isEmpty else { return }
        enteredPIN.removeLast()
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func verifyPIN() {
        guard canSubmit else { return }

        // Geofence: if a job coordinate was provided, the seeker has to be
        // physically within geofenceRadiusMeters of it to verify. Stops
        // people from confirming a job from across town.
        if let target = jobCoordinate {
            guard let here = locationManager.location else {
                isSuccess = false
                resultMessage = "Turn on location to confirm. We need to verify you're at the job."
                showResult = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            let dest = CLLocation(latitude: target.latitude, longitude: target.longitude)
            let distance = here.distance(from: dest)
            if distance > geofenceRadiusMeters {
                isSuccess = false
                let blocks = max(1, Int((distance - geofenceRadiusMeters) / 80))
                resultMessage = "You're about \(blocks) block\(blocks == 1 ? "" : "s") away. Get to the job location, then enter the PIN."
                showResult = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
        }

        isVerifying = true

        pinService.verifyPIN(jobId: jobId, enteredPIN: enteredPIN, type: type) { success, message in
            DispatchQueue.main.async {
                isVerifying = false
                
                if !success, message.localizedCaseInsensitiveContains("too many") {
                    enteredPIN = ""
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    return
                }
                
                isSuccess = success
                resultMessage = message
                showResult = true
                
                if !success {
                    enteredPIN = ""
                    
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Number Button Component

struct NumberButton: View {
    let number: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.system(size: 24, weight: .semibold, design: .default))
                .foregroundColor(CommunallyTheme.darkGray)
                .frame(width: 68, height: 68)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 3)
                )
        }
    }
}

// MARK: - PIN Verification Button (Quick Access)

struct PINVerificationButton: View {
    let jobId: String
    let type: PINVerificationType
    let isHirer: Bool
    var hirerId: String = ""
    var workerId: String = ""
    var jobCoordinate: CLLocationCoordinate2D? = nil
    var geofenceRadiusMeters: CLLocationDistance = 200
    @State private var showPINEntry = false
    @State private var showPINDisplay = false
    
    var body: some View {
        Button(action: {
            if isHirer {
                showPINDisplay = true
            } else {
                showPINEntry = true
            }
        }) {
            HStack {
                Image(systemName: isHirer ? "eye.fill" : "key.fill")
                Text(isHirer ? "Show PIN" : "Enter PIN")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [type.color, type.color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .sheet(isPresented: $showPINDisplay) {
            NavigationView {
                ZStack {
                    Color.white.ignoresSafeArea()
                    ScrollView {
                        PINDisplayView(jobId: jobId, type: type, hirerId: hirerId, workerId: workerId)
                    }
                }
                .navigationTitle("Your PIN")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showPINDisplay = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPINEntry) {
            PINEntryView(
                jobId: jobId,
                type: type,
                jobCoordinate: jobCoordinate,
                geofenceRadiusMeters: geofenceRadiusMeters
            ) {
                print("✅ PIN verified successfully")
            }
        }
    }
}

// MARK: - PIN Status Indicator

struct PINStatusIndicator: View {
    let jobId: String
    let type: PINVerificationType
    @ObservedObject var pinService = PINVerificationService.shared
    
    var pin: JobPIN? {
        pinService.getPIN(jobId: jobId, type: type)
    }
    
    var body: some View {
        if let pin = pin {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                
                Text(pin.status.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusColor.opacity(0.1))
            )
        }
    }
    
    private var statusIcon: String {
        switch pin?.status {
        case .pending:
            return "clock.fill"
        case .verified:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .expired:
            return "exclamationmark.triangle.fill"
        case .none:
            return "questionmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch pin?.status {
        case .pending:
            return .orange
        case .verified:
            return .green
        case .failed:
            return .red
        case .expired:
            return .gray
        case .none:
            return .secondary
        }
    }
}

// MARK: - PIN Verification Card

struct PINVerificationCard: View {
    let jobId: String
    let type: PINVerificationType
    let isHirer: Bool
    var hirerId: String = ""
    var workerId: String = ""
    /// Optional geofence target — when set, the seeker has to be within
    /// `geofenceRadiusMeters` of this coordinate to verify the PIN.
    var jobCoordinate: CLLocationCoordinate2D? = nil
    var geofenceRadiusMeters: CLLocationDistance = 200
    @ObservedObject var pinService = PINVerificationService.shared
    
    var isVerified: Bool {
        pinService.isVerified(jobId: jobId, type: type)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundColor(type.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.rawValue)
                        .font(.headline)
                    
                    Text(isHirer ? "Show PIN to worker" : "Enter PIN from hirer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                PINStatusIndicator(jobId: jobId, type: type)
            }
            
            // Action
            if !isVerified {
                PINVerificationButton(
                    jobId: jobId,
                    type: type,
                    isHirer: isHirer,
                    hirerId: hirerId,
                    workerId: workerId,
                    jobCoordinate: jobCoordinate,
                    geofenceRadiusMeters: geofenceRadiusMeters
                )
            } else {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    Text("Verified")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        )
        .padding(.horizontal)
        .onAppear {
            pinService.observePIN(jobId: jobId, type: type)
            pinService.fetchPIN(jobId: jobId, type: type) { _ in }
        }
    }
}

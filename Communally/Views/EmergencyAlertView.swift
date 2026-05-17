//
//  EmergencyAlertView.swift
//  Communally
//
//  Emergency alert UI components
//

import SwiftUI
import MapKit

// MARK: - Emergency Alert Banner

struct EmergencyAlertBanner: View {
    let alert: EmergencyAlert
    let onDismiss: () -> Void
    let onViewDetails: () -> Void
    
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Alert Icon
                Text(alert.type.icon)
                    .font(.system(size: 32))
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)
                
                // Alert Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.type.rawValue.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text(alert.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(alert.actionableAdvice)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Dismiss Button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [alert.severity.color, alert.severity.color.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // View Details Button
            Button(action: onViewDetails) {
                Text("View Details & Route Around")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.2))
            }
        }
        .cornerRadius(16)
        .shadow(color: alert.severity.color.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal)
        .onAppear {
            isPulsing = alert.severity == .critical
        }
    }
}

// MARK: - Emergency Alert Detail View

struct EmergencyAlertDetailView: View {
    let alert: EmergencyAlert
    @State private var region: MKCoordinateRegion
    @Environment(\.dismiss) private var dismiss
    
    init(alert: EmergencyAlert) {
        self.alert = alert
        _region = State(initialValue: MKCoordinateRegion(
            center: alert.location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Alert Header
                    VStack(spacing: 12) {
                        Text(alert.type.icon)
                            .font(.system(size: 60))
                        
                        Text(alert.type.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Text(alert.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        // Severity Badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(alert.severity.color)
                                .frame(width: 8, height: 8)
                            
                            Text(alert.severity.rawValue + " Priority")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(alert.severity.color.opacity(0.15))
                        .cornerRadius(20)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [alert.severity.color.opacity(0.1), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Alert Details
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(icon: "info.circle.fill", title: "Description", value: alert.description)
                        
                        DetailRow(icon: "location.fill", title: "Location", value: alert.location.address ?? "Unknown")
                        
                        DetailRow(icon: "building.2.fill", title: "Source", value: alert.source)
                        
                        DetailRow(icon: "clock.fill", title: "Reported", value: formatDate(alert.timestamp))
                        
                        if let expiresAt = alert.expiresAt {
                            DetailRow(icon: "timer", title: "Expires", value: formatDate(expiresAt))
                        }
                        
                        // Actionable Advice
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Safety Advice")
                                    .font(.headline)
                            }
                            
                            Text(alert.actionableAdvice)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    
                    // Map Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Alert Location")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Map(coordinateRegion: $region, annotationItems: [alert]) { alert in
                            MapAnnotation(coordinate: alert.location.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(alert.severity.color.opacity(0.3))
                                        .frame(width: 100, height: 100)
                                    
                                    Circle()
                                        .fill(alert.severity.color)
                                        .frame(width: 40, height: 40)
                                    
                                    Text(alert.type.icon)
                                        .font(.title3)
                                }
                            }
                        }
                        .frame(height: 250)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: openInMaps) {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("View in Maps")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        
                        Button(action: shareAlert) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Alert")
                            }
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Emergency Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func openInMaps() {
        let coordinate = alert.location.coordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = alert.title
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
    
    private func shareAlert() {
        let message = """
        🚨 Emergency Alert: \(alert.type.rawValue)
        
        \(alert.title)
        \(alert.description)
        
        Location: \(alert.location.address ?? "Unknown")
        Time: \(formatDate(alert.timestamp))
        
        ⚠️ \(alert.actionableAdvice)
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Detail Row Component

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Emergency Alerts List View

struct EmergencyAlertsListView: View {
    @ObservedObject var alertService = EmergencyAlertService.shared
    @State private var selectedAlert: EmergencyAlert?
    @State private var showSettings = false
    
    var body: some View {
        NavigationView {
            List {
                if alertService.nearbyAlerts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("All Clear")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("No emergency alerts in your area")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(alertService.nearbyAlerts.sorted(by: { $0.severity.rawValue > $1.severity.rawValue })) { alert in
                        Button(action: {
                            selectedAlert = alert
                        }) {
                            AlertRowView(alert: alert)
                        }
                        .listRowBackground(alert.severity.color.opacity(0.05))
                    }
                }
            }
            .navigationTitle("Emergency Alerts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(item: $selectedAlert) { alert in
                EmergencyAlertDetailView(alert: alert)
            }
            .sheet(isPresented: $showSettings) {
                EmergencyAlertSettingsView()
            }
        }
    }
}

// MARK: - Alert Row View

struct AlertRowView: View {
    let alert: EmergencyAlert
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(alert.severity.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Text(alert.type.icon)
                    .font(.title2)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.type.rawValue)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(alert.severity.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(alert.severity.color)
                        .cornerRadius(8)
                }
                
                Text(alert.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(formatTime(alert.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Emergency Alert Settings View

struct EmergencyAlertSettingsView: View {
    @ObservedObject var alertService = EmergencyAlertService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Enable Emergency Alerts", isOn: $alertService.enableEmergencyAlerts)
                        .onChange(of: alertService.enableEmergencyAlerts) { _, enabled in
                            if enabled {
                                alertService.startMonitoring()
                            } else {
                                alertService.stopMonitoring()
                            }
                        }
                } header: {
                    Text("Monitoring")
                } footer: {
                    Text("Receive real-time alerts about emergencies near you")
                }
                
                Section {
                    ForEach(EmergencyType.allCases, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { alertService.alertTypes.contains(type) },
                            set: { alertService.toggleAlertType(type, enabled: $0) }
                        )) {
                            HStack {
                                Text(type.icon)
                                Text(type.rawValue)
                            }
                        }
                    }
                } header: {
                    Text("Alert Types")
                } footer: {
                    Text("Choose which types of emergencies you want to be notified about")
                }
                
                Section {
                    Picker("Minimum Severity", selection: $alertService.minimumSeverity) {
                        ForEach([AlertSeverity.low, .medium, .high, .critical], id: \.self) { severity in
                            Text(severity.rawValue).tag(severity)
                        }
                    }
                } header: {
                    Text("Alert Threshold")
                } footer: {
                    Text("Only show alerts at or above this severity level")
                }
                
                Section {
                    InfoRow(icon: "📍", title: "Range", description: "5km radius")
                    InfoRow(icon: "⏱", title: "Check Frequency", description: "Every 5 minutes")
                    InfoRow(icon: "🔔", title: "Notification", description: "Critical alerts")
                } header: {
                    Text("How It Works")
                }
            }
            .navigationTitle("Emergency Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Floating Alert Indicator

struct EmergencyAlertIndicator: View {
    /// Icon-only circle for the dashboard toolbar; full pill when `false`.
    var compact: Bool = false

    @ObservedObject var alertService = EmergencyAlertService.shared
    @State private var showAlertsList = false
    @State private var isPulsing = false
    
    var body: some View {
        if alertService.hasActiveAlerts {
            Button(action: { showAlertsList = true }) {
                Group {
                    if compact {
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.35))
                                    .frame(width: 44, height: 44)
                                    .scaleEffect(isPulsing ? 1.15 : 1.0)
                                    .opacity(isPulsing ? 0.45 : 0.75)

                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 44, height: 44)

                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 17, weight: .semibold))
                            }

                            if alertService.criticalAlertCount > 0 {
                                Text("\(min(alertService.criticalAlertCount, 9))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Circle().fill(Color.orange))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .shadow(color: .red.opacity(0.35), radius: 6, x: 0, y: 2)
                    } else {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 36, height: 36)
                                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                                    .opacity(isPulsing ? 0.3 : 0.6)
                                
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                            
                            if alertService.criticalAlertCount > 0 {
                                Text("\(alertService.criticalAlertCount)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(8)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(22)
                        .shadow(color: .red.opacity(0.3), radius: 10)
                    }
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .sheet(isPresented: $showAlertsList) {
                EmergencyAlertsListView()
            }
        }
    }
}

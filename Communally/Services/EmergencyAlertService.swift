//
//  EmergencyAlertService.swift
//  Communally
//
//  Real-time emergency alerts for active crime, fires, and hazards
//

import Foundation
import CoreLocation
import UserNotifications
import SwiftUI

// MARK: - Emergency Alert Types

enum EmergencyType: String, Codable, CaseIterable {
    case activeCrime = "Active Crime"
    case fire = "Fire"
    case flood = "Flood"
    case extremeWeather = "Severe Weather"
    case hazmat = "Hazardous Materials"
    case civilUnrest = "Civil Unrest"
    case roadClosure = "Road Closure"
    case other = "Emergency"
    
    var icon: String {
        switch self {
        case .activeCrime: return "🚨"
        case .fire: return "🔥"
        case .flood: return "🌊"
        case .extremeWeather: return "⛈️"
        case .hazmat: return "☢️"
        case .civilUnrest: return "⚠️"
        case .roadClosure: return "🚧"
        case .other: return "🆘"
        }
    }
    
    var color: Color {
        switch self {
        case .activeCrime, .fire, .hazmat: return .red
        case .flood, .extremeWeather, .civilUnrest: return .orange
        case .roadClosure, .other: return .yellow
        }
    }
    
    var urgency: Int {
        switch self {
        case .activeCrime, .fire: return 3 // Critical
        case .hazmat, .civilUnrest: return 2 // High
        case .flood, .extremeWeather, .roadClosure: return 1 // Medium
        case .other: return 0 // Low
        }
    }
}

enum AlertSeverity: String, Codable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
}

// MARK: - Emergency Alert Model

struct EmergencyAlert: Identifiable, Codable {
    let id: String
    let type: EmergencyType
    let severity: AlertSeverity
    let title: String
    let description: String
    let location: AlertLocation
    let radius: Double // in meters
    let timestamp: Date
    let expiresAt: Date?
    let source: String
    let actionableAdvice: String
    
    struct AlertLocation: Codable {
        let latitude: Double
        let longitude: Double
        let address: String?
        
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    func distance(from userLocation: CLLocation) -> Double {
        let alertLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        return userLocation.distance(from: alertLocation)
    }
    
    var isActive: Bool {
        guard let expiresAt = expiresAt else { return true }
        return Date() < expiresAt
    }
}

// MARK: - Emergency Alert Service

class EmergencyAlertService: ObservableObject {
    static let shared = EmergencyAlertService()
    
    @Published var activeAlerts: [EmergencyAlert] = []
    @Published var nearbyAlerts: [EmergencyAlert] = []
    @Published var showAlertBanner: Bool = false
    @Published var currentBannerAlert: EmergencyAlert?
    
    private var locationManager = LocationManager.shared
    private var monitoringTimer: Timer?
    private var isMonitoring = false
    
    // Configuration
    private let alertCheckInterval: TimeInterval = 300 // 5 minutes
    private let proximityRadius: Double = 5000 // 5km - check for alerts within this radius
    private let dangerZoneRadius: Double = 1000 // 1km - alert if within this distance
    
    // User preferences
    @Published var enableEmergencyAlerts = true
    @Published var alertTypes: Set<EmergencyType> = Set(EmergencyType.allCases)
    @Published var minimumSeverity: AlertSeverity = .low
    
    private init() {
        loadSettings()
        startMonitoring()
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        guard enableEmergencyAlerts else { return }
        
        isMonitoring = true
        print("🚨 Starting emergency alert monitoring")
        
        // Initial check
        checkForEmergencies()
        
        // Set up periodic checks
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: alertCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForEmergencies()
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("🚨 Stopped emergency alert monitoring")
    }
    
    private func checkForEmergencies() {
        guard let userLocation = locationManager.location else {
            print("⚠️ Cannot check emergencies - no location available")
            return
        }
        
        print("🔍 Checking for emergencies near: \(userLocation.coordinate.latitude), \(userLocation.coordinate.longitude)")
        
        // Fetch alerts from multiple sources
        Task {
            await fetchEmergencyAlerts(near: userLocation)
        }
    }
    
    // MARK: - Fetch Alerts
    
    private func fetchEmergencyAlerts(near location: CLLocation) async {
        // In production, this would call real APIs:
        // - FEMA alerts
        // - Local police scanners
        // - Fire department APIs
        // - Weather alerts
        // - Traffic APIs
        // - Crime mapping services
        
        // For now, we'll use simulated data + real-time weather API
        var newAlerts: [EmergencyAlert] = []
        
        // Fetch from multiple sources
        async let weatherAlerts = fetchWeatherAlerts(near: location)
        async let crimeAlerts = fetchCrimeAlerts(near: location)
        async let trafficAlerts = fetchTrafficAlerts(near: location)
        
        // Combine all alerts
        let (weather, crime, traffic) = await (weatherAlerts, crimeAlerts, trafficAlerts)
        newAlerts.append(contentsOf: weather)
        newAlerts.append(contentsOf: crime)
        newAlerts.append(contentsOf: traffic)
        
        // Update on main thread
        await MainActor.run {
            processNewAlerts(newAlerts, userLocation: location)
        }
    }
    
    // MARK: - API Integrations (Simulated)
    
    private func fetchWeatherAlerts(near location: CLLocation) async -> [EmergencyAlert] {
        // In production: Use National Weather Service API, Weather.gov, etc.
        // Example: https://api.weather.gov/alerts/active?point=lat,lon
        
        var alerts: [EmergencyAlert] = []
        
        // Simulate weather check
        // In production, make actual API call
        
        return alerts
    }
    
    private func fetchCrimeAlerts(near location: CLLocation) async -> [EmergencyAlert] {
        // In production: Use:
        // - SpotCrime API
        // - CrimeMapping.com
        // - Local police department APIs
        // - Citizen app data
        
        var alerts: [EmergencyAlert] = []
        
        // Simulate crime data check
        // In production, make actual API calls
        
        return alerts
    }
    
    private func fetchTrafficAlerts(near location: CLLocation) async -> [EmergencyAlert] {
        // In production: Use:
        // - Google Maps Traffic API
        // - Waze API
        // - Local DOT APIs
        
        var alerts: [EmergencyAlert] = []
        
        // Simulate traffic check
        // In production, make actual API calls
        
        return alerts
    }
    
    // MARK: - Process Alerts
    
    private func processNewAlerts(_ newAlerts: [EmergencyAlert], userLocation: CLLocation) {
        // Filter by user preferences
        let filteredAlerts = newAlerts.filter { alert in
            // Check if alert type is enabled
            guard alertTypes.contains(alert.type) else { return false }
            
            // Check if severity meets minimum
            guard alert.severity.rawValue >= minimumSeverity.rawValue else { return false }
            
            // Check if alert is still active
            guard alert.isActive else { return false }
            
            return true
        }
        
        // Update active alerts
        activeAlerts = filteredAlerts
        
        // Find nearby dangerous alerts
        nearbyAlerts = filteredAlerts.filter { alert in
            let distance = alert.distance(from: userLocation)
            return distance <= dangerZoneRadius
        }
        
        // Check for critical nearby alerts
        checkForDangerZone(userLocation: userLocation)
    }
    
    private func checkForDangerZone(userLocation: CLLocation) {
        // Find critical alerts very close to user
        let criticalNearby = nearbyAlerts.filter { alert in
            let distance = alert.distance(from: userLocation)
            return distance <= alert.radius && alert.severity == .critical
        }
        
        // Alert user if in danger zone
        for alert in criticalNearby {
            notifyUserOfDanger(alert: alert, distance: alert.distance(from: userLocation))
        }
    }
    
    // MARK: - Notifications
    
    private func notifyUserOfDanger(alert: EmergencyAlert, distance: Double) {
        print("⚠️ DANGER ZONE: \(alert.type.rawValue) within \(Int(distance))m")
        
        // Show banner
        currentBannerAlert = alert
        showAlertBanner = true
        
        // Send push notification
        sendEmergencyNotification(alert: alert, distance: distance)
        
        // Log for analytics
        logEmergencyAlert(alert: alert)
    }
    
    private func sendEmergencyNotification(alert: EmergencyAlert, distance: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.type.icon) EMERGENCY ALERT"
        content.body = "\(alert.title) - \(Int(distance))m away. \(alert.actionableAdvice)"
        content.sound = .defaultCritical
        content.categoryIdentifier = "EMERGENCY_ALERT"
        
        // Set priority to critical
        content.interruptionLevel = .critical
        
        let request = UNNotificationRequest(
            identifier: "emergency_\(alert.id)",
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending emergency notification: \(error)")
            } else {
                print("✅ Emergency notification sent")
            }
        }
    }
    
    // MARK: - Alert Actions
    
    func dismissBanner() {
        showAlertBanner = false
        currentBannerAlert = nil
    }
    
    func getAlternativeRoute(avoiding alert: EmergencyAlert) -> String {
        // In production: Calculate safe route using Maps API
        return "Take alternative route avoiding \(alert.location.address ?? "danger zone")"
    }
    
    func markAlertAcknowledged(_ alertId: String) {
        // Store acknowledged alerts
        UserDefaults.standard.set(true, forKey: "alert_ack_\(alertId)")
    }
    
    func isAlertAcknowledged(_ alertId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "alert_ack_\(alertId)")
    }
    
    // MARK: - Settings
    
    func toggleAlertType(_ type: EmergencyType, enabled: Bool) {
        if enabled {
            alertTypes.insert(type)
        } else {
            alertTypes.remove(type)
        }
        saveSettings()
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(enableEmergencyAlerts, forKey: "emergency_alerts_enabled")
        
        let typesArray = alertTypes.map { $0.rawValue }
        UserDefaults.standard.set(typesArray, forKey: "emergency_alert_types")
        
        UserDefaults.standard.set(minimumSeverity.rawValue, forKey: "emergency_min_severity")
    }
    
    private func loadSettings() {
        enableEmergencyAlerts = UserDefaults.standard.object(forKey: "emergency_alerts_enabled") as? Bool ?? true
        
        if let typesArray = UserDefaults.standard.array(forKey: "emergency_alert_types") as? [String] {
            alertTypes = Set(typesArray.compactMap { EmergencyType(rawValue: $0) })
        } else {
            alertTypes = Set(EmergencyType.allCases)
        }
        
        if let severityRaw = UserDefaults.standard.string(forKey: "emergency_min_severity"),
           let severity = AlertSeverity(rawValue: severityRaw) {
            minimumSeverity = severity
        }
    }
    
    private func logEmergencyAlert(alert: EmergencyAlert) {
        // In production: Send to analytics
        print("📊 Emergency alert logged: \(alert.type.rawValue) - \(alert.severity.rawValue)")
    }
    
    // MARK: - Test Data
    
    func addTestAlert(near location: CLLocation) {
        let testAlert = EmergencyAlert(
            id: UUID().uuidString,
            type: .activeCrime,
            severity: .critical,
            title: "Armed Robbery in Progress",
            description: "Police responding to armed robbery. Avoid area.",
            location: EmergencyAlert.AlertLocation(
                latitude: location.coordinate.latitude + 0.005,
                longitude: location.coordinate.longitude + 0.005,
                address: "123 Main St"
            ),
            radius: 500,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(3600),
            source: "Local Police",
            actionableAdvice: "Avoid this area. Take alternative route."
        )
        
        activeAlerts.append(testAlert)
        nearbyAlerts.append(testAlert)
        notifyUserOfDanger(alert: testAlert, distance: 500)
    }
}

// MARK: - Helper Extensions

extension EmergencyAlertService {
    func getAlertsInArea(center: CLLocationCoordinate2D, radius: Double) -> [EmergencyAlert] {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        
        return activeAlerts.filter { alert in
            let distance = alert.distance(from: centerLocation)
            return distance <= radius
        }
    }
    
    func getCriticalAlerts() -> [EmergencyAlert] {
        return nearbyAlerts.filter { $0.severity == .critical }
    }
    
    var hasActiveAlerts: Bool {
        return !nearbyAlerts.isEmpty
    }
    
    var criticalAlertCount: Int {
        return getCriticalAlerts().count
    }
}

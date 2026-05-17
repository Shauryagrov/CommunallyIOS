//
//  SafetyMonitoringService.swift
//  Communally
//
//  Advanced safety monitoring using GPS, sensors, and timers
//

import Foundation
import CoreLocation
import CoreMotion
import UserNotifications

class SafetyMonitoringService: NSObject, ObservableObject {
    static let shared = SafetyMonitoringService()
    
    // MARK: - Published Properties
    @Published var isMonitoring = false
    @Published var needsCheckIn = false
    @Published var alertLevel: SafetyAlertLevel = .normal
    
    // MARK: - Private Properties
    private var activeJobId: String?
    private var jobStartTime: Date?
    private var expectedDuration: TimeInterval = 3600 // 1 hour default
    private var lastKnownLocation: CLLocation?
    private var lastMovementTime: Date?
    private var checkInTimer: Timer?
    private var monitoringTimer: Timer?
    
    // Motion detection
    private let motionManager = CMMotionManager()
    private var motionQueue = OperationQueue()
    
    // Safety thresholds
    private let stationaryThreshold: TimeInterval = 1800 // 30 minutes without movement
    private let overtimeThreshold: TimeInterval = 600 // 10 minutes over expected time
    private let fallDetectionThreshold: Double = 2.5 // G-force threshold
    
    private override init() {
        super.init()
        motionQueue.maxConcurrentOperationCount = 1
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for a specific job
    func startMonitoring(
        jobId: String,
        expectedDuration: TimeInterval,
        emergencyContact: String? = nil
    ) {
        print("🛡️ Starting safety monitoring for job: \(jobId)")
        
        self.activeJobId = jobId
        self.jobStartTime = Date()
        self.expectedDuration = expectedDuration
        self.lastMovementTime = Date()
        self.isMonitoring = true
        self.alertLevel = .normal
        
        // Start monitoring systems
        startLocationMonitoring()
        startMotionDetection()
        startTimerMonitoring()
        
        // Schedule first check-in
        scheduleCheckIn(after: expectedDuration / 2) // Check in halfway through
    }
    
    /// Stop monitoring (job completed safely)
    func stopMonitoring(reason: String = "Job completed") {
        print("🛡️ Stopping safety monitoring: \(reason)")
        
        isMonitoring = false
        needsCheckIn = false
        alertLevel = .normal
        
        checkInTimer?.invalidate()
        monitoringTimer?.invalidate()
        
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        
        activeJobId = nil
        jobStartTime = nil
    }
    
    /// User responded to check-in
    func respondToCheckIn(status: CheckInStatus) {
        print("✅ User check-in: \(status)")
        
        needsCheckIn = false
        
        switch status {
        case .safe:
            alertLevel = .normal
            // Reschedule next check-in
            scheduleCheckIn(after: 1800) // Check again in 30 minutes
            
        case .needsHelp:
            alertLevel = .critical
            triggerEmergencyAlert()
            
        case .extending:
            // User is safe but needs more time
            alertLevel = .normal
            // Extend monitoring
            if let startTime = jobStartTime {
                expectedDuration = Date().timeIntervalSince(startTime) + 3600 // Add 1 hour
            }
            scheduleCheckIn(after: 1800)
        }
    }
    
    // MARK: - Private Methods
    
    private func startLocationMonitoring() {
        // Monitor location changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(locationDidUpdate(_:)),
            name: NSNotification.Name("LocationDidUpdate"),
            object: nil
        )
        
        lastKnownLocation = LocationManager.shared.location
    }
    
    private func startMotionDetection() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.1 // 10 times per second
        
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            // Detect sudden impacts/falls
            let totalAcceleration = sqrt(
                pow(motion.userAcceleration.x, 2) +
                pow(motion.userAcceleration.y, 2) +
                pow(motion.userAcceleration.z, 2)
            )
            
            if totalAcceleration > self.fallDetectionThreshold {
                DispatchQueue.main.async {
                    self.detectPotentialIncident(type: .fall)
                }
            }
            
            // Detect movement (not stationary)
            if totalAcceleration > 0.1 {
                DispatchQueue.main.async {
                    self.lastMovementTime = Date()
                }
            }
        }
    }
    
    private func startTimerMonitoring() {
        // Check safety status every 5 minutes
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkSafetyStatus()
        }
    }
    
    private func checkSafetyStatus() {
        guard isMonitoring, let startTime = jobStartTime else { return }
        
        let currentDuration = Date().timeIntervalSince(startTime)
        
        // Check if job is running overtime
        if currentDuration > expectedDuration + overtimeThreshold {
            detectPotentialIncident(type: .overtime)
        }
        
        // Check if user hasn't moved in a while
        if let lastMovement = lastMovementTime {
            let stationaryTime = Date().timeIntervalSince(lastMovement)
            if stationaryTime > stationaryThreshold {
                detectPotentialIncident(type: .stationary)
            }
        }
        
        // Check if location seems unusual
        checkLocationAnomaly()
        
        // Check for emergency alerts in the area
        checkForEmergencyAlertsNearby()
    }
    
    private func checkForEmergencyAlertsNearby() {
        guard let currentLocation = LocationManager.shared.location else { return }
        
        // Check if user is near any critical emergency alerts
        let criticalAlerts = EmergencyAlertService.shared.getCriticalAlerts()
        
        for alert in criticalAlerts {
            let distance = alert.distance(from: currentLocation)
            
            // If within danger zone, prompt check-in
            if distance <= alert.radius {
                print("⚠️ User is near emergency: \(alert.type.rawValue)")
                detectPotentialIncident(type: .unusualMovement)
            }
        }
    }
    
    private func checkLocationAnomaly() {
        guard let currentLocation = LocationManager.shared.location,
              let lastLocation = lastKnownLocation else { return }
        
        let distance = currentLocation.distance(from: lastLocation)
        let timeDiff = currentLocation.timestamp.timeIntervalSince(lastLocation.timestamp)
        
        // If user moved very far very fast (kidnapping detection)
        if distance > 5000 && timeDiff < 300 { // 5km in 5 minutes
            detectPotentialIncident(type: .unusualMovement)
        }
        
        lastKnownLocation = currentLocation
    }
    
    private func detectPotentialIncident(type: IncidentType) {
        print("⚠️ Potential incident detected: \(type)")
        
        switch type {
        case .fall:
            alertLevel = .warning
            promptCheckIn(reason: "We detected a possible fall. Are you okay?")
            
        case .overtime:
            alertLevel = .warning
            promptCheckIn(reason: "Your job is running longer than expected. Are you safe?")
            
        case .stationary:
            alertLevel = .warning
            promptCheckIn(reason: "We haven't detected movement in a while. Are you okay?")
            
        case .unusualMovement:
            alertLevel = .critical
            promptCheckIn(reason: "We detected unusual location changes. Are you safe?")
        }
    }
    
    private func promptCheckIn(reason: String) {
        needsCheckIn = true
        
        // Send local notification
        sendCheckInNotification(message: reason)
        
        // Start countdown - if no response in 5 minutes, escalate
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self = self else { return }
            
            if self.needsCheckIn { // User hasn't responded
                self.escalateAlert()
            }
        }
    }
    
    private func scheduleCheckIn(after interval: TimeInterval) {
        checkInTimer?.invalidate()
        
        checkInTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.promptCheckIn(reason: "Quick safety check-in. How's everything going?")
        }
    }
    
    private func escalateAlert() {
        print("🚨 ESCALATING ALERT - No response to check-in")
        
        alertLevel = .critical
        
        // Send urgent notification
        sendUrgentNotification()
        
        // Could trigger emergency contacts here
        // shareLocationWithEmergencyContacts()
    }
    
    private func triggerEmergencyAlert() {
        print("🚨 EMERGENCY ALERT TRIGGERED")
        
        alertLevel = .critical
        
        // Send emergency notification
        sendEmergencyNotification()
        
        // Share location with emergency contacts
        shareLocationWithEmergencyContacts()
        
        // Could call emergency services API here
        // notifyEmergencyServices()
    }
    
    @objc private func locationDidUpdate(_ notification: Notification) {
        // Update last known location when location changes
        lastKnownLocation = LocationManager.shared.location
    }
    
    // MARK: - Notifications
    
    private func sendCheckInNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Safety Check-In Required"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "SAFETY_CHECKIN"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendUrgentNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ URGENT: Safety Check Required"
        content.body = "You haven't responded to our safety check. Tap here if you're safe."
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "URGENT_CHECKIN"
        
        let request = UNNotificationRequest(
            identifier: "urgent_checkin",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendEmergencyNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🚨 EMERGENCY ALERT"
        content.body = "Emergency contacts have been notified of your location."
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "EMERGENCY"
        
        let request = UNNotificationRequest(
            identifier: "emergency_alert",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func shareLocationWithEmergencyContacts() {
        // This would integrate with your emergency contacts system
        // For now, just log
        print("📍 Sharing location with emergency contacts")
        
        // Could automatically share via SMS or push notification
        // to pre-defined emergency contacts
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Supporting Types

enum SafetyAlertLevel {
    case normal      // Everything is fine
    case warning     // Something seems off, checking in
    case critical    // Emergency situation
}

enum CheckInStatus {
    case safe        // User is safe, continue normally
    case needsHelp   // User needs emergency help
    case extending   // User is safe but needs more time
}

enum IncidentType {
    case fall              // Accelerometer detected fall
    case overtime          // Job running too long
    case stationary        // User hasn't moved
    case unusualMovement   // Rapid location change
}

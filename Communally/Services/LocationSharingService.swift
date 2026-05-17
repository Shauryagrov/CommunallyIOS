//
//  LocationSharingService.swift
//  Communally
//
//  Share live location with friends & family for safety
//

import Foundation
import CoreLocation
import UIKit

class LocationSharingService {
    static let shared = LocationSharingService()
    
    private init() {}
    
    /// Generate a shareable message with current location
    func generateLocationMessage(userName: String, jobTitle: String? = nil) -> String {
        guard let location = LocationManager.shared.location else {
            return "I'm using Communally! Download: https://communally.app"
        }
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        // Google Maps link (works on all platforms)
        let googleMapsLink = "https://www.google.com/maps?q=\(latitude),\(longitude)"
        
        // Apple Maps link (opens in Apple Maps on iOS)
        let appleMapsLink = "https://maps.apple.com/?ll=\(latitude),\(longitude)"
        
        var message = "📍 Hey! I'm \(userName) and I'm on my way to"
        
        if let job = jobTitle {
            message += " \"\(job)\""
        } else {
            message += " a job"
        }
        
        message += " via Communally.\n\n"
        message += "🗺 My live location:\n"
        message += "Google Maps: \(googleMapsLink)\n"
        message += "Apple Maps: \(appleMapsLink)\n\n"
        message += "🔒 Track me for safety!"
        
        return message
    }
    
    /// Share location via iOS share sheet
    func shareLocation(
        from viewController: UIViewController,
        userName: String,
        jobTitle: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        let message = generateLocationMessage(userName: userName, jobTitle: jobTitle)
        
        // Create activity view controller
        let activityVC = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )
        
        // Exclude some activities that don't make sense
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .print,
            .saveToCameraRoll
        ]
        
        // For iPad - set popover presentation
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        
        // Completion handler
        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                print("✅ Location shared successfully")
            }
            completion?()
        }
        
        viewController.present(activityVC, animated: true)
    }
    
    /// Get shareable coordinates as text
    func getCoordinatesText() -> String? {
        guard let location = LocationManager.shared.location else {
            return nil
        }
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        return "\(latitude), \(longitude)"
    }
    
    /// Check if location is available
    var isLocationAvailable: Bool {
        return LocationManager.shared.location != nil
    }
}

// MARK: - SwiftUI Helper

import SwiftUI

struct LocationSharingButton: View {
    let userName: String
    let jobTitle: String?

    init(userName: String, jobTitle: String? = nil) {
        self.userName = userName
        self.jobTitle = jobTitle
    }

    private var shareMessage: String {
        LocationSharingService.shared.generateLocationMessage(userName: userName, jobTitle: jobTitle)
    }

    var body: some View {
        let available = LocationSharingService.shared.isLocationAvailable

        ShareLink(item: shareMessage) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Share My Location")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CommunallyTheme.buttonGradient)
            .cornerRadius(12)
        }
        .disabled(!available)
        .opacity(available ? 1.0 : 0.5)
    }
}

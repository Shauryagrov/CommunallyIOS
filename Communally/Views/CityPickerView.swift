//
//  CityPickerView.swift
//  Communally
//
//  Sheet for picking a city to browse from when CoreLocation permission
//  isn't granted (or the user just wants to peek at jobs in another city).
//
//  Tapping a city calls LocationManager.shared.setManualLocation(city:),
//  which sets `manualLocation` + `manualLocationLabel`. The map view and
//  Browse view both read `effectiveLocation`, so the radius filter
//  re-centers immediately and the user sees jobs near their picked city.
//
//  Apple Guideline 5.1.5 requirement: the app stays functional without
//  Location Services. This sheet is the "I don't want to share my location
//  but I still want to use the app" escape hatch.
//
//  This sheet is also the canonical place we explain how to TURN ON
//  location after the user has denied it. Once iOS has the user's .denied
//  answer, `requestWhenInUseAuthorization()` is a silent no-op — the only
//  way to flip it is the Settings app. So instead of putting a broken
//  "Turn on location" button on the map / Browse banner, we put the full
//  instructions and an "Open Settings" deep link right here, in the same
//  sheet the user lands in when they tap the city picker icon.
//

import SwiftUI
import CoreLocation
import UIKit

struct CityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var searchText = ""

    private var filteredCities: [ManualBrowseCity] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ManualBrowseCity.popularUSCities }
        return ManualBrowseCity.popularUSCities.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var canStillPromptForLocation: Bool {
        locationManager.authorizationStatus == .notDetermined
    }

    private var locationIsDenied: Bool {
        locationManager.authorizationStatus == .denied
            || locationManager.authorizationStatus == .restricted
    }

    private var locationIsGranted: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
            || locationManager.authorizationStatus == .authorizedAlways
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 14) {
                        // Top "real location" card — adapts to whatever
                        // CoreLocation state the user is currently in.
                        // Three paths:
                        //   1. .notDetermined → "Turn on location" button
                        //      that DOES prompt iOS (still in the
                        //      one-shot window before user has answered).
                        //   2. .denied / .restricted → "Open Settings"
                        //      button + step-by-step instructions, since
                        //      requestWhenInUseAuthorization is a no-op
                        //      once the answer is on file.
                        //   3. .authorizedWhenInUse → confirmation badge.
                        locationStatusCard

                        // Friendly explainer of WHY the user might want to
                        // pick a city: covers both seeker and hirer flows
                        // so users understand what they're missing / what
                        // their hirers see.
                        roleExplainerCard

                        // Currently-selected pill (only when a manual city is set)
                        if let selected = locationManager.manualLocationLabel {
                            currentlyBrowsingCard(label: selected)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                }

                Divider()

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search cities", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // City list
                if filteredCities.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No matches")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.gray)
                        Text("Try a different city name. We currently support 40 major US metros.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredCities) { city in
                            Button {
                                locationManager.setManualLocation(city: city)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.displayName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(CommunallyTheme.darkGray)
                                    }
                                    Spacer()
                                    if locationManager.manualLocationLabel == city.displayName {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(CommunallyTheme.primaryGreen)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.gray.opacity(0.5))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Browse by city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var locationStatusCard: some View {
        if locationIsGranted {
            // Reassurance: location is on, manual city is just a "peek"
            // at other cities.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    Text("Location is on")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                }
                Text("You're seeing jobs near your current location. Picking a city below is just a quick way to peek at jobs in another area — you can clear it any time to go back to live results.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CommunallyTheme.primaryGreen.opacity(0.08))
            )
        } else if canStillPromptForLocation {
            // First-time path — iOS hasn't asked yet, so we can.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.white)
                    Text("Turn on location")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("See jobs that are actually close to you, sorted by distance. You can still pick a city below if you prefer.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    locationManager.requestLocationPermission { _ in }
                } label: {
                    Text("Turn on location")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white)
                        )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        } else if locationIsDenied {
            // iOS already has a .denied answer — requestWhenInUseAuth
            // does nothing. The ONLY way back is Settings. Tell the user
            // exactly which taps, with a deep link.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    Text("Turn on location in Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                }
                Text("Location is off for Communally. To get jobs near you, turn it on in iOS Settings:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    settingsStep(number: 1, text: "Tap **Open Settings** below")
                    settingsStep(number: 2, text: "Tap **Location**")
                    settingsStep(number: 3, text: "Choose **While Using the App**")
                    settingsStep(number: 4, text: "Come back here — jobs near you will load")
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Open Settings")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(CommunallyTheme.primaryGreen)
                    )
                }
                Text("Or just pick a city below to keep browsing without turning on location.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CommunallyTheme.primaryGreen.opacity(0.25), lineWidth: 1)
            )
        }
    }

    /// Numbered Settings step row. Renders **bold** markdown so the key
    /// nouns ("Location", "Open Settings") pop without a separate label.
    private func settingsStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .frame(width: 14, alignment: .leading)
            Text(.init(text))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Explains seeker vs. hirer location behavior so users understand
    /// what's different on each side. Especially important since hirers
    /// rely on a verified home address (entered in onboarding) and don't
    /// need live location permission — picking a city here is purely a
    /// seeker thing.
    private var roleExplainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How location works")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(CommunallyTheme.darkGray)
            VStack(alignment: .leading, spacing: 6) {
                roleRow(
                    icon: "magnifyingglass.circle.fill",
                    title: "Job seekers",
                    body: "We use your location (or a city you pick) to show jobs within your search radius. No location = browse a city of your choice instead."
                )
                roleRow(
                    icon: "house.circle.fill",
                    title: "Job hirers",
                    body: "We use the verified home address you entered during onboarding to route applicants to your jobs — live location isn't required."
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private func roleRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Text(body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func currentlyBrowsingCard(label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
            Text("Currently browsing: \(label)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)
            Spacer()
            Button("Reset") {
                locationManager.clearManualLocation()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(CommunallyTheme.primaryGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CommunallyTheme.primaryGreen.opacity(0.08))
        )
    }
}

#Preview {
    CityPickerView()
}

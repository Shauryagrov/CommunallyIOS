//
//  AddressSearchWithMiniMap.swift
//  Communally
//
//  Map-first home picker: tap map or use current location; address is reverse-geocoded.
//

import SwiftUI
import MapKit
import CoreLocation
import Contacts

struct AddressSearchWithMiniMap: View {
    @Binding var addressLine: String
    @Binding var resolvedCoordinate: CLLocationCoordinate2D?

    @ObservedObject private var locationManager = LocationManager.shared
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12))
    )
    @State private var waitingForUserLocation = false
    @State private var locationHint: String?
    @State private var isReverseGeocoding = false
    @State private var activeGeocoder: CLGeocoder?

    private var coordinateSignature: String {
        guard let c = resolvedCoordinate else { return "" }
        return "\(c.latitude),\(c.longitude)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap the map to drop your home pin, or use your current location.")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .bottomTrailing) {
                mapTapArea

                Button {
                    useMyLocationTapped()
                } label: {
                    Label("My location", systemImage: "location.fill")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(CommunallyTheme.primaryGreen, in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityLabel("Center map on my current location")
            }
            .frame(minHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )

            if let locationHint {
                Text(locationHint)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color.orange.opacity(0.95))
            }

            if isReverseGeocoding {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Looking up address…")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                }
            } else if resolvedCoordinate != nil, !addressLine.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CommunallyTheme.primaryGreen)
                        .font(.system(size: 14, weight: .semibold))
                    Text(addressLine)
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.25, green: 0.25, blue: 0.25))
                }
            }
        }
        .onAppear {
            // Do not request location here — permission is asked on the onboarding “Location & policies” step.
            if mapShowsUserLocation {
                locationManager.startLocationUpdates()
            }
            syncMapToCoordinateIfNeeded()
        }
        .onChange(of: coordinateSignature) { _, newSig in
            guard !newSig.isEmpty, let c = resolvedCoordinate else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mapPosition = .region(
                        MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12))
                    )
                }
                return
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                mapPosition = .region(
                    MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))
                )
            }
        }
        .onChange(of: locationManager.location?.coordinate.latitude) { _, _ in
            consumePendingUserLocationIfPossible()
        }
        .onChange(of: locationManager.location?.coordinate.longitude) { _, _ in
            consumePendingUserLocationIfPossible()
        }
    }

    private func consumePendingUserLocationIfPossible() {
        guard waitingForUserLocation, let loc = locationManager.location else { return }
        waitingForUserLocation = false
        applyCoordinate(loc.coordinate)
    }

    private var mapShowsUserLocation: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private var mapTapArea: some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate]) {
                if mapShowsUserLocation {
                    UserAnnotation()
                }
                if let c = resolvedCoordinate {
                    Annotation("Home", coordinate: c) {
                        Image(systemName: "house.circle.fill")
                            .font(.system(size: 40))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, CommunallyTheme.primaryGreen)
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                    }
                }
            }
            .mapStyle(.standard(elevation: .automatic, emphasis: .automatic, pointsOfInterest: .excludingAll, showsTraffic: false))
            // simultaneousGesture so pan/zoom still work; only short “taps” place the pin
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let travel = hypot(value.translation.width, value.translation.height)
                        guard travel < 14 else { return }
                        if let coord = proxy.convert(value.startLocation, from: .local) {
                            applyCoordinate(coord)
                        }
                    }
            )
        }
    }

    private func syncMapToCoordinateIfNeeded() {
        if let c = resolvedCoordinate {
            mapPosition = .region(
                MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))
            )
        } else if let loc = locationManager.location, GeoAppConstants.isCoordinateInUS(loc.coordinate) {
            mapPosition = .region(
                MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))
            )
        }
    }

    private func useMyLocationTapped() {
        locationHint = nil
        locationManager.requestLocationPermission { granted in
            guard granted else {
                locationHint = "Location is off. Enable it in Settings to use My location."
                waitingForUserLocation = false
                return
            }
            locationManager.startLocationUpdates()
            if let loc = locationManager.location, loc.timestamp.timeIntervalSinceNow > -120 {
                applyCoordinate(loc.coordinate)
                waitingForUserLocation = false
                return
            }
            waitingForUserLocation = true
            locationManager.requestLocation()
            scheduleUserLocationFallbackPoll()
        }
    }

    /// GPS can return without changing lat/lon from the last reading; poll briefly so “My location” still applies.
    private func scheduleUserLocationFallbackPoll() {
        Task { @MainActor in
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if !waitingForUserLocation { return }
                if let loc = locationManager.location {
                    waitingForUserLocation = false
                    applyCoordinate(loc.coordinate)
                    return
                }
            }
            if waitingForUserLocation {
                waitingForUserLocation = false
                locationHint = "Couldn’t get your location. Tap the map to set your home."
            }
        }
    }

    private func applyCoordinate(_ coord: CLLocationCoordinate2D) {
        guard GeoAppConstants.isCoordinateInUS(coord) else {
            locationHint = "Pick a spot inside the United States."
            return
        }
        locationHint = nil
        resolvedCoordinate = coord
        reverseGeocode(coord)
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(
                MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025))
            )
        }
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        activeGeocoder?.cancelGeocode()
        isReverseGeocoding = true
        let geocoder = CLGeocoder()
        activeGeocoder = geocoder
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")) { placemarks, error in
            DispatchQueue.main.async {
                isReverseGeocoding = false
                activeGeocoder = nil
                if let error {
                    addressLine = formattedFallback(coord)
                    locationHint = error.localizedDescription
                    return
                }
                guard let pm = placemarks?.first else {
                    addressLine = formattedFallback(coord)
                    return
                }
                if let postal = pm.postalAddress {
                    let fmt = CNPostalAddressFormatter()
                    addressLine = fmt.string(from: postal).replacingOccurrences(of: "\n", with: ", ")
                } else {
                    addressLine = formattedPlacemarkLines(pm, fallbackCoordinate: coord)
                }
            }
        }
    }

    private func formattedPlacemarkLines(_ pm: CLPlacemark, fallbackCoordinate: CLLocationCoordinate2D) -> String {
        let parts = [pm.subThoroughfare, pm.thoroughfare, pm.locality, pm.administrativeArea, pm.postalCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? formattedFallback(fallbackCoordinate) : parts.joined(separator: ", ")
    }

    private func formattedFallback(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.5f°, %.5f°", coord.latitude, coord.longitude)
    }
}

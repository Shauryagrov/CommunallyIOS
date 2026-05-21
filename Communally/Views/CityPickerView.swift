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

import SwiftUI

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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search field (no autocomplete API — just substring match
                // against the hardcoded popularUSCities list)
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

                // Currently-selected pill (only shown when a manual city is set)
                if let selected = locationManager.manualLocationLabel {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                        Text("Currently browsing: \(selected)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        Spacer()
                        Button("Reset") {
                            locationManager.clearManualLocation()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(CommunallyTheme.primaryGreen.opacity(0.08))
                }

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
            .navigationTitle("Pick a City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

#Preview {
    CityPickerView()
}

//
//  USAddressAutocompleteField.swift
//  Communally
//
//  MapKit address search so hirers pick a real US address (not free-typed garbage).
//

import SwiftUI
import MapKit
import Contacts
import Foundation

final class USAddressSearchCompleterModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = [.address]
        c.region = MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: GeoAppConstants.usMapSpan)
        c.pointOfInterestFilter = .excludingAll
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }

    func updateQuery(_ fragment: String) {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            suggestions = []
            isSearching = false
            completer.queryFragment = ""
            return
        }
        isSearching = true
        completer.queryFragment = trimmed
    }

    func clearSuggestions() {
        suggestions = []
    }

    /// After picking a suggestion, stop the completer from re-querying the full line (avoids flicker and extra `onChange` work).
    func stopCompleterAfterResolve() {
        completer.queryFragment = ""
        suggestions = []
        isSearching = false
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.isSearching = false
            self.suggestions = Array(completer.results.prefix(10))
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isSearching = false
            self.suggestions = []
        }
    }

    /// Resolves a suggestion to coordinates + formatted mailing address (US only).
    func resolve(
        _ completion: MKLocalSearchCompletion,
        done: @escaping (Result<(address: String, coordinate: CLLocationCoordinate2D), Error>) -> Void
    ) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                DispatchQueue.main.async { done(.failure(error)) }
                return
            }
            guard let item = response?.mapItems.first,
                  let coord = item.placemark.location?.coordinate,
                  GeoAppConstants.isCoordinateInUS(coord)
            else {
                DispatchQueue.main.async {
                    let msg = "That doesn’t look like a US address. Pick a full street address in the United States."
                    done(.failure(NSError(domain: "CommunallyAddress", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
                return
            }

            let formatted: String
            if let postal = item.placemark.postalAddress {
                let fmt = CNPostalAddressFormatter()
                formatted = fmt.string(from: postal).replacingOccurrences(of: "\n", with: ", ")
            } else {
                let t = completion.title
                let s = completion.subtitle
                formatted = s.isEmpty ? t : "\(t), \(s)"
            }

            DispatchQueue.main.async {
                done(.success((formatted, coord)))
            }
        }
    }
}

struct USAddressAutocompleteField: View {
    @Binding var addressLine: String
    @Binding var resolvedCoordinate: CLLocationCoordinate2D?
    @StateObject private var model = USAddressSearchCompleterModel()
    @FocusState private var fieldFocused: Bool
    @State private var resolveError: String?
    /// Prevents `onChange(of: addressLine)` from clearing `resolvedCoordinate` when we set the line from a map suggestion (SwiftUI can run that `onChange` after both assignments and wipe the coordinate).
    @State private var skipNextAddressChangeCoordinateReset = false

    private var trimmedQuery: String {
        addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showSuggestionList: Bool {
        fieldFocused && trimmedQuery.count >= 3 && !model.suggestions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addressTextField
            resolveErrorBanner
            verifiedRow
            suggestionList
        }
    }

    private var addressTextField: some View {
        TextField("Start typing your street address", text: $addressLine, axis: .vertical)
            .textFieldStyle(OnboardingOutlinedTextFieldStyle())
            .lineLimit(2...4)
            .textContentType(.fullStreetAddress)
            .focused($fieldFocused)
            .onChange(of: addressLine) { _, newValue in
                resolveError = nil
                if skipNextAddressChangeCoordinateReset {
                    skipNextAddressChangeCoordinateReset = false
                } else {
                    resolvedCoordinate = nil
                    model.updateQuery(newValue)
                }
            }
    }

    @ViewBuilder
    private var resolveErrorBanner: some View {
        if let resolveError {
            Text(resolveError)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(Color.red.opacity(0.9))
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var verifiedRow: some View {
        if resolvedCoordinate != nil {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                    .font(.system(size: 14, weight: .semibold))
                Text("US address selected — job posts will use this location")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.38))
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        if showSuggestionList {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, item in
                        suggestionButton(item)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .padding(.top, 8)
        }
    }

    private func suggestionButton(_ item: MKLocalSearchCompletion) -> some View {
        Button {
            resolveError = nil
            model.resolve(item) { result in
                switch result {
                case .success(let pair):
                    skipNextAddressChangeCoordinateReset = true
                    addressLine = pair.address
                    resolvedCoordinate = pair.coordinate
                    fieldFocused = false
                    model.stopCompleterAfterResolve()
                case .failure(let err):
                    resolvedCoordinate = nil
                    resolveError = err.localizedDescription
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

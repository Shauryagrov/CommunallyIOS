//
//  IdentityDocumentImageValidator.swift
//  Communally
//
//  Client-side checks so random screenshots are less likely to pass. True ID verification needs a provider (e.g. Stripe Identity).
//

import UIKit
import Vision

enum IdentityDocumentImageValidator {

    struct ValidationFailure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Minimum shorter edge in pixels (after orientation).
    private static let minShortEdgePixels: CGFloat = 640
    /// Allowed width/height ratio (document-ish).
    private static let minAspect: CGFloat = 0.35
    private static let maxAspect: CGFloat = 2.4
    /// Minimum bounding-box area (normalized) for a detected rectangle to count as a plausible document.
    private static let minRectArea: CGFloat = 0.07
    private static let minRectConfidence: Float = 0.4

    static func validate(_ image: UIImage, completion: @escaping (Result<Void, ValidationFailure>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(ValidationFailure(message: "Could not read this image. Try another photo.")))
            return
        }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let shortSide = min(w, h)
        let longSide = max(w, h)
        let aspect = longSide / max(shortSide, 1)

        guard shortSide >= minShortEdgePixels else {
            completion(.failure(ValidationFailure(message: "This photo is too small. Fill the frame with your ID so it’s sharp and readable.")))
            return
        }

        guard aspect >= minAspect && aspect <= maxAspect else {
            completion(.failure(ValidationFailure(message: "Use a normal photo of your ID (not an extreme crop or panorama).")))
            return
        }

        let request = VNDetectRectanglesRequest { request, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(ValidationFailure(message: "Could not analyze this image: \(error.localizedDescription)")))
                    return
                }

                let rects = (request.results as? [VNRectangleObservation]) ?? []
                let plausible = rects.filter { obs in
                    let area = obs.boundingBox.width * obs.boundingBox.height
                    return area >= minRectArea && obs.confidence >= minRectConfidence
                }

                if plausible.isEmpty {
                    completion(.failure(ValidationFailure(message: "We couldn’t detect a flat document in this photo. Lay your ID on a table, fill most of the frame, and use bright, even light.")))
                    return
                }

                completion(.success(()))
            }
        }

        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.3
        request.minimumSize = 0.12
        request.maximumObservations = 6
        request.quadratureTolerance = 26

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(ValidationFailure(message: "Could not check this photo. Try again or use a different image.")))
                }
            }
        }
    }
}

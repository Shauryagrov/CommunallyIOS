//
//  LocationBlurring.swift
//  Communally
//
//  Privacy primitive for the neighborhood map. Real GPS coordinates are
//  never exposed user-to-user — instead we publish a "map coordinate"
//  that's the real coordinate rounded to a ~500m grid + a daily
//  randomized jitter inside that grid cell. Two users at the same
//  address land at different pin spots, and the jitter rerolls every
//  24 hours so persistent triangulation is hard.
//
//  Why this design (Apple Guideline 5.1.2 + 1.3):
//    - 500m grid: enough fidelity to feel "neighborhood-local" without
//      being house-level identifying.
//    - Per-user-per-day random jitter inside the grid cell: prevents
//      "same address → same pin" inference, and prevents long-term
//      tracking via the published coordinate.
//    - Strict client-side: hirers/seekers never see the raw lat/lon.
//      Only `mapLatitude/Longitude` (this output) ships to other users.
//
//  Usage:
//      let blurred = LocationBlurring.blur(
//          realLatitude: 37.7749,
//          realLongitude: -122.4194,
//          seed: user.id + "-" + dayBucket()
//      )
//      // Persist `blurred` to user.mapLatitude / user.mapLongitude.
//

import Foundation
import CoreLocation

enum LocationBlurring {

    /// Approx. meters per degree of latitude. Constant at this scale.
    private static let metersPerDegreeLatitude: Double = 111_320

    /// Grid edge — rounding bin for the real coordinate. 500m feels
    /// "neighborhood" without being house-identifying.
    static let gridSizeMeters: Double = 500

    /// Max jitter (radius) inside the grid cell. ±300m keeps the
    /// resulting pin inside the 500m cell with room to spare.
    static let jitterMaxMeters: Double = 300

    /// Re-roll jitter every 24 hours. Other intervals work — the key
    /// property is "long enough that the pin is stable for a session
    /// but short enough that long-term tracking via this signal fails."
    static let blurRefreshInterval: TimeInterval = 24 * 60 * 60

    /// Whether the user's persisted blurred coord is fresh enough to
    /// reuse, or stale and should be recomputed.
    static func needsRefresh(_ lastUpdatedAt: Date?) -> Bool {
        guard let last = lastUpdatedAt else { return true }
        return Date().timeIntervalSince(last) > blurRefreshInterval
    }

    /// Returns a stable-for-24h grid+jitter coordinate derived from
    /// the real lat/lon. The same `seed` returns the same jitter for
    /// the same day bucket.
    static func blur(
        realLatitude: Double,
        realLongitude: Double,
        seed: String
    ) -> (latitude: Double, longitude: Double) {
        // 1. Snap to the nearest grid cell center.
        let metersPerDegreeLongitude = max(
            1,
            metersPerDegreeLatitude * cos(realLatitude * .pi / 180)
        )
        let latStep = gridSizeMeters / metersPerDegreeLatitude
        let lonStep = gridSizeMeters / metersPerDegreeLongitude
        let gridLat = (realLatitude / latStep).rounded() * latStep
        let gridLon = (realLongitude / lonStep).rounded() * lonStep

        // 2. Deterministic jitter from the seed. Same seed + same day
        //    → same jitter. Different seed → different jitter even at
        //    the exact same address.
        var rng = SeededRNG(seed: seed.hashValue)
        let angle = rng.nextDouble() * 2 * .pi
        let radiusMeters = rng.nextDouble() * jitterMaxMeters
        let dLat = (radiusMeters * cos(angle)) / metersPerDegreeLatitude
        let dLon = (radiusMeters * sin(angle)) / metersPerDegreeLongitude

        return (gridLat + dLat, gridLon + dLon)
    }

    /// Convenience: today's "day bucket" string for use as part of the
    /// per-day jitter seed. yyyy-MM-dd in UTC.
    static func currentDayBucket() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

/// Tiny deterministic PRNG so the blur is reproducible for a (user,
/// day) pair. NOT for cryptographic use — this is just so two devices
/// computing the same blurred coord for the same user on the same day
/// don't drift. xorshift64 style.
private struct SeededRNG {
    private var state: UInt64
    init(seed: Int) {
        // Map signed Int seed → non-zero UInt64. xorshift breaks on 0.
        let unsigned = UInt64(bitPattern: Int64(seed))
        state = (unsigned == 0) ? 0xdeadbeefcafebabe : unsigned
    }
    /// Returns a Double in [0, 1).
    mutating func nextDouble() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        // Top 53 bits → Double precision worth of randomness.
        return Double(state >> 11) / Double(1 << 53)
    }
}

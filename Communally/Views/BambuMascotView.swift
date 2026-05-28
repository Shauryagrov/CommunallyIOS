//
//  BambuMascotView.swift
//  Communally
//
//  Bambu the green panda — the Communally mascot.
//
//  Two render modes:
//    1. Image mode (preferred): pass an asset name from the catalog and
//       we render Image(assetName). Use a PNG or PDF/SVG with
//       "Preserve Vector Data" enabled for crisp scaling.
//    2. Shape mode (fallback): pure SwiftUI shapes — no PNG required.
//
//  When `assetName` is nil OR the named asset can't be loaded, we draw
//  the shape version so the app never shows a broken-image placeholder.
//
//  To swap in a designer-drawn mascot:
//      1. Drop the file into Assets.xcassets (e.g. "BambuMascot")
//      2. Either:
//           a) Pass `assetName: "BambuMascot"` at each call site, OR
//           b) Set `BambuMascotView.defaultAssetName = "BambuMascot"`
//              once at app launch — all existing call sites pick it up.
//
//  Usage:
//      BambuMascotView()                            // shape OR default asset
//      BambuMascotView(size: 120)                   // custom size
//      BambuMascotView(waving: true)                // animated wave
//      BambuMascotView(assetName: "BambuWaving")    // explicit image
//

import SwiftUI
import UIKit  // Explicit import — needed for UIImage(named:) availability check.

/// Bambu's expressive poses. Each maps to a named asset in
/// Assets.xcassets — the asset names match what was provided by the
/// designer (all-caps, no separator). Until the PNGs are dropped into
/// each .imageset folder, the shape fallback renders so the UI never
/// breaks.
enum BambuPose: String {
    case waving   = "COMMUNALLYMASCOTWAVE"     // arm up, smiling — intro / hello
    case thinking = "COMMUNALLYMASCOTTHINK"    // paw to chin — pondering / browsing
    case happy    = "COMMUNALLYMASCOTHAPPY"    // arms up, mid-celebration — excitement / action
    case hugging  = "COMMUNALLYMASCOTHUG"      // sitting, hugging heart — love / payoff
}

struct BambuMascotView: View {
    var size: CGFloat = 200
    var pose: BambuPose = .waving
    /// When true, ambient bob + (for waving pose) gentle rotation play
    /// on appear. Disable for static usage like tab icons or list rows.
    var animated: Bool = true
    /// Explicit asset-name override — bypasses `pose`. Useful for one-offs.
    var assetName: String? = nil

    /// Global swap point. Set this once (e.g. in CommunallyApp.init) to
    /// force every BambuMascotView to render the shape fallback even if
    /// assets exist — useful for testing the fallback path.
    nonisolated(unsafe) static var forceShapeRendering: Bool = false

    private var resolvedAssetName: String? {
        if Self.forceShapeRendering { return nil }
        return assetName ?? pose.rawValue
    }

    // Core palette — matches CommunallyTheme + a touch of cream for the face.
    private let greenDeep   = Color(red: 0.082, green: 0.502, blue: 0.282) // #15803d
    private let greenBright = Color(red: 0.133, green: 0.773, blue: 0.369) // #22c55e
    private let greenLeaf   = Color(red: 0.525, green: 0.937, blue: 0.604) // #86efac
    private let cream       = Color(red: 0.996, green: 0.992, blue: 0.976) // #fefdf9
    private let creamShadow = Color(red: 0.953, green: 0.937, blue: 0.886) // #f3efe2
    private let ink         = Color(red: 0.043, green: 0.078, blue: 0.063) // #0b1410
    private let blush       = Color(red: 0.992, green: 0.643, blue: 0.690) // #fda4af

    @State private var bob: CGFloat = 0
    @State private var waveAngle: Double = 0

    var body: some View {
        Group {
            // Image mode — preferred when the named asset exists.
            if let name = resolvedAssetName, UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    // Only the waving pose gets the gentle hand-wave rotation;
                    // other poses look weird if you rotate the whole figure.
                    .rotationEffect(.degrees(pose == .waving ? waveAngle : 0),
                                    anchor: .bottom)
                    .offset(y: animated ? bob : 0)
                    .onAppear { if animated { startAmbientAnimations() } }
            } else {
                shapeBambu
            }
        }
        // Treat the mascot as one decorative element for VoiceOver — its
        // semantic value is the surrounding copy (eyebrow + title + body),
        // not the shapes themselves. Parents that want the mascot announced
        // can override with `.accessibilityHidden(false).accessibilityLabel(...)`.
        .accessibilityElement()
        .accessibilityLabel("Bambu the panda, Communally's mascot")
        .accessibilityHidden(true)
    }

    /// Pure-SwiftUI shape rendering — original implementation kept as the
    /// fallback path so the app never shows a broken-asset placeholder.
    private var shapeBambu: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let unit = s / 240.0 // SVG was authored at 240x240

            ZStack {
                // Bamboo leaves (left + right)
                bambooLeaf
                    .frame(width: 50 * unit, height: 18 * unit)
                    .rotationEffect(.degrees(-22))
                    .offset(x: -84 * unit, y: 0)
                bambooLeaf
                    .frame(width: 50 * unit, height: 18 * unit)
                    .rotationEffect(.degrees(28))
                    .offset(x: 84 * unit, y: -10 * unit)

                // Body shadow / body
                Ellipse()
                    .fill(LinearGradient(colors: [greenBright, greenDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 124 * unit, height: 88 * unit)
                    .offset(y: 60 * unit)
                    .shadow(color: ink.opacity(0.18), radius: 6 * unit, x: 0, y: 4 * unit)

                // Belly patch
                Ellipse()
                    .fill(LinearGradient(colors: [cream, creamShadow], startPoint: .top, endPoint: .bottom))
                    .frame(width: 76 * unit, height: 52 * unit)
                    .offset(y: 66 * unit)
                    .opacity(0.95)

                // Arms
                // In shape mode, animate arms only for the `.waving` pose.
                Group {
                    let shouldWave = pose == .waving
                    Ellipse()
                        .fill(greenDeep)
                        .frame(width: 28 * unit, height: 22 * unit)
                        .offset(x: -52 * unit, y: 70 * unit)
                        .rotationEffect(.degrees(shouldWave ? -28 : 0), anchor: .top)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: shouldWave)
                    Ellipse()
                        .fill(greenDeep)
                        .frame(width: 28 * unit, height: 22 * unit)
                        .offset(x: 52 * unit, y: 70 * unit)
                        .rotationEffect(.degrees(shouldWave ? 28 : 0), anchor: .top)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: shouldWave)
                }

                // Feet
                Ellipse().fill(greenDeep).frame(width: 28 * unit, height: 18 * unit).offset(x: -28 * unit, y: 98 * unit)
                Ellipse().fill(greenDeep).frame(width: 28 * unit, height: 18 * unit).offset(x:  28 * unit, y: 98 * unit)

                // Ears
                Group {
                    Circle().fill(greenDeep).frame(width: 36 * unit, height: 36 * unit).offset(x: -52 * unit, y: -38 * unit)
                    Circle().fill(greenDeep).frame(width: 36 * unit, height: 36 * unit).offset(x:  52 * unit, y: -38 * unit)
                    Circle().fill(greenBright.opacity(0.8)).frame(width: 20 * unit, height: 20 * unit).offset(x: -52 * unit, y: -38 * unit)
                    Circle().fill(greenBright.opacity(0.8)).frame(width: 20 * unit, height: 20 * unit).offset(x:  52 * unit, y: -38 * unit)
                }

                // Head
                Circle()
                    .fill(LinearGradient(colors: [cream, creamShadow], startPoint: .top, endPoint: .bottom))
                    .frame(width: 120 * unit, height: 120 * unit)
                    .offset(y: -20 * unit)
                    .shadow(color: ink.opacity(0.15), radius: 6 * unit, x: 0, y: 4 * unit)

                // Eye patches
                Ellipse()
                    .fill(Color(red: 0.086, green: 0.639, blue: 0.290))
                    .frame(width: 32 * unit, height: 40 * unit)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -25 * unit, y: -20 * unit)
                Ellipse()
                    .fill(Color(red: 0.086, green: 0.639, blue: 0.290))
                    .frame(width: 32 * unit, height: 40 * unit)
                    .rotationEffect(.degrees(12))
                    .offset(x:  25 * unit, y: -20 * unit)

                // Cheek blush
                Circle().fill(blush.opacity(0.55)).blur(radius: 4 * unit).frame(width: 22 * unit, height: 22 * unit).offset(x: -38 * unit, y: 0)
                Circle().fill(blush.opacity(0.55)).blur(radius: 4 * unit).frame(width: 22 * unit, height: 22 * unit).offset(x:  38 * unit, y: 0)

                // Eyes
                Circle().fill(ink).frame(width: 10 * unit, height: 10 * unit).offset(x: -23 * unit, y: -18 * unit)
                Circle().fill(ink).frame(width: 10 * unit, height: 10 * unit).offset(x:  23 * unit, y: -18 * unit)
                Circle().fill(Color.white).frame(width: 3.2 * unit, height: 3.2 * unit).offset(x: -21.5 * unit, y: -20 * unit)
                Circle().fill(Color.white).frame(width: 3.2 * unit, height: 3.2 * unit).offset(x:  24.5 * unit, y: -20 * unit)

                // Nose
                NoseShape()
                    .fill(ink)
                    .frame(width: 12 * unit, height: 11 * unit)
                    .offset(y: -2 * unit)

                // Mouth
                MouthShape()
                    .stroke(ink, style: StrokeStyle(lineWidth: 2.2 * unit, lineCap: .round, lineJoin: .round))
                    .frame(width: 14 * unit, height: 8 * unit)
                    .offset(y: 8 * unit)

                // Tongue bridge from nose to mouth
                Rectangle()
                    .fill(ink)
                    .frame(width: 1.8 * unit, height: 5 * unit)
                    .offset(y: 4 * unit)
            }
            .offset(y: bob)
            .onAppear { startAmbientAnimations() }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size, height: size)
    }

    /// Single source of truth for ambient mascot motion. Both render modes
    /// trigger this so the bob (and image-mode wave) are identical.
    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            bob = -6
        }
        if pose == .waving {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                waveAngle = 8
            }
        }
    }

    // Bamboo leaf — leaf-shape with a center stem
    private var bambooLeaf: some View {
        ZStack {
            BambooLeafShape().fill(greenLeaf)
            BambooLeafShape()
                .stroke(greenDeep.opacity(0.4), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }
}

// MARK: - Shapes

private struct BambooLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.5))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.5))
        p.closeSubpath()
        return p
    }
}

private struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.4),
                       control: CGPoint(x: w * 1.1, y: 0))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                       control: CGPoint(x: w * 0.9, y: h * 1.05))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.4),
                       control: CGPoint(x: w * 0.1, y: h * 1.05))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                       control: CGPoint(x: -w * 0.1, y: 0))
        p.closeSubpath()
        return p
    }
}

private struct MouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: 0),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 1.1))
        return p
    }
}

#Preview("Waving") {
    BambuMascotView(size: 200, pose: .waving)
        .padding()
        .background(Color(red: 0.94, green: 0.98, blue: 0.94))
}

#Preview("Thinking") {
    BambuMascotView(size: 200, pose: .thinking)
        .padding()
        .background(Color(red: 0.94, green: 0.98, blue: 0.94))
}

#Preview("Jumping") {
    BambuMascotView(size: 200, pose: .happy)
        .padding()
        .background(Color(red: 0.94, green: 0.98, blue: 0.94))
}

#Preview("Hugging") {
    BambuMascotView(size: 200, pose: .hugging)
        .padding()
        .background(Color(red: 0.94, green: 0.98, blue: 0.94))
}

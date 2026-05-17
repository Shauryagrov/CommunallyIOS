//
//  GoogleLogoView.swift
//  Communally
//
//  Draws the official Google "G" icon using filled ring-arc paths.
//  Colors from Google Brand Guidelines. No white-circle hack — center is transparent.
//

import SwiftUI

struct GoogleLogoView: View {
    var size: CGFloat = 24

    // Official Google brand colors
    private let gBlue   = Color(red: 0.259, green: 0.522, blue: 0.957)  // #4285F4
    private let gRed    = Color(red: 0.918, green: 0.263, blue: 0.208)  // #EA4335
    private let gYellow = Color(red: 0.984, green: 0.737, blue: 0.020)  // #FBBC05
    private let gGreen  = Color(red: 0.204, green: 0.659, blue: 0.325)  // #34A853

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2

            let outerR = w * 0.46   // outer radius
            let innerR = w * 0.27   // inner radius — sets stroke thickness
            let barH   = w * 0.155  // crossbar height

            // Angles: 0° = right (3 o'clock), increases clockwise (SwiftUI convention).
            // Gap (opening of G) spans from 322° to 38° (~76° wide), centred on right.
            // Remaining 284° arc is split into four colour segments, going clockwise
            // from the bottom of the gap (38°):

            //  Green  38°  →  83°   (45°)  lower-right
            //  Yellow 83°  → 173°   (90°)  bottom + lower-left
            //  Red   173°  → 263°   (90°)  left + upper-left
            //  Blue  263°  → 322°   (59°)  top + upper-right

            drawSegment(&ctx, cx: cx, cy: cy, outerR: outerR, innerR: innerR,
                        from: 38,  to: 83,  color: gGreen)
            drawSegment(&ctx, cx: cx, cy: cy, outerR: outerR, innerR: innerR,
                        from: 83,  to: 173, color: gYellow)
            drawSegment(&ctx, cx: cx, cy: cy, outerR: outerR, innerR: innerR,
                        from: 173, to: 263, color: gRed)
            drawSegment(&ctx, cx: cx, cy: cy, outerR: outerR, innerR: innerR,
                        from: 263, to: 322, color: gBlue)

            // Crossbar — blue rectangle from center rightward to the outer edge,
            // vertically centred, height = barH.
            let barRect = CGRect(
                x: cx,
                y: cy - barH / 2,
                width: outerR,
                height: barH
            )
            ctx.fill(Path(barRect), with: .color(gBlue))
        }
        .frame(width: size, height: size)
    }

    // Draws one filled ring-arc segment (donut sector) for a given colour.
    private func drawSegment(
        _ ctx: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        outerR: CGFloat, innerR: CGFloat,
        from startDeg: Double, to endDeg: Double,
        color: Color
    ) {
        let center = CGPoint(x: cx, y: cy)
        var path = Path()

        // Outer arc (clockwise)
        path.addArc(center: center, radius: outerR,
                    startAngle: .degrees(startDeg),
                    endAngle:   .degrees(endDeg),
                    clockwise: false)

        // Connect to inner arc and trace it back (counter-clockwise)
        path.addArc(center: center, radius: innerR,
                    startAngle: .degrees(endDeg),
                    endAngle:   .degrees(startDeg),
                    clockwise: true)

        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }
}

#Preview {
    HStack(spacing: 24) {
        GoogleLogoView(size: 20)
        GoogleLogoView(size: 32)
        GoogleLogoView(size: 48)
    }
    .padding(24)
    .background(Color.white)
}

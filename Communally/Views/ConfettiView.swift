//
//  ConfettiView.swift
//  Communally
//
//  Lightweight celebration confetti rendered with Canvas + TimelineView.
//  No third-party dependencies. Trigger by incrementing the bound `trigger`.
//

import SwiftUI

struct ConfettiView: View {
    @Binding var trigger: Int
    var duration: Double = 1.6
    var pieceCount: Int = 60

    @State private var bursts: [Burst] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: bursts.isEmpty)) { context in
            Canvas { ctx, size in
                let now = context.date.timeIntervalSinceReferenceDate
                for burst in bursts {
                    let elapsed = now - burst.startedAt
                    guard elapsed >= 0, elapsed <= duration else { continue }
                    let t = elapsed / duration

                    for piece in burst.pieces {
                        let progress = min(max(t / piece.life, 0), 1)
                        // Project from a top-center origin with horizontal drift.
                        let x = size.width * 0.5
                            + piece.dx * size.width * 0.55 * CGFloat(progress)
                        let y = -40
                            + (size.height + 80) * CGFloat(progress)
                            + sin(progress * .pi * piece.wobble) * 14
                        let rotation = piece.rotation + .degrees(360 * progress * piece.spin)

                        var rect = CGRect(x: x, y: y, width: piece.size, height: piece.size * 0.55)
                        rect = rect.offsetBy(dx: -piece.size / 2, dy: -piece.size / 2)

                        let path = Path(roundedRect: rect, cornerSize: CGSize(width: 1.2, height: 1.2))
                        let opacity = 1.0 - max(0, progress - 0.7) / 0.3
                        ctx.drawLayer { layer in
                            layer.translateBy(x: rect.midX, y: rect.midY)
                            layer.rotate(by: rotation)
                            layer.translateBy(x: -rect.midX, y: -rect.midY)
                            layer.opacity = opacity
                            layer.fill(path, with: .color(piece.color))
                        }
                    }
                }
            }
            .onChange(of: context.date) { _ in
                pruneFinished(now: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _ in
            spawnBurst()
        }
    }

    private func spawnBurst() {
        let pieces = (0..<pieceCount).map { _ in Piece.random() }
        bursts.append(Burst(startedAt: Date().timeIntervalSinceReferenceDate, pieces: pieces))
    }

    private func pruneFinished(now: TimeInterval) {
        bursts.removeAll { now - $0.startedAt > duration + 0.1 }
    }

    private struct Burst {
        let startedAt: TimeInterval
        let pieces: [Piece]
    }

    private struct Piece {
        let dx: CGFloat
        let size: CGFloat
        let color: Color
        let rotation: Angle
        let spin: CGFloat
        let wobble: CGFloat
        let life: CGFloat

        static func random() -> Piece {
            let palette: [Color] = [
                CommunallyTheme.primaryGreen,
                CommunallyTheme.secondaryGreen,
                CommunallyTheme.lightGreen,
                Color(red: 0.98, green: 0.82, blue: 0.30),
                Color(red: 0.96, green: 0.45, blue: 0.62)
            ]
            return Piece(
                dx: CGFloat.random(in: -1...1),
                size: CGFloat.random(in: 6...12),
                color: palette.randomElement() ?? CommunallyTheme.primaryGreen,
                rotation: .degrees(Double.random(in: 0...360)),
                spin: CGFloat.random(in: 0.6...2.4),
                wobble: CGFloat.random(in: 1.5...3.5),
                life: CGFloat.random(in: 0.78...1.0)
            )
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var trigger = 0
        var body: some View {
            ZStack {
                Color.white.ignoresSafeArea()
                Button("🎉 Pop") { trigger += 1 }
                    .font(.title)
                ConfettiView(trigger: $trigger)
            }
        }
    }
    return Demo()
}

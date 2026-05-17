//
//  LoadingOverlayManager.swift
//  Communally
//
//  Lightweight global "we're doing something slow" indicator. Any view can
//  call `LoadingOverlayManager.shared.show("…")` before a long-running task
//  and `hide()` when it finishes. The overlay only appears if the work takes
//  longer than ~250ms — fast operations don't flicker an unnecessary popup.
//

import SwiftUI

final class LoadingOverlayManager: ObservableObject {
    static let shared = LoadingOverlayManager()

    @Published var isShowing: Bool = false
    @Published var message: String = "Loading…"

    private var pendingShowWorkItem: DispatchWorkItem?
    /// Tracks active "show" calls so nested operations don't hide each other.
    private var activeRequests: Int = 0
    /// Don't flash the spinner for sub-250ms operations.
    private let showAfter: TimeInterval = 0.25

    private init() {}

    /// Schedule the spinner to appear after `showAfter`. Pair with `hide()`.
    func show(_ message: String = "Loading…") {
        DispatchQueue.main.async {
            self.activeRequests += 1
            self.message = message
            self.pendingShowWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.activeRequests > 0 {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.isShowing = true
                    }
                }
            }
            self.pendingShowWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.showAfter, execute: work)
        }
    }

    /// Cancels a pending show or hides a visible spinner.
    func hide() {
        DispatchQueue.main.async {
            self.activeRequests = max(0, self.activeRequests - 1)
            if self.activeRequests == 0 {
                self.pendingShowWorkItem?.cancel()
                self.pendingShowWorkItem = nil
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.isShowing = false
                }
            }
        }
    }
}

struct LoadingOverlayView: View {
    @ObservedObject private var manager = LoadingOverlayManager.shared

    var body: some View {
        if manager.isShowing {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: CommunallyTheme.primaryGreen))
                        .scaleEffect(1.2)
                    Text(manager.message)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(24)
                .frame(minWidth: 160)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 8)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            .zIndex(9999)
        }
    }
}

//
//  AnimationExtensions.swift
//  Communally
//
//  Smooth animations and transitions for professional UX
//

import SwiftUI

// MARK: - View Extensions for Animations

extension View {
    /// Fade in animation
    func fadeIn(duration: Double = 0.4, delay: Double = 0) -> some View {
        self.modifier(FadeInModifier(duration: duration, delay: delay))
    }
    
    /// Slide in from bottom animation
    func slideInFromBottom(duration: Double = 0.5, delay: Double = 0) -> some View {
        self.modifier(SlideInFromBottomModifier(duration: duration, delay: delay))
    }
    
    /// Slide in from top animation
    func slideInFromTop(duration: Double = 0.5, delay: Double = 0) -> some View {
        self.modifier(SlideInFromTopModifier(duration: duration, delay: delay))
    }
    
    /// Scale in animation
    func scaleIn(duration: Double = 0.4, delay: Double = 0) -> some View {
        self.modifier(ScaleInModifier(duration: duration, delay: delay))
    }
    
    /// Add shimmer loading effect
    func shimmer(isLoading: Bool) -> some View {
        self.modifier(ShimmerModifier(isLoading: isLoading))
    }
    
    /// Add smooth card shadow
    func cardShadow(color: Color = .black, opacity: Double = 0.1, radius: CGFloat = 10, y: CGFloat = 4) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: y)
    }
    
    /// Add interactive card effect
    func interactiveCard() -> some View {
        self.modifier(InteractiveCardModifier())
    }
    
    /// Apply staggered animation
    func staggered(index: Int, total: Int) -> some View {
        self.modifier(StaggeredAnimation(index: index, total: total))
    }
}

// MARK: - Animation Modifiers

struct FadeInModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    opacity = 1
                }
            }
    }
}

struct SlideInFromBottomModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var offset: CGFloat = 50
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.8).delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

struct SlideInFromTopModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var offset: CGFloat = -50
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.8).delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

struct ScaleInModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.7).delay(delay)) {
                    scale = 1.0
                    opacity = 1
                }
            }
    }
}

struct ShimmerModifier: ViewModifier {
    let isLoading: Bool
    @State private var shimmerOffset: CGFloat = -1
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isLoading {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width)
                        .offset(x: shimmerOffset * geometry.size.width)
                        .animation(
                            .linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: shimmerOffset
                        )
                        .onAppear {
                            shimmerOffset = 2
                        }
                    }
                }
            )
    }
}

struct InteractiveCardModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - Loading States

struct LoadingView: View {
    let message: String
    
    init(message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(CommunallyTheme.primaryGreen)
            
            Text(message)
                .font(.system(size: 16, weight: .medium, design: .default))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false
    let color: Color
    let size: CGFloat
    
    init(color: Color = CommunallyTheme.primaryGreen, size: CGFloat = 12) {
        self.color = color
        self.size = size
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isPulsing ? 1.2 : 0.8)
            .opacity(isPulsing ? 1.0 : 0.5)
            .animation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Staggered Animation

struct StaggeredAnimation: ViewModifier {
    let index: Int
    let total: Int
    @State private var appeared = false
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                let delay = Double(index) * 0.1
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Success Checkmark Animation

struct AnimatedCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.5
    let size: CGFloat
    let color: Color
    
    init(size: CGFloat = 60, color: Color = .green) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: 1)
                .stroke(color, lineWidth: 3)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            
            Path { path in
                path.move(to: CGPoint(x: size * 0.3, y: size * 0.5))
                path.addLine(to: CGPoint(x: size * 0.45, y: size * 0.65))
                path.addLine(to: CGPoint(x: size * 0.7, y: size * 0.35))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
            }
            withAnimation(.easeInOut(duration: 0.5).delay(0.2)) {
                trimEnd = 1.0
            }
        }
    }
}


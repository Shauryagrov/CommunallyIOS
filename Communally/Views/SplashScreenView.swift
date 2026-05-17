//
//  SplashScreenView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var scale = 1.04
    @State private var opacity = 0.0

    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                CommunallyTheme.primaryGreen
                    .ignoresSafeArea()

                Image("SplashScreenArtwork")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) {
                    opacity = 1.0
                    scale = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isActive = true
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}

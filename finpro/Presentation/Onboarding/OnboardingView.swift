//
//  OnboardingView.swift
//  finpro
//

import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingSplashView(logoTop: logoTop)
            .background(Color.screenBackground.ignoresSafeArea())
            .task {
                try? await Task.sleep(for: reduceMotion ? .milliseconds(650) : OnboardingSplashView.duration)
                guard !Task.isCancelled else { return }
                onContinue()
            }
    }

    private func logoTop(in proxy: GeometryProxy) -> CGFloat {
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        return max(0, screenHeight * (322.0 / 874.0) - proxy.safeAreaInsets.top)
    }
}

#Preview { OnboardingView(onContinue: {}) }

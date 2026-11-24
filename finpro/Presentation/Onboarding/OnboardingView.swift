//
//  OnboardingView.swift
//  finpro
//

import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void
    @State private var showsWelcome: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(startsAtWelcome: Bool = false, onContinue: @escaping () -> Void) {
        _showsWelcome = State(initialValue: startsAtWelcome)
        self.onContinue = onContinue
    }

    var body: some View {
        Group {
            if showsWelcome {
                welcome
            } else {
                GeometryReader { proxy in
                    BrandLogoView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, logoTop(in: proxy))
                }
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    showsWelcome = true
                }
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsWelcome)
    }

    /// The logo starts at y=322 on the 874 pt Sketch canvas.
    private func logoTop(in proxy: GeometryProxy) -> CGFloat {
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        return max(0, screenHeight * (322.0 / 874.0) - proxy.safeAreaInsets.top)
    }

    private var welcome: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                BrandLogoView()
                    .padding(.top, logoTop(in: proxy))
                Spacer(minLength: 24)
                VStack(spacing: 0) {
                    Text("Record covers effortlessly").font(.appTitle2).fontWeight(.bold)
                        .foregroundStyle(Color.primaryBrand)
                    Text("A smoother way to create\nyour singing covers.")
                        .font(.appBody).foregroundStyle(Color.primary300)
                }
                .multilineTextAlignment(.center)
                Button("Get Started", action: onContinue)
                    .buttonStyle(.appPrimary)
                    .padding(.top, 65)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 25)
        }
    }

}

#Preview { OnboardingView(onContinue: {}) }

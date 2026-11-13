//
//  OnboardingView.swift
//  finpro
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var currentStep = -2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let titles = ["Stay on pitch,\nas you sing.", "Retake less.\nCreate more.", "Find a key that fits\nyour voice."]
    private let subtitles = [
        "Follow visual pitch and timing cues while recording your cover.",
        "Redo a phrase and keep your best take in one seamless cover.",
        "We'll transpose songs to match your voice, so you can sing comfortably."
    ]

    var body: some View {
        Group {
            if currentStep == -2 {
                EasySingLogoView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        withAnimation { currentStep = -1 }
                    }
            } else if currentStep == -1 {
                welcome
            } else {
                walkthrough
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: currentStep < 0)
    }

    private var welcome: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                EasySingLogoView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 10) {
                    Text("Record covers effortlessly.").font(.appTitle2)
                        .foregroundStyle(Color.primaryBrand)
                    Text("A smoother way to create your singing covers.")
                        .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                }
                .multilineTextAlignment(.center)
                Button { currentStep = 0 } label: {
                    HStack(spacing: AppSpacing.small) {
                        Text("Get Started")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.appPrimary)
                .frame(maxWidth: 246)
                .padding(.top, 32)
                .padding(.bottom, proxy.size.height * 0.12)
            }
            .padding(.horizontal, 24)
        }
    }

    private var walkthrough: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation { currentStep -= 1 } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.appIcon(.glass))
                .accessibilityLabel("Back")
                Spacer()
                if currentStep < 2 {
                    Button("Skip", action: onFinish)
                        .font(.appSubheadline).foregroundStyle(Color.primary)
                        .glassCapsuleButtonStyle()
                }
            }
            .padding(.horizontal, 16)

            TabView(selection: $currentStep) {
                ForEach(0..<3) { index in
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(titles[index]).font(.appLargeTitle)
                                    .foregroundStyle(Color.primaryBrand)
                                    .accessibilityAddTraits(.isHeader)
                                Text(subtitles[index]).font(.appBody)
                                    .foregroundStyle(Color.secondaryText)
                                    .frame(maxWidth: 335, alignment: .leading)
                                    .padding(.top, 10)
                                    .frame(minHeight: 54, alignment: .topLeading)
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .fill(Color.primary800)
                                    .frame(height: max(220, proxy.size.height - 214))
                                    .padding(.top, 24)
                                    .accessibilityLabel("Illustration placeholder")
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 44)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Capsule().fill(index == currentStep ? Color.primary800 : Color.gray.opacity(0.4))
                        .frame(width: index == currentStep ? 18 : 6, height: 6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white, in: Capsule())
            .accessibilityLabel("Page \(currentStep + 1) of 3")
            .padding(.top, 12)

            Group {
                if currentStep == 2 {
                    Button("Find my vocal range", action: onFinish).buttonStyle(.appPrimary)
                } else {
                    Color.clear.frame(height: 56).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
        }
    }
}

#Preview { OnboardingView(onFinish: {}) }

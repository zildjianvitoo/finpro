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
        "We’ll highlight clips that need a retake, so you can re-record just that section.",
        "We'll transpose songs to match your voice, so you can sing with confidence."
    ]

    var body: some View {
        Group {
            if currentStep == -2 {
                BrandLogoView()
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
        // Logo in the upper part, as in the 1.2 Welcome Screen design (top at ~23% of the safe area).
        GeometryReader { proxy in
            VStack(spacing: 0) {
                BrandLogoView()
                    .padding(.top, proxy.size.height * 0.23)
                Spacer(minLength: 24)
                VStack(spacing: 0) {
                    Text("Record covers effortlessly").font(.appTitle2).fontWeight(.bold)
                        .foregroundStyle(Color.primaryBrand)
                    Text("A smoother way to create\nyour singing covers.")
                        .font(.appBody).foregroundStyle(Color.primary300)
                }
                .multilineTextAlignment(.center)
                Button("Get Started") { currentStep = 0 }
                    .buttonStyle(.appPrimary)
                    .padding(.top, 65)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 25)
        }
    }

    private var isLastPage: Bool { currentStep == 2 }
    private var pageAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.25) }

    private var walkthrough: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation { currentStep -= 1 } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.appIcon(.glass))
                .accessibilityLabel("Back")
                Spacer()
                // Kept in the layout on the last page (only faded out), so the header height and
                // with it the pages don't jump when the last page is reached.
                Button("Skip", action: onFinish)
                    .font(.appBody).fontWeight(.medium).foregroundStyle(Color.primary)
                    .glassCapsuleButtonStyle()
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
                    .accessibilityHidden(isLastPage)
                    .animation(pageAnimation, value: isLastPage)
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
                                    .foregroundStyle(Color.primary300)
                                    .frame(maxWidth: 335, alignment: .leading)
                                    .padding(.top, 8)
                                    .frame(minHeight: 52, alignment: .topLeading)
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .fill(Color.primaryBrand)
                                    .frame(height: max(220, proxy.size.height - 212))
                                    .padding(.top, 34)
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
                        .frame(width: index == currentStep ? 20 : 8, height: 8)
                }
            }
            .animation(pageAnimation, value: currentStep)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white, in: Capsule())
            .accessibilityLabel("Page \(currentStep + 1) of 3")
            .padding(.top, 15)

            // Always laid out (faded in on the last page), so nothing moves when it appears.
            Button("Find my vocal range", action: onFinish).buttonStyle(.appPrimary)
                .opacity(isLastPage ? 1 : 0)
                .offset(y: isLastPage || reduceMotion ? 0 : 8)
                .disabled(!isLastPage)
                .accessibilityHidden(!isLastPage)
                .animation(pageAnimation, value: isLastPage)
                .padding(.horizontal, 25).padding(.top, 16).padding(.bottom, 16)
        }
    }
}

#Preview { OnboardingView(onFinish: {}) }

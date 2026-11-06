//
//  OnboardingView.swift
//  finpro
//
//  App onboarding and walkthrough flow: Splash + 3 swipeable guide screens.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    /// -1: Splash screen, 0..2: Walkthrough steps
    @State private var currentStep: Int = -1

    private struct WalkthroughPage {
        let badge: String
        let title: String
        let subtitle: String
        let imageName: String
        let buttonTitle: String
    }

    private let pages: [WalkthroughPage] = [
        WalkthroughPage(
            badge: "VOCAL GUIDE",
            title: "Stay on pitch, as you sing.",
            subtitle: "Follow visual pitch and timing guides as you record.",
            imageName: "onboarding-2",
            buttonTitle: "Continue"
        ),
        WalkthroughPage(
            badge: "SEAMLESS RECORDING",
            title: "Retake less. Create more.",
            subtitle: "Redo specific parts without restarting. Your takes come together in one cover.",
            imageName: "onboarding-3",
            buttonTitle: "Continue"
        ),
        WalkthroughPage(
            badge: "SETUP",
            title: "Get your setup ready.",
            subtitle: "Use wired earphones or headphones for more synchronized audio. Bluetooth may cause recording delays.",
            imageName: "onboarding-4",
            buttonTitle: "I'm ready"
        )
    ]

    var body: some View {
        Group {
            if currentStep < 0 {
                splashScreen
                    .transition(.opacity)
            } else {
                walkthroughContainer
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.default, value: currentStep < 0)
        .background(Color(.systemBackground))
    }

    // MARK: - Splash Screen

    private var splashScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            EasySingLogoView()
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Make your cover easier.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Text("A smoother way to record your singing covers.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)

                Button("Get started") {
                    withAnimation { currentStep = 0 }
                }
                .buttonStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Walkthrough Container (Swipeable)

    private var walkthroughContainer: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $currentStep) {
                ForEach(0..<pages.count, id: \.self) { index in
                    pageContent(for: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
    }

    private func pageContent(for page: WalkthroughPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                badgeView(title: page.badge)

                Text(page.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text(page.subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Image(page.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Top Bar (with Liquid Glass)

    private var topBar: some View {
        LiquidGlassGroup {
            HStack {
                Button {
                    withAnimation {
                        if currentStep == 0 {
                            currentStep = -1
                        } else {
                            currentStep -= 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .liquidGlassCircle()

                Spacer()

                if currentStep < pages.count - 1 {
                    Button(action: onFinish) {
                        Text("Skip")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassCapsule()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private func badgeView(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.badgeBackground))
    }

    // MARK: - Footer

    private var footer: some View {
        let isLastPage = currentStep >= pages.count - 1
        let buttonTitle = isLastPage ? "I'm ready" : "Continue"

        return VStack(spacing: 20) {
            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.primary : Color(.systemGray4))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }

            Button(buttonTitle) {
                if !isLastPage {
                    withAnimation { currentStep += 1 }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color(.systemBackground))
    }
}

#Preview {
    OnboardingView(onFinish: {})
}

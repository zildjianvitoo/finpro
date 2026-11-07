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

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Inset of the text and illustrations, deeper than the buttons per the design.
    private let contentInset: CGFloat = 44

    private struct WalkthroughPage {
        let badge: String
        let title: String
        let subtitle: String
        let imageName: String
        var proTip: String?
    }

    private let pages: [WalkthroughPage] = [
        WalkthroughPage(
            badge: "VOCAL GUIDE",
            title: "Stay on pitch, as you sing.",
            subtitle: "Follow visual pitch and timing guides as you record.",
            imageName: "onboarding-2"
        ),
        WalkthroughPage(
            badge: "SEAMLESS RECORDING",
            title: "Retake less. Create more.",
            subtitle: "Redo specific parts without restarting. Your takes come together in one cover.",
            imageName: "onboarding-3"
        ),
        WalkthroughPage(
            badge: "SETUP",
            title: "Get your setup ready.",
            subtitle: "Use wired earphones or headphones for more synchronized audio. Bluetooth may cause recording delays.",
            imageName: "onboarding-4",
            proTip: "Pro tip: Connect your wired headphones before you start recording."
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
        .background(Color.onboardingBackground.ignoresSafeArea())
    }

    // MARK: - Splash Screen

    private var splashScreen: some View {
        VStack(spacing: 0) {
            // Centered in the space above the text, nudged up as in the design.
            EasySingLogoView()
                .frame(maxHeight: .infinity)
                .padding(.bottom, 50)

            VStack(spacing: 12) {
                Text("Make your cover easier.")
                    .font(.title.bold())
                    .foregroundStyle(Color.plumInk)

                Text("A smoother way to record your singing covers.")
                    .font(.callout)
                    .foregroundStyle(Color.plumInkSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, contentInset)
            .padding(.bottom, 44)

            Button("Get started") {
                withAnimation { currentStep = 0 }
            }
            .buttonStyle(.primaryDeep)
            .padding(.horizontal, buttonInset)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Walkthrough Container (Swipeable)

    private var walkthroughContainer: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 20) {
                    pager
                    pageDots
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
    }

    /// The hidden copies give the pager the height of its tallest page,
    /// so the dots sit right under the illustration instead of at the bottom.
    private var pager: some View {
        ZStack {
            ForEach(pages.indices, id: \.self) { index in
                pageContent(for: pages[index])
            }
        }
        .hidden()
        .overlay {
            TabView(selection: $currentStep) {
                ForEach(pages.indices, id: \.self) { index in
                    pageContent(for: pages[index])
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func pageContent(for page: WalkthroughPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            badgeView(title: page.badge)
                .padding(.bottom, 12)

            Text(page.title)
                .font(.title.bold())
                .foregroundStyle(Color.plumInk)
                .padding(.bottom, 8)

            Text(page.subtitle)
                .font(.callout)
                .foregroundStyle(Color.plumInkSecondary)
                .padding(.bottom, 32)

            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    if let proTip = page.proTip {
                        OnboardingProTipView(text: proTip)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, contentInset)
        .padding(.top, 8)
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
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Back")

                Spacer()

                if currentStep < pages.count - 1 {
                    Button(action: onFinish) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .glassCapsuleButtonStyle()
                }
            }
            .padding(.horizontal, buttonInset)
            .padding(.bottom, 2)
        }
    }

    private func badgeView(title: String) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.badgeBackground))
    }

    // MARK: - Page Dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.primary : Color(.systemGray4))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(.systemBackground)))
        .animation(.easeInOut(duration: 0.2), value: currentStep)
        .accessibilityElement()
        .accessibilityLabel("Page \(currentStep + 1) of \(pages.count)")
    }

    // MARK: - Footer

    private var footer: some View {
        let isLastPage = currentStep >= pages.count - 1
        let buttonTitle = isLastPage ? "I'm ready" : "Continue"

        return Button(buttonTitle) {
            if !isLastPage {
                withAnimation { currentStep += 1 }
            } else {
                onFinish()
            }
        }
        .buttonStyle(.primaryDeep)
        .padding(.horizontal, buttonInset)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}

//
//  OnboardingSplashView.swift
//  finpro
//

import SwiftUI

struct OnboardingSplashView: View {
    static let duration: Duration = .milliseconds(2_650)
    let logoTop: (GeometryProxy) -> CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = ContinuousClock.now

    // The existing mascot artwork is 245 × 300. Anchor the zoom on its face.
    private static let mascotHeight: CGFloat = 105
    private static let mascotWidth: CGFloat = mascotHeight * 245 / 300
    private static let face = UnitPoint(x: 0.40, y: 0.69)

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                BrandLogoView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, logoTop(proxy))
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
                    animatedLogo(in: proxy, elapsed: (ContinuousClock.now - start) / .seconds(1))
                }
            }
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verca")
    }

    private func animatedLogo(in proxy: GeometryProxy, elapsed: Double) -> some View {
        let reveal = eased(elapsed, from: 0.98, to: 1.95)
        let wordmark = eased(elapsed, from: 1.53, to: 2.14)
        let eyesFade = eased(elapsed, from: 1.50, to: 1.94)
        let zoom = max(proxy.size.width / 45, proxy.size.height / 89)
        let faceOffsetX = Self.mascotWidth * (0.5 - Self.face.x)
        let faceY = logoTop(proxy) + Self.mascotHeight * Self.face.y

        return VStack(spacing: 8) {
            Image("BrandMascot").resizable().scaledToFit()
                .opacity(eased(elapsed, from: 0.82, to: 1.22))
                .overlay { eyes(at: elapsed).opacity(1 - eyesFade) }
                .frame(width: Self.mascotWidth, height: Self.mascotHeight)
                .scaleEffect(1 + (zoom - 1) * (1 - reveal), anchor: Self.face)
                .offset(x: faceOffsetX * (1 - reveal),
                        y: (proxy.size.height * 0.67 - faceY) * (1 - reveal))
                .zIndex(1)

            Text("Verca")
                .font(.appLargeTitle)
                .foregroundStyle(Color.primaryBrand)
                .opacity(wordmark)
                .offset(y: 12 * (1 - wordmark))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, logoTop(proxy))
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Color(red: 235 / 255, green: 150 / 255, blue: 196 / 255)
                .opacity(1 - eased(elapsed, from: 0.84, to: 1.32))
                .ignoresSafeArea()
        }
    }

    private func eyes(at elapsed: Double) -> some View {
        let unit = Self.mascotHeight / 300
        let look = 8 - 16 * eased(elapsed, from: 0.18, to: 0.47)
            + 8 * eased(elapsed, from: 0.64, to: 0.97)
        let blink = eased(elapsed, from: 1.22, to: 1.31)
            - eased(elapsed, from: 1.35, to: 1.47)
        return ZStack(alignment: .topLeading) {
            eye(unit: unit, look: look, blink: blink).position(x: 76 * unit, y: 210 * unit)
            eye(unit: unit, look: look, blink: blink).position(x: 126 * unit, y: 206 * unit)
        }
        .frame(width: Self.mascotWidth, height: Self.mascotHeight)
    }

    private func eye(unit: CGFloat, look: Double, blink: Double) -> some View {
        Circle().fill(.white)
            .overlay {
                Circle().fill(.black)
                    .frame(width: 31 * unit, height: 31 * unit)
                    .scaleEffect(y: max(0.16, 1 - blink))
                    .offset(x: look * unit)
            }
            .frame(width: 55 * unit, height: 55 * unit)
    }

    private func eased(_ value: Double, from start: Double, to end: Double) -> Double {
        let progress = min(1, max(0, (value - start) / (end - start)))
        return progress * progress * (3 - 2 * progress)
    }
}

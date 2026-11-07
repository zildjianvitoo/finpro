//
//  VocalRangeVoiceProfileView.swift
//  finpro
//
//  Screen asking the user to describe their voice (Female / Male).
//

import SwiftUI

struct VocalRangeVoiceProfileView: View {
    enum VoiceType: String, CaseIterable, Identifiable {
        case female = "Female"
        case male = "Male"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .female:
                "Typically has a higher speaking pitch, with a lighter or brighter vocal tone."
            case .male:
                "Typically has a lower speaking pitch, with a deeper or fuller vocal tone."
            }
        }
    }

    let onBack: () -> Void
    let onContinue: (VoiceType) -> Void

    @State private var selectedType: VoiceType?

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Leading inset of the text and cards, aligned with the other vocal range screens.
    private let contentLeadingInset: CGFloat = 52
    /// Trailing inset per the design, narrower so the subtitle lines and cards fit as drawn.
    private let contentTrailingInset: CGFloat = 40
    /// Gap between the top bar and the title per the design.
    private let titleTopSpacing: CGFloat = 68
    /// Gap between the subtitle and the first card per the design.
    private let cardsTopSpacing: CGFloat = 48
    private let cardCornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, cardsTopSpacing)

                    VStack(spacing: 16) {
                        ForEach(VoiceType.allCases) { type in
                            card(for: type)
                        }
                    }
                }
                .padding(.leading, contentLeadingInset)
                .padding(.trailing, contentTrailingInset)
                .padding(.top, titleTopSpacing)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let selectedType {
                Button("Continue") {
                    onContinue(selectedType)
                }
                .buttonStyle(.primaryDeep)
                .padding(.horizontal, buttonInset)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedType)
        .sensoryFeedback(.selection, trigger: selectedType)
        .background(Color.onboardingBackground.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            LiquidGlassGroup {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Back")
            }
            Spacer()
        }
        .padding(.horizontal, buttonInset)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How would you\ndescribe your\nvoice?")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.plumInk)
                .accessibilityAddTraits(.isHeader)

            Text("Choose the option that feels closest to your voice.\nThis helps us personalize your vocal test.")
                .font(.footnote)
                .foregroundStyle(Color.plumInkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(for type: VoiceType) -> some View {
        let isSelected = selectedType == type
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)

        return Button {
            selectedType = type
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(type.rawValue)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(type.description)
                    .font(.footnote)
                    .foregroundStyle(Color.plumInkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .background(shape.fill(isSelected ? Color.voiceCardSelected : Color(.secondarySystemGroupedBackground)))
            .overlay(shape.stroke(Color.voiceOptionBorder, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VocalRangeVoiceProfileView(onBack: {}, onContinue: { _ in })
}

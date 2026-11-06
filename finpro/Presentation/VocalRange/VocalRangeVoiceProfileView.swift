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

    var body: some View {
        VStack(spacing: 0) {
            topBar

            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(spacing: 16) {
                    ForEach(VoiceType.allCases) { type in
                        card(for: type)
                    }
                }
                .padding(.top, 8)

                Spacer()

                if selectedType != nil {
                    Button("Continue") {
                        if let selectedType {
                            onContinue(selectedType)
                        }
                    }
                    .buttonStyle(.primary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedType)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    private var topBar: some View {
        HStack {
            LiquidGlassGroup {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .liquidGlassCircle()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How would you\ndescribe your\nvoice?")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.brandPlum)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose the option that feels closest to your voice.\nThis helps us personalize your vocal test.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(for type: VoiceType) -> some View {
        let isSelected = selectedType == type

        return Button {
            selectedType = type
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(type.rawValue)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text(type.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.voiceCardSelected : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.brandPlum : Color.voiceCardBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VocalRangeVoiceProfileView(onBack: {}, onContinue: { _ in })
}

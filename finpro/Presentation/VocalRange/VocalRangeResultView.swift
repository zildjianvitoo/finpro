//
//  VocalRangeResultView.swift
//  finpro
//
//  Vocal range test result screen ("SOPRANO", comfort zone, song transposition).
//

import SwiftUI

struct VocalRangeResultView: View {
    let range: VocalRange
    let isFemale: Bool
    let onDone: () -> Void
    let onRetake: () -> Void

    /// Song key offset in semitones; 0 is the original key.
    @State private var selectedTransposition = -2

    private let transpositionOptions = [0, -2, -1, 1]

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Inset of the sections and the recommendation card per the design.
    private let contentInset: CGFloat = 44
    private let chipHeight: CGFloat = 38
    private let chipMinWidth: CGFloat = 62
    private let cornerRadius: CGFloat = 12

    @ScaledMetric(relativeTo: .largeTitle) private var voiceTypeSize: CGFloat = 56
    /// Line height of the voice type at full size, kept when a long name (e.g. MEZZO-SOPRANO)
    /// shrinks to fit, so the header height does not change between results.
    @ScaledMetric(relativeTo: .largeTitle) private var voiceTypeLineHeight: CGFloat = 67

    private var classification: (name: String, comfortLowMIDI: Float, comfortHighMIDI: Float) {
        VoiceClassification.classify(range: range, isFemale: isFemale)
    }

    private func noteName(_ midi: Float) -> String {
        PitchMath.noteName(midi: Int(midi.rounded()))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    comfortZoneSection
                    transpositionSection
                        .padding(.top, 46)
                }
                .padding(.horizontal, contentInset)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(Color.onboardingBackground.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your vocal range")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(alignment: .top, spacing: 6) {
                    Text(classification.name)
                        .font(.system(size: voiceTypeSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white)

                    Text("(\(noteName(range.lowestMIDI))-\(noteName(range.highestMIDI)))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 8)
                }
                .frame(minHeight: voiceTypeLineHeight)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(isFemale ? "Female voice" : "Male voice")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.plumNight)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, buttonInset)
        .padding(.top, 40)
        .padding(.bottom, 18)
        .background(Color.plumNight.ignoresSafeArea(edges: .top))
    }

    // MARK: - Comfort Zone

    private var comfortZoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your comfort zone")
                Spacer()
                Text("(\(noteName(classification.comfortLowMIDI))-\(noteName(classification.comfortHighMIDI)))")
            }
            .font(.headline)
            .foregroundStyle(Color.plumInk)
            .accessibilityElement(children: .combine)

            ComfortZoneBar(
                lowestMIDI: range.lowestMIDI,
                highestMIDI: range.highestMIDI,
                comfortLowMIDI: classification.comfortLowMIDI,
                comfortHighMIDI: classification.comfortHighMIDI
            )
            .padding(.top, 34)
        }
    }

    // MARK: - Transposition

    private var transpositionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Song transposition")
                .font(.headline)
                .foregroundStyle(Color.plumInk)

            Text("We’ll use song keys that feel comfortable")
                .font(.caption)
                .foregroundStyle(Color.plumInkSecondary)

            HStack(spacing: 10) {
                ForEach(transpositionOptions, id: \.self) { option in
                    chip(for: option)
                }
            }
            .padding(.top, 8)
        }
    }

    private func chip(for option: Int) -> some View {
        let isSelected = selectedTransposition == option
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return Button {
            selectedTransposition = option
        } label: {
            Text(label(for: option))
                .font(.subheadline)
                .foregroundStyle(Color.plumInk)
                .padding(.horizontal, 8)
                .frame(minWidth: chipMinWidth, maxWidth: option == 0 ? .infinity : nil)
                .frame(minHeight: chipHeight)
                .background(shape.fill(isSelected ? Color.voiceCardSelected : Color.clear))
                .overlay(shape.strokeBorder(Color.chipBorder, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option == 0 ? "Original key" : "\(label(for: option)) semitones")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func label(for option: Int) -> String {
        option == 0 ? "Original" : option > 0 ? "+\(option)" : "\(option)"
    }

    // MARK: - Recommendation

    private var recommendationMessage: String {
        let steps = abs(selectedTransposition)
        let unit = steps == 1 ? "semitone" : "semitones"
        return switch selectedTransposition {
        case 0: "We’ll keep the backing track and pitch guide in the original key."
        case ..<0: "We’ll lower the backing track and pitch guide by \(steps) \(unit)."
        default: "We’ll raise the backing track and pitch guide by \(steps) \(unit)."
        }
    }

    private var recommendationCard: some View {
        HStack(spacing: 20) {
            Image(systemName: "seal")
                .font(.title3)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Great match for \(selectedTransposition == 0 ? "Original" : label(for: selectedTransposition).replacingOccurrences(of: "-", with: "−"))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.plumInk)

                Text(recommendationMessage)
                    .font(.caption)
                    .foregroundStyle(Color.plumInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.surfaceElevated)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            recommendationCard
                .padding(.horizontal, contentInset)
                .padding(.bottom, 32)

            Button("Done", action: onDone)
                .buttonStyle(.primaryDeep)
                .padding(.horizontal, buttonInset)

            Button(action: onRetake) {
                Text("Retake")
                    .font(.caption)
                    .underline()
                    .foregroundStyle(Color.plumInkSecondary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }
}

#Preview {
    VocalRangeResultView(
        range: VocalRange(lowestMIDI: 45, highestMIDI: 76),
        isFemale: true,
        onDone: {},
        onRetake: {}
    )
}

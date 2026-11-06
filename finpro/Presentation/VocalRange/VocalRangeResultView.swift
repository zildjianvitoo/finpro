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

    @State private var selectedTransposition: String = "-2"

    private let transpositionOptions = ["Original", "-2", "-1", "+1"]

    private var lowName: String {
        PitchMath.noteName(midi: Int(range.lowestMIDI.rounded()))
    }

    private var highName: String {
        PitchMath.noteName(midi: Int(range.highestMIDI.rounded()))
    }

    private var classification: (name: String, comfortLowMIDI: Float, comfortHighMIDI: Float) {
        VoiceClassification.classify(range: range, isFemale: isFemale)
    }

    private var comfortLowName: String {
        PitchMath.noteName(midi: Int(classification.comfortLowMIDI.rounded()))
    }

    private var comfortHighName: String {
        PitchMath.noteName(midi: Int(classification.comfortHighMIDI.rounded()))
    }

    private var midName: String {
        let mid = (range.lowestMIDI + range.highestMIDI) / 2
        return PitchMath.noteName(midi: Int(mid.rounded()))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBanner

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    comfortZoneSection
                    transpositionSection
                    recommendationCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            footer
        }
        .background(Color(red: 0.22, green: 0.08, blue: 0.20))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Top Banner

    private var topBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your vocal range")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.7))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(classification.name)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("(\(lowName)-\(highName))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            Text(isFemale ? "Female voice" : "Male voice")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Comfort Zone Section

    private var comfortZoneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your comfort zone")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text("(\(comfortLowName)-\(comfortHighName))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            comfortBar

            HStack {
                Text(lowName)
                Spacer()
                Text(comfortLowName)
                Spacer()
                Text(midName)
                Spacer()
                Text(comfortHighName)
                Spacer()
                Text(highName)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var comfortBar: some View {
        ZStack {
            // Base track with multi-tone gradient
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.45, blue: 0.20),
                            Color(red: 0.95, green: 0.80, blue: 0.30),
                            Color.micIconHighlight,
                            Color(red: 0.95, green: 0.80, blue: 0.30),
                            Color(red: 0.85, green: 0.45, blue: 0.20)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 12)

            // Markers for comfort zone
            HStack {
                Spacer().frame(width: 40)
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 2, height: 18)
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 2, height: 18)
                Spacer().frame(width: 40)
            }
        }
    }

    // MARK: - Transposition Section

    private var transpositionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song transposition")
                .font(.headline.bold())
                .foregroundStyle(.primary)

            Text("We'll use this song keys that feel comfortable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            HStack(spacing: 10) {
                ForEach(transpositionOptions, id: \.self) { option in
                    let isSelected = selectedTransposition == option
                    Button {
                        selectedTransposition = option
                    } label: {
                        Text(option)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.voiceCardSelected : Color(.systemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.brandPlum : Color.voiceCardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Recommendation Card

    private var recommendationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("Great match for \(selectedTransposition)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text("We'll lower the backing track and pitch guide by 2 semitones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Done", action: onDone)
                .buttonStyle(.primary)

            Button("Retake", action: onRetake)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 36)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 36)
        .background(Color(.systemBackground))
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

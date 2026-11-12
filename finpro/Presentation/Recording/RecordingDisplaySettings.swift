//
//  RecordingDisplaySettings.swift
//  finpro
//
//  What the recording screen shows on top of the camera (lyrics, pitch guide) and how opaque
//  their panels are. Kept in UserDefaults as a per-user preference; only the on-screen
//  guides change, never the recorded video.
//

import SwiftUI

enum RecordingDisplaySettings {
    static let showsLyricsKey = "recording.showsLyrics"
    static let lyricsOpacityKey = "recording.lyricsOpacity"
    static let showsPitchGuideKey = "recording.showsPitchGuide"
    static let pitchGuideOpacityKey = "recording.pitchGuideOpacity"
    /// Where the lyrics sit: true = inside the pitch guide (Concept 2), false = a card near the camera (Concept 1).
    static let lyricsInGuideKey = "recording.lyricsInGuide"
    /// Text size of the lyrics card, an index into `lyricsTextStyles`.
    static let lyricsTextStepKey = "recording.lyricsTextStep"

    /// Size of the notes, lines and voice dot of the pitch guide, 0...1 (the Pitch Guide slider).
    static let pitchGuideScaleKey = "recording.pitchGuideScale"

    static let defaultLyricsInGuide = true
    /// The middle of the slider is the design's default look; the right end is "Pitch Max".
    static let defaultPitchGuideScale = 0.5
    static let defaultLyricsTextStep = 0
    static let lyricsTextStyles: [Font] = [.appSubheadline, .appBody, .appTitle3]

    /// Lines (natural notes) the pitch guide shows, as in the design.
    static let guideRows: CGFloat = 6
    /// Two lines of lyrics under the notes (Concept 2).
    static let guideLyricsHeight: CGFloat = 44

    static func lyricsTextStyle(step: Int) -> Font {
        lyricsTextStyles[min(max(step, 0), lyricsTextStyles.count - 1)]
    }

    static func nextLyricsTextStep(after step: Int) -> Int {
        (step + 1) % lyricsTextStyles.count
    }

    static let defaultLyricsOpacity = 0.7
    static let defaultPitchGuideOpacity = 0.5
    /// Below this the panels are hard to read over the camera.
    static let minimumOpacity = 0.1
    static let opacityStep = 0.1
}

/// The settings card from "Get Ready to Record", also shown from the recording screen.
struct RecordingDisplaySettingsCard: View {
    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.lyricsOpacityKey) private var lyricsOpacity = RecordingDisplaySettings.defaultLyricsOpacity
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.pitchGuideOpacityKey) private var pitchGuideOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toggleRow("Lyrics", subtitle: "Show lyrics while recording", isOn: $showsLyrics)
            opacityRow("Lyrics Opacity", subtitle: "Teleprompter near the camera", value: $lyricsOpacity)
                .disabled(!showsLyrics)
            toggleRow("Pitch Guide", subtitle: "Show pitch guidance while recording", isOn: $showsPitchGuide)
            opacityRow("Pitch Guide Opacity", subtitle: "Pitch reference and your voice", value: $pitchGuideOpacity)
                .disabled(!showsPitchGuide)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.chipBorder.opacity(0.3), lineWidth: 1)
        )
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            labels(title, subtitle: subtitle)
        }
        .tint(Color.plumNight)
    }

    private func opacityRow(_ title: String, subtitle: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                labels(title, subtitle: subtitle)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(Color.plumInk)
                    .monospacedDigit()
            }
            Slider(value: value, in: RecordingDisplaySettings.minimumOpacity...1, step: RecordingDisplaySettings.opacityStep) {
                Text(title)
            }
            .tint(Color.tileMauve)
        }
    }

    private func labels(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.plumInk)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color.plumInkSecondary)
        }
    }
}

#Preview {
    RecordingDisplaySettingsCard()
        .padding()
        .background(Color.onboardingBackground)
}

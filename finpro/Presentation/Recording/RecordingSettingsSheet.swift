//
//  RecordingSettingsSheet.swift
//  finpro
//
//  Bottom sheet opened from the recording screen's settings button: Original Vocal, Lyrics, a
//  Pitch Guide opacity slider and, at the bottom, where the lyrics sit (Concept 1 card near the
//  camera, or Concept 2 inside the pitch guide). Values are the per-user preferences in
//  RecordingDisplaySettings.
//

import SwiftUI

struct RecordingSettingsSheet: View {
    let viewModel: RecordingViewModel

    /// The sheet is as tall as its content.
    @State private var contentHeight: CGFloat = 400

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.lyricsInGuideKey) private var lyricsInGuide = RecordingDisplaySettings.defaultLyricsInGuide
    @AppStorage(RecordingDisplaySettings.pitchGuideOpacityKey) private var pitchGuideOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity

    private let horizontalInset: CGFloat = 24
    private let rowHeight: CGFloat = 50
    private let rowSpacing: CGFloat = 12
    private let cardCornerRadius: CGFloat = 30
    private let unavailableOpacity = 0.5
    /// Rows are dark glass over the light sheet.
    private let rowFill = Color.black.opacity(0.41)

    var body: some View {
        VStack(spacing: rowSpacing) {
            Text("Settings")
                .font(.appHeadline)
                .foregroundStyle(Color.black)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            // Songs without a separated vocal cannot switch it, so the row stays but is dimmed.
            switchRow("Original Vocal", isOn: Binding(
                get: { viewModel.referenceVocalEnabled && viewModel.supportsReferenceVocal },
                set: { viewModel.setReferenceVocalEnabled($0) }))
                .opacity(viewModel.supportsReferenceVocal ? 1 : unavailableOpacity)
                .disabled(!viewModel.supportsReferenceVocal)
            switchRow("Lyrics", isOn: $showsLyrics)
            pitchGuideCard
            switchRow("Lyrics in Pitch Guide", isOn: $lyricsInGuide)
                .opacity(showsLyrics ? 1 : unavailableOpacity)
                .disabled(!showsLyrics)
            extras
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.appBody)
                .foregroundStyle(.white)
            Spacer()
            AppSwitch(isOn: isOn)
        }
        .padding(.leading, 19)
        .padding(.trailing, 8)
        .frame(height: rowHeight)
        .background(Capsule().fill(rowFill))
        .accessibilityElement(children: .combine)
    }

    private var pitchGuideCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pitch Guide")
                .font(.appBody)
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $pitchGuideOpacity, in: RecordingDisplaySettings.minimumOpacity...1) {
                    Text("Pitch Guide opacity")
                }
                .tint(.blue)
                Image(systemName: "textformat.size.larger")
            }
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous).fill(rowFill))
    }

    /// Information that is not in the design but still matters when it applies.
    @ViewBuilder
    private var extras: some View {
        if viewModel.microphoneName != nil || viewModel.isSpeakerTest {
            VStack(alignment: .leading, spacing: 6) {
                if let microphone = viewModel.microphoneName {
                    Label("Microphone: \(microphone)", systemImage: "headphones")
                        .font(.appFootnote)
                        .foregroundStyle(Color.secondaryText)
                }
                if viewModel.isSpeakerTest {
                    Label("Speaker test mode: scores are not reliable", systemImage: "speaker.wave.3")
                        .font(.appFootnote)
                        .foregroundStyle(Color.primaryBrand)
                }
                #if DEBUG
                pitchDebug
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    /// Debug builds: is the microphone heard, and how often? 20 samples/s is the target (50 ms hop).
    private var pitchDebug: some View {
        let stats = viewModel.pitchStats
        let level = stats.lastLevelDB.isFinite ? "\(Int(stats.lastLevelDB)) dB" : "silent"
        return Text("Mic \(stats.lastNote ?? "—") · \(stats.samplesPerSecond)/s · voiced \(stats.voicedPercent)% · \(level)")
            .font(.appCaption.monospacedDigit())
            .foregroundStyle(Color.secondaryText)
    }
}

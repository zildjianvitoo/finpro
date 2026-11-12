//
//  RecordingSettingsSheet.swift
//  finpro
//
//  Bottom sheet opened from the recording screen's settings button: "Recording Settings" with
//  Lyrics and Pitch Guide, each opening an on/off choice and, when on, an opacity slider.
//  Values are the per-user preferences in RecordingDisplaySettings.
//

import SwiftUI

struct RecordingSettingsSheet: View {
    let viewModel: RecordingViewModel
    /// The full pitch guide layout always shows the guide, so only lyrics are offered there.
    var offersPitchGuide = true

    private enum Page {
        case main, lyrics, pitchGuide
    }

    @State private var page = Page.main
    /// The sheet is as tall as its content, which differs per page.
    @State private var contentHeight: CGFloat = 200

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.lyricsOpacityKey) private var lyricsOpacity = RecordingDisplaySettings.defaultLyricsOpacity
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.pitchGuideOpacityKey) private var pitchGuideOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity

    private let horizontalInset: CGFloat = 24
    private let choiceSize: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .main:
                main
            case .lyrics:
                detail(title: "Lyrics", isOn: $showsLyrics, opacity: $lyricsOpacity,
                       opacityTitle: "Lyrics Opacity", opacitySubtitle: "Teleprompter near the camera")
            case .pitchGuide:
                detail(title: "Pitch Guide", isOn: $showsPitchGuide, opacity: $pitchGuideOpacity,
                       opacityTitle: "Pitch Guide Opacity", opacitySubtitle: "Pitch reference and your voice")
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: page)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .foregroundStyle(Color.plumInk)
    }

    // MARK: - Main

    private var main: some View {
        VStack(spacing: 20) {
            Text("Recording Settings")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer()
                entry("Lyrics", systemImage: "music.note.list") { page = .lyrics }
                Spacer()
                if offersPitchGuide {
                    Spacer()
                    entry("Pitch Guide", systemImage: "music.quarternote.3") { page = .pitchGuide }
                    Spacer()
                }
            }

            extras
        }
    }

    private func entry(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.plumNight)
                    .frame(width: choiceSize, height: choiceSize)
                    .background(Circle().fill(.white.opacity(0.85)))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// Controls that are not in the design but still matter when they apply.
    @ViewBuilder
    private var extras: some View {
        if viewModel.supportsReferenceVocal || viewModel.microphoneName != nil || viewModel.isSpeakerTest {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.supportsReferenceVocal {
                    Toggle("Reference vocal", isOn: Binding(
                        get: { viewModel.referenceVocalEnabled },
                        set: { viewModel.setReferenceVocalEnabled($0) }))
                        .font(.subheadline.weight(.semibold))
                        .tint(Color.plumNight)
                        .accessibilityHint("Switch between reference mix and instrumental without stopping recording")
                }
                if let microphone = viewModel.microphoneName {
                    Label("Microphone: \(microphone)", systemImage: "headphones")
                        .font(.footnote)
                        .foregroundStyle(Color.plumInkSecondary)
                }
                if viewModel.isSpeakerTest {
                    Label("Speaker test mode: scores are not reliable", systemImage: "speaker.wave.3")
                        .font(.footnote)
                        .foregroundStyle(.purple)
                }
                #if DEBUG
                pitchDebug
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Debug builds: is the microphone heard, and how often? 20 samples/s is the target (50 ms hop).
    private var pitchDebug: some View {
        let stats = viewModel.pitchStats
        let level = stats.lastLevelDB.isFinite ? "\(Int(stats.lastLevelDB)) dB" : "silent"
        return Text("Mic \(stats.lastNote ?? "—") · \(stats.samplesPerSecond)/s · voiced \(stats.voicedPercent)% · \(level)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.plumInkSecondary)
    }

    // MARK: - Detail

    private func detail(title: String, isOn: Binding<Bool>, opacity: Binding<Double>,
                        opacityTitle: String, opacitySubtitle: String) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    LiquidGlassGroup {
                        Button {
                            page = .main
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.plumInk)
                        }
                        .glassCircleButtonStyle()
                        .accessibilityLabel("Back to settings")
                    }
                    Spacer()
                }
            }
            .frame(minHeight: 44)

            Text(isOn.wrappedValue ? "ON" : "OFF")
                .font(.title3.weight(.semibold))
                .padding(.top, 6)
                .accessibilityHidden(true)

            HStack {
                Spacer()
                choice(isOn: isOn, value: true, systemImage: "music.note", label: "Show \(title)")
                Spacer()
                Spacer()
                choice(isOn: isOn, value: false, systemImage: "music.note", label: "Hide \(title)")
                Spacer()
            }
            .padding(.top, 14)

            if isOn.wrappedValue {
                opacityRow(opacityTitle, subtitle: opacitySubtitle, value: opacity)
                    .padding(.top, 24)
            }
        }
    }

    /// One of the two round choices; the chosen one is dark. The "off" one shows the note struck through.
    private func choice(isOn: Binding<Bool>, value: Bool, systemImage: String, label: String) -> some View {
        let isSelected = isOn.wrappedValue == value
        return Button {
            isOn.wrappedValue = value
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .overlay {
                    if !value {
                        Capsule()
                            .frame(width: 2, height: 26)
                            .rotationEffect(.degrees(45))
                    }
                }
                .foregroundStyle(isSelected ? Color.white : Color.plumNight)
                .frame(width: choiceSize, height: choiceSize)
                .background(Circle().fill(isSelected ? Color.plumNight : .white.opacity(0.85)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func opacityRow(_ title: String, subtitle: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.plumInkSecondary)
                }
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
            }
            Slider(value: value, in: RecordingDisplaySettings.minimumOpacity...1,
                   step: RecordingDisplaySettings.opacityStep) {
                Text(title)
            }
            .tint(Color.tileMauve)
        }
    }
}

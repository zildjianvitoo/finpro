//
//  ReadyView.swift
//  finpro
//
//  "Get Ready to Record" (PRD §5.2 step 3): choose what the recording screen shows (lyrics,
//  pitch guide and their opacity), see a preview of both, and start once earphones are in.
//

import SwiftUI

struct ReadyView: View {
    let song: PreparedSong
    /// Lyrics of the chosen part, for the preview line (empty when none were found).
    var lyrics: [LyricLine] = []
    let routeMonitor: any AudioRouteMonitor
    /// Debug speaker test (DebugOptions) lets Record through without earphones.
    var allowsSpeaker = false
    let onRecord: () -> Void
    let onChooseAnother: () -> Void
    var onChangeKey: (() -> Void)? = nil

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.lyricsOpacityKey) private var lyricsOpacity = RecordingDisplaySettings.defaultLyricsOpacity
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.pitchGuideOpacityKey) private var pitchGuideOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity
    @State private var route: AudioOutputRoute?

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Inset of the title and cards per the design.
    private let contentInset: CGFloat = 28
    private let topBarHeight: CGFloat = 48
    private let previewPillHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LiquidGlassGroup {
                    Button(action: onChangeKey ?? onChooseAnother) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    .glassCircleButtonStyle()
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
            .frame(minHeight: topBarHeight)
            .padding(.horizontal, buttonInset)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get Ready to Record")
                            .font(.title2.bold())
                            .foregroundStyle(Color.plumInk)
                            .accessibilityAddTraits(.isHeader)
                        Text("Set up your recording and choose what appears on screen.")
                            .font(.footnote)
                            .foregroundStyle(Color.plumInkSecondary)
                    }
                    .padding(.top, 12)

                    RecordingDisplaySettingsCard()
                        .padding(.top, 16)

                    previewCard
                        .padding(.top, 12)
                }
                .padding(.horizontal, contentInset)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 8) {
                if !canRecord {
                    Label("Plug in earphones to record.", systemImage: "headphones")
                        .font(.footnote)
                        .foregroundStyle(Color.plumInk)
                }
                Button("Start Recording", action: onRecord)
                    .buttonStyle(.primaryDeep)
                    .disabled(!canRecord)
            }
            .padding(.horizontal, buttonInset)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(Color.onboardingBackground.ignoresSafeArea())
        .task {
            route = routeMonitor.currentRoute
            for await change in routeMonitor.routeChanges() { route = change }
        }
    }

    /// PRD §5.2 step 3: Record is disabled on the built-in speaker/receiver.
    private var canRecord: Bool {
        allowsSpeaker || (route ?? routeMonitor.currentRoute).allowsRecording
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camera Preview")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.plumInk)

            if showsLyrics {
                previewLabel("Lyrics Preview")
                Text(previewLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.plumInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: previewPillHeight)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color.surfaceLavender.opacity(lyricsOpacity)))
            }

            if showsPitchGuide {
                previewLabel("Pitch Guide Preview")
                Image(systemName: "waveform")
                    .font(.footnote)
                    .foregroundStyle(Color.plumInk)
                    .frame(maxWidth: .infinity, minHeight: previewPillHeight)
                    .background(Capsule().fill(Color.surfaceLavender.opacity(pitchGuideOpacity)))
                    .accessibilityLabel("Pitch guide")
            }

            if !showsLyrics && !showsPitchGuide {
                Text("Only the camera will be on screen.")
                    .font(.caption2)
                    .foregroundStyle(Color.plumInkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.chipBorder.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: showsLyrics)
        .animation(.easeInOut(duration: 0.2), value: showsPitchGuide)
    }

    private func previewLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.plumInkSecondary)
    }

    /// The first line of the chosen part, or a placeholder when the song has no lyrics.
    private var previewLine: String {
        lyrics.first?.text ?? "Your lyrics will appear here"
    }
}

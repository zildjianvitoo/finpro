//
//  RecordingView.swift
//  finpro
//
//  Recording screen (PRD §5.5): the front camera in its 9:16 frame, a tips card before recording
//  starts, then the timer, the lyrics (a card near the camera, or inside the pitch guide), the
//  pitch guide and the controls: settings, record (start / pause / resume), delete and done.
//

import SwiftUI
import UIKit

struct RecordingView: View {
    @State private var viewModel: RecordingViewModel
    @State private var confirmsEnd = false
    @State private var confirmsDiscard = false
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.lyricsInGuideKey) private var lyricsInGuide = RecordingDisplaySettings.defaultLyricsInGuide
    @AppStorage(RecordingDisplaySettings.pitchGuideOpacityKey) private var pitchGuideOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity
    @AppStorage(RecordingDisplaySettings.lyricsTextStepKey) private var lyricsTextStep = RecordingDisplaySettings.defaultLyricsTextStep

    /// Measurements of the design (iPhone 17 Pro, 402 × 874 pt).
    private let backButtonSize: CGFloat = 44
    private let topBarInset: CGFloat = 1
    private let lyricsCardGap: CGFloat = 8
    private let lyricsCardInset: CGFloat = 33
    private let pitchGuideMaxWidth: CGFloat = 316
    private let guideControlsGap: CGFloat = 22
    private let recordButtonSize: CGFloat = 68
    private let recordDotSize: CGFloat = 48
    private let controlsBottomInset: CGFloat = 9
    private let settingsButtonSize: CGFloat = 50
    private let deleteGlyphSize: CGFloat = 28
    private let doneGlyphSize: CGFloat = 36
    private let pauseGlyphSize: CGFloat = 20
    /// Horizontal centres of the controls as a share of the width (85, 201, 284 and 355 of 402).
    private let settingsX = 0.211
    private let recordX = 0.5
    private let deleteX = 0.708
    private let doneX = 0.883
    private let timerRefresh: TimeInterval = 0.25
    private let timerCornerRadius: CGFloat = 10
    private let timerHeight: CGFloat = 26
    private let disabledOpacity = 0.4
    /// Countdown: the screen dims, the number sits in a white circle (design).
    private let countdownDimOpacity = 0.4
    private let countdownCircleSize: CGFloat = 150
    /// How far the retry hint sits above the centre of the pitch guide.
    private let retryHintLift: CGFloat = 36

    init(viewModel: RecordingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        // The outer reader respects the safe area, so it reports the insets; the content then
        // lays out on the full screen.
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let layout = VideoLayout(size: CGSize(width: outer.size.width + insets.leading + insets.trailing,
                                                  height: outer.size.height + insets.top + insets.bottom),
                                     top: insets.top)
            ZStack(alignment: .top) {
                Color.black
                cameraLayer(layout)
                content(layout)
                countdownLayer(layout)
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .ignoresSafeArea()
            // The design is light only; tokens resolve light even when the phone is in dark mode.
            .environment(\.colorScheme, .light)
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // PRD §5.8: leaving the app stops the session; ask for time to finalize the file.
            let task = UIApplication.shared.beginBackgroundTask(withName: "Finalize recording")
            Task {
                await viewModel.interrupt()
                UIApplication.shared.endBackgroundTask(task)
            }
        }
        .confirmationDialog("End session?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            if viewModel.passedCount > 0 {
                Button("Export \(viewModel.passedCount) of \(viewModel.segmentCount)") {
                    Task { await viewModel.finish() }
                }
            }
            Button("Discard", role: .destructive) {
                Task { await viewModel.discard() }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text(viewModel.passedCount > 0
                 ? "Your cover will use the \(viewModel.passedCount) segments you passed."
                 : "No segment has passed yet.")
        }
        .confirmationDialog("Discard this recording?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                Task { await viewModel.discard() }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("Nothing from this session will be kept.")
        }
        .sheet(isPresented: $showsSettings) { RecordingSettingsSheet(viewModel: viewModel) }
    }

    // MARK: - Layout

    /// The camera shows in a 9:16 frame under the status bar, the part that ends up in the video;
    /// the rest of the screen is black.
    private struct VideoLayout {
        let size: CGSize
        let top: CGFloat

        var videoHeight: CGFloat { min(size.width * 16 / 9, size.height - top) }
        /// Black space below the camera frame.
        var bottomInset: CGFloat { max(0, size.height - top - videoHeight) }
    }

    private var lyricsAvailable: Bool { showsLyrics && !viewModel.lyrics.isEmpty }
    /// Concept 2: the lyrics sit inside the pitch guide, which then needs the guide to be shown.
    private var lyricsInPanel: Bool { lyricsAvailable && lyricsInGuide && showsPitchGuide }
    /// Concept 1: a card near the camera (also when there is no pitch guide to hold them).
    private var lyricsAsCard: Bool { lyricsAvailable && !lyricsInPanel }

    private var guideHeight: CGFloat {
        PianoRollView.height(rows: RecordingDisplaySettings.guideRows,
                             lyricsHeight: lyricsInPanel ? RecordingDisplaySettings.guideLyricsHeight : 0)
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraSurface: some View {
        if let source = viewModel.previewSource, viewModel.isCameraReady {
            CameraPreviewView(session: source.previewSession, device: source.previewDevice)
        } else if viewModel.isCameraReady, viewModel.status != .ready {
            // Simulator / fakes: there is no camera, the loop still runs.
            Color.black.overlay {
                Image(systemName: "video.slash")
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func cameraLayer(_ layout: VideoLayout) -> some View {
        cameraSurface
            .frame(width: layout.size.width, height: layout.videoHeight)
            .clipped()
            .padding(.top, layout.top)
    }

    @ViewBuilder
    private func content(_ layout: VideoLayout) -> some View {
        switch viewModel.status {
        case .starting where !viewModel.isCameraReady:
            ProgressView("Getting ready…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxHeight: .infinity)
        case .ready, .starting, .recording:
            sessionOverlay(layout)
        case .finishing:
            ProgressView("Saving your recording…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxHeight: .infinity)
        case .blocked(let error):
            stoppedState(error, primary: ("Try Again", { Task { await viewModel.start() } }))
                .frame(maxHeight: .infinity)
        case .interrupted(let error), .failed(let error):
            stoppedState(error, primary: viewModel.passedCount > 0
                         ? ("Export \(viewModel.passedCount) of \(viewModel.segmentCount)", { viewModel.exportAfterInterruption() })
                         : nil)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Before and while recording

    /// Top bar, lyrics, pitch guide and controls over the camera frame; the tips card sits on top
    /// of them until it is dismissed by starting the recording.
    private func sessionOverlay(_ layout: VideoLayout) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, topBarInset)

            if lyricsAsCard {
                RecordingLyricsView(lines: viewModel.lyrics,
                                    songTime: viewModel.displaySongTime,
                                    textStep: lyricsTextStep,
                                    onChangeTextSize: { lyricsTextStep = RecordingDisplaySettings.nextLyricsTextStep(after: lyricsTextStep) },
                                    onHide: { withAnimation(.snappy) { showsLyrics = false } })
                    .padding(.horizontal, lyricsCardInset)
                    .padding(.top, lyricsCardGap)
                    .transition(.opacity)
            }

            Spacer()
            phaseInfo
            Spacer()

            bluetoothWarning

            if showsPitchGuide {
                pitchGuide
                    .frame(maxWidth: pitchGuideMaxWidth)
                    .frame(height: guideHeight)
                    .padding(.bottom, guideControlsGap)
            }

            controls(width: layout.size.width)
                .padding(.bottom, controlsBottomInset)
        }
        .padding(.top, layout.top)
        .frame(width: layout.size.width, height: layout.top + layout.videoHeight, alignment: .top)
        .overlay {
            if viewModel.status == .ready {
                tipsCard
            }
        }
        .animation(.snappy, value: lyricsInGuide)
        .animation(.snappy, value: showsLyrics)
    }

    private var pitchGuide: some View {
        PianoRollView(notes: pianoRollNotes,
                      trail: viewModel.trail,
                      focusMIDI: focusMIDI,
                      songTime: viewModel.displaySongTime,
                      dimmedBefore: viewModel.loop.phase == .preRoll ? viewModel.loop.currentSegment?.audioStartTime : nil,
                      isPaused: confirmsEnd || confirmsDiscard || showsSettings,
                      wordLabels: wordLabels,
                      lyricsHeight: lyricsInPanel ? RecordingDisplaySettings.guideLyricsHeight : 0,
                      backgroundOpacity: pitchGuideOpacity)
            .overlay(alignment: .bottom) {
                if lyricsInPanel {
                    RecordingGuideLyricsView(lines: viewModel.lyrics, songTime: viewModel.displaySongTime)
                        .frame(height: RecordingDisplaySettings.guideLyricsHeight)
                        .padding(.bottom, PianoRollView.bottomInset / 2)
                }
            }
    }

    @ViewBuilder
    private var bluetoothWarning: some View {
        if viewModel.showsBluetoothWarning {
            Label("Wired earphones give the best sync", systemImage: "airpodspro")
                .font(.appCaption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.85), in: .capsule)
                .padding(.bottom, 8)
        }
    }

    private var topBar: some View {
        ZStack {
            timer
            HStack {
                LiquidGlassGroup {
                    Button {
                        if viewModel.status == .ready {
                            Task { await viewModel.discard() }
                        } else {
                            confirmsEnd = true
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.black.opacity(0.9))
                    }
                    .glassCircleButtonStyle()
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
        }
        .frame(minHeight: backButtonSize)
        .padding(.horizontal, 16)
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: timerRefresh)) { _ in
            Text(Duration.seconds(viewModel.elapsedRecordingTime())
                .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                .font(.appBody.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: timerHeight)
                .background(RoundedRectangle(cornerRadius: timerCornerRadius, style: .continuous).fill(Color.timerRed))
                .overlay(RoundedRectangle(cornerRadius: timerCornerRadius, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
                .accessibilityLabel("Recording time")
        }
    }

    // MARK: - Controls

    /// Settings, record (start / pause / resume), delete and done, at the places of the design.
    private func controls(width: CGFloat) -> some View {
        ZStack {
            settingsButton.position(x: width * settingsX, y: recordButtonSize / 2)
            recordButton.position(x: width * recordX, y: recordButtonSize / 2)
            deleteButton.position(x: width * deleteX, y: recordButtonSize / 2)
            doneButton.position(x: width * doneX, y: recordButtonSize / 2)
        }
        .frame(width: width, height: recordButtonSize)
    }

    private var settingsButton: some View {
        Button {
            showsSettings = true
        } label: {
            Image(systemName: "switch.2")
        }
        .buttonStyle(.appIcon(.tinted, size: settingsButtonSize))
        .accessibilityLabel("Recording settings")
    }

    /// Red record button: starts the recording, pauses it, and resumes it while paused (the
    /// current segment restarts after a countdown).
    private var recordButton: some View {
        Button {
            switch viewModel.status {
            case .ready: Task { await viewModel.beginRecording() }
            default: if viewModel.isPaused { viewModel.resume() } else { viewModel.pause() }
            }
        } label: {
            ZStack {
                Circle().fill(.black.opacity(0.45))
                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                Circle().fill(Color.recordRed).frame(width: recordDotSize, height: recordDotSize)
                if viewModel.status == .recording, !viewModel.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: pauseGlyphSize))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: recordButtonSize, height: recordButtonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canUseRecordButton)
        .opacity(canUseRecordButton ? 1 : disabledOpacity)
        .accessibilityLabel(recordButtonLabel)
    }

    private var canUseRecordButton: Bool {
        switch viewModel.status {
        case .ready: true
        case .recording: viewModel.canPause
        default: false
        }
    }

    private var recordButtonLabel: String {
        switch viewModel.status {
        case .ready: "Start recording"
        default: viewModel.isPaused ? "Resume recording" : "Pause recording"
        }
    }

    private var deleteButton: some View {
        Button {
            if viewModel.status == .ready {
                Task { await viewModel.discard() }
            } else {
                confirmsDiscard = true
            }
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: deleteGlyphSize))
                .foregroundStyle(Color.screenBackground)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discard recording")
    }

    /// Done: exports what passed. With nothing passed yet it asks what to do instead.
    private var doneButton: some View {
        Button {
            if viewModel.passedCount > 0 {
                Task { await viewModel.finish() }
            } else {
                confirmsEnd = true
            }
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: doneGlyphSize))
                .foregroundStyle(Color.secBrand)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.status != .recording)
        .opacity(viewModel.status == .recording ? 1 : disabledOpacity)
        .accessibilityLabel("Finish recording")
    }

    // MARK: - Tips

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "headphones")
                .font(.body)
                .foregroundStyle(Color.primary800)
                .environment(\.colorScheme, .light)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text("Quick Recording Tips")
                .font(.appSubheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Wear headphones, keep your camera steady, and find a quiet place for the best recording.")
                .font(.appFootnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await viewModel.beginRecording() }
            } label: {
                Text("Got It, Let’s Record")
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Color.primary800))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial.opacity(0.9), in: .rect(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Countdown

    /// The countdown after a failed attempt (the missed notes stay on the pitch guide).
    private var isRetryCountdown: Bool {
        if case .countdown = viewModel.loop.phase { viewModel.lastResult?.passed == false } else { false }
    }

    /// Dims the screen and shows the number in a white circle; after a failed attempt a hint says
    /// the phrase is sung again. Touches pass through so the controls stay reachable.
    @ViewBuilder
    private func countdownLayer(_ layout: VideoLayout) -> some View {
        if case .countdown(let remaining) = viewModel.loop.phase {
            ZStack {
                Color.black.opacity(countdownDimOpacity)

                Text("\(remaining)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color.primary800)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: remaining)
                    .frame(width: countdownCircleSize, height: countdownCircleSize)
                    .background(Circle().fill(.white))
                    .accessibilityLabel("Starting in \(remaining)")

                if isRetryCountdown {
                    retryHint
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, layout.bottomInset + controlsBottomInset + recordButtonSize + guideControlsGap
                                 + guideHeight / 2 - retryHintLift)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var retryHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.appTitle3.weight(.medium))
                .accessibilityHidden(true)
            Text("Sing this phrase again")
                .font(.appSubheadline.weight(.medium))
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .frame(width: 240, height: 72)
        .background(.white.opacity(0.55), in: .rect(cornerRadius: AppRadius.medium))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var phaseInfo: some View {
        switch viewModel.loop.phase {
        case .preRoll:
            Label("Listen…", systemImage: "ear")
                .font(.appTitle3.bold())
                .foregroundStyle(.white)
        case .singing:
            if let result = viewModel.lastResult, result.passed {
                Label("Segment \(result.segmentIndex + 1) passed", systemImage: "checkmark.circle.fill")
                    .font(.appSubheadline.bold())
                    .foregroundStyle(Color.pitchHit)
            }
        case .idle, .ended, .countdown, .showingResult, .paused:
            // The missed notes on the pitch guide are the result, the countdown has its own layer,
            // and the paused state is shown by the record button.
            EmptyView()
        }
    }

    private func stoppedState(_ error: UserFacingError, primary: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            ErrorStateView(error: error, actionTitle: primary?.0, action: primary?.1)
            Button("Start Over", role: .destructive) {
                Task { await viewModel.discard() }
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.black.opacity(0.7), in: .rect(cornerRadius: 20))
        .padding()
    }

    // MARK: - Data for the pitch guide

    private var pianoRollNotes: [PianoRollView.Note] {
        let showsMissed = viewModel.loop.phase == .showingResult || isRetryCountdown
        let missed = showsMissed ? Set(viewModel.lastResult?.missedNoteIDs ?? []) : []
        let plan = viewModel.song.transposition
        return viewModel.song.segments.flatMap(\.targetNotes).map {
            PianoRollView.Note(id: $0.id, midi: plan.transposed($0), start: $0.startTime, end: $0.endTime,
                               isMissed: missed.contains($0.id))
        }
    }

    /// Each lyric word on the note that starts closest to it (within a short window).
    private var wordLabels: [UUID: String] {
        let notes = viewModel.song.segments.flatMap(\.targetNotes)
        let window: TimeInterval = 0.3
        var labels: [UUID: String] = [:]
        for word in viewModel.lyrics.flatMap(\.words) {
            let candidates = notes.filter { labels[$0.id] == nil && abs($0.startTime - word.start) <= window }
            if let note = candidates.min(by: { abs($0.startTime - word.start) < abs($1.startTime - word.start) }) {
                labels[note.id] = word.text
            }
        }
        return labels
    }

    private var focusMIDI: [Int] {
        guard let segment = viewModel.loop.currentSegment else { return [] }
        let notes = segment.targetNotes.isEmpty
            ? viewModel.song.segments.flatMap(\.targetNotes)
            : segment.targetNotes
        return notes.map(viewModel.song.transposition.transposed)
    }
}

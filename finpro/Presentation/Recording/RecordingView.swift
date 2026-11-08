//
//  RecordingView.swift
//  finpro
//
//  Recording screen (PRD §5.5): full-screen front camera with the 9:16 frame guide, a tips card
//  before recording starts, then the timer, lyrics teleprompter, pitch guide and the pause,
//  record (end session) and display settings controls.
//

import SwiftUI
import UIKit

struct RecordingView: View {
    @State private var viewModel: RecordingViewModel
    @State private var confirmsEnd = false
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.lyricsOpacityKey) private var lyricsOpacity = RecordingDisplaySettings.defaultLyricsOpacity
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.pitchGuideOpacityKey) private var pitchGuideOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity

    private let sideInset: CGFloat = 16
    private let lyricsInset: CGFloat = 32
    private let pitchGuideHeight: CGFloat = 120
    private let recordButtonSize: CGFloat = 72
    private let stopButtonSize: CGFloat = 50
    private let stopGlyphSize: CGFloat = 30
    private let stopGlyphCornerRadius: CGFloat = 6
    private let timerRefresh: TimeInterval = 0.25
    private let sectionSpacing: CGFloat = 10
    private let controlsBottomPadding: CGFloat = 8
    /// Countdown: the screen dims, the number sits in a white circle (design).
    private let countdownDimOpacity = 0.4
    private let countdownCircleSize: CGFloat = 150
    /// How far the retry hint sits above the bottom of the pitch guide.
    private let retryHintLift: CGFloat = 24

    init(viewModel: RecordingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer
            content
            countdownLayer
        }
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
        .sheet(isPresented: $showsSettings) { RecordingSettingsSheet(viewModel: viewModel) }
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraLayer: some View {
        if let source = viewModel.previewSource, viewModel.isCameraReady {
            CameraPreviewView(session: source.previewSession, device: source.previewDevice)
                .ignoresSafeArea()
            FrameGuide()
                .ignoresSafeArea()
        } else if viewModel.isCameraReady, viewModel.status != .ready {
            // Simulator / fakes: there is no camera, the loop still runs.
            Label("No camera preview", systemImage: "video.slash")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .starting where !viewModel.isCameraReady:
            ProgressView("Getting ready…")
                .tint(.white)
                .foregroundStyle(.white)
        case .ready:
            VStack(spacing: 0) {
                topBar
                Spacer()
                tipsCard
                Spacer()
            }
        case .starting, .recording:
            recordingOverlay
        case .finishing:
            ProgressView("Saving your recording…")
                .tint(.white)
                .foregroundStyle(.white)
        case .blocked(let error):
            stoppedState(error, primary: ("Try Again", { Task { await viewModel.start() } }))
        case .interrupted(let error), .failed(let error):
            stoppedState(error, primary: viewModel.passedCount > 0
                         ? ("Export \(viewModel.passedCount) of \(viewModel.segmentCount)", { viewModel.exportAfterInterruption() })
                         : nil)
        }
    }

    // MARK: - Before recording

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "headphones")
                .font(.body)
                .foregroundStyle(Color.plumNight)
                .environment(\.colorScheme, .light)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text("Quick Recording Tips")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Wear headphones, keep your camera steady, and find a quiet place for the best recording.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await viewModel.beginRecording() }
            } label: {
                Text("Got It, Let’s Record")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Color.plumNight))
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
    /// the phrase is sung again. Touches pass through so pause stays reachable.
    @ViewBuilder
    private var countdownLayer: some View {
        if case .countdown(let remaining) = viewModel.loop.phase {
            ZStack {
                Color.black.opacity(countdownDimOpacity)
                    .ignoresSafeArea()

                Text("\(remaining)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color.plumInk)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: remaining)
                    .frame(width: countdownCircleSize, height: countdownCircleSize)
                    .background(Circle().fill(.white))
                    .accessibilityLabel("Starting in \(remaining)")

                if isRetryCountdown {
                    retryHint
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, recordButtonSize + sectionSpacing + controlsBottomPadding + retryHintLift)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var retryHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3.weight(.medium))
                .accessibilityHidden(true)
            Text("Sing this phrase again")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .frame(width: 240, height: 72)
        .background(.white.opacity(0.55), in: .rect(cornerRadius: 16))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }

    // MARK: - While recording

    private var recordingOverlay: some View {
        VStack(spacing: sectionSpacing) {
            topBar

            if showsLyrics, !viewModel.lyrics.isEmpty {
                RecordingLyricsView(lines: viewModel.lyrics,
                                    songTime: viewModel.displaySongTime,
                                    backgroundOpacity: lyricsOpacity)
                    .padding(.horizontal, lyricsInset)
            }

            Spacer()
            phaseInfo
            Spacer()

            if viewModel.showsBluetoothWarning {
                Label("Wired earphones give the best sync", systemImage: "airpodspro")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.85), in: .capsule)
            }

            if showsPitchGuide {
                PianoRollView(notes: pianoRollNotes,
                              trail: viewModel.trail,
                              focusMIDI: focusMIDI,
                              songTime: viewModel.displaySongTime,
                              dimmedBefore: viewModel.loop.phase == .preRoll ? viewModel.loop.currentSegment?.audioStartTime : nil,
                              isPaused: confirmsEnd || showsSettings,
                              wordLabels: wordLabels,
                              backgroundOpacity: pitchGuideOpacity)
                    .frame(height: pitchGuideHeight)
                    .padding(.horizontal, sideInset)
            }

            controls
        }
        .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                    }
                    .glassCircleButtonStyle()
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
        }
        .frame(minHeight: 48)
        .padding(.horizontal, sideInset)
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: timerRefresh)) { _ in
            Text(Duration.seconds(viewModel.elapsedRecordingTime())
                .formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2))))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel("Recording time")
        }
    }

    /// Recording: pause, record (ends the session), settings. Paused: the red record button takes
    /// the pause button's place to resume, and the stop square in the middle ends the session.
    private var controls: some View {
        HStack {
            Group {
                if viewModel.isPaused { resumeButton } else { pauseButton }
            }
            .frame(width: recordButtonSize, alignment: .leading)

            Spacer()

            if viewModel.isPaused { stopButton } else { endButton }

            Spacer()

            LiquidGlassGroup {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.white)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Recording settings")
            }
            .frame(width: recordButtonSize, alignment: .trailing)
        }
        .padding(.horizontal, sideInset + 8)
        .padding(.bottom, controlsBottomPadding)
    }

    private var pauseButton: some View {
        LiquidGlassGroup {
            Button {
                viewModel.pause()
            } label: {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.white)
            }
            .glassCircleButtonStyle()
            .disabled(!viewModel.canPause)
            .accessibilityLabel("Pause")
        }
    }

    /// The red record button; while paused it resumes (the current segment restarts after a countdown).
    private var resumeButton: some View {
        Button {
            viewModel.resume()
        } label: {
            recordCircle(size: recordButtonSize)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPause)
        .accessibilityLabel("Resume recording")
        .accessibilityHint("Restarts the current segment after a countdown")
    }

    private var endButton: some View {
        Button {
            confirmsEnd = true
        } label: {
            recordCircle(size: recordButtonSize)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.status != .recording)
        .accessibilityLabel("End recording")
    }

    private var stopButton: some View {
        Button {
            confirmsEnd = true
        } label: {
            RoundedRectangle(cornerRadius: stopGlyphCornerRadius, style: .continuous)
                .fill(Color.red)
                .frame(width: stopGlyphSize, height: stopGlyphSize)
                .frame(width: stopButtonSize, height: stopButtonSize)
                .background(Circle().fill(.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.status != .recording)
        .accessibilityLabel("End recording")
    }

    private func recordCircle(size: CGFloat) -> some View {
        Circle()
            .fill(Color.red)
            .padding(5)
            .background(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
            .frame(width: size, height: size)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var phaseInfo: some View {
        switch viewModel.loop.phase {
        case .preRoll:
            Label("Listen…", systemImage: "ear")
                .font(.title3.bold())
        case .singing:
            if let result = viewModel.lastResult, result.passed {
                Label("Segment \(result.segmentIndex + 1) passed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }
        case .idle, .ended, .countdown, .showingResult, .paused:
            // The missed notes on the pitch guide are the result, the countdown has its own layer,
            // and the paused state is shown by the resume and stop buttons.
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

/// Darkens everything outside the centred 9:16 area that ends up in the video.
private struct FrameGuide: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = min(size.width, size.height * 9 / 16)
            let height = width * 16 / 9
            let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle()
                .path(in: rect)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

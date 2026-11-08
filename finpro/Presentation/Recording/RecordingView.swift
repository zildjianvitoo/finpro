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
    private let timerRefresh: TimeInterval = 0.25

    init(viewModel: RecordingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer
            content
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
        .sheet(isPresented: $showsSettings) { settingsSheet }
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

    // MARK: - While recording

    private var recordingOverlay: some View {
        VStack(spacing: 10) {
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

    private var controls: some View {
        HStack {
            LiquidGlassGroup {
                Button {
                    viewModel.isPaused ? viewModel.resume() : viewModel.pause()
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .foregroundStyle(.white)
                }
                .glassCircleButtonStyle()
                .disabled(!viewModel.canPause)
                .accessibilityLabel(viewModel.isPaused ? "Resume" : "Pause")
                .accessibilityHint(viewModel.isPaused ? "Restarts the current segment after a countdown" : "")
            }

            Spacer()

            Button {
                confirmsEnd = true
            } label: {
                Circle()
                    .fill(Color.red)
                    .padding(5)
                    .background(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                    .frame(width: recordButtonSize, height: recordButtonSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.status != .recording)
            .accessibilityLabel("End recording")

            Spacer()

            LiquidGlassGroup {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.white)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Display settings")
            }
        }
        .padding(.horizontal, sideInset + 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var phaseInfo: some View {
        switch viewModel.loop.phase {
        case .countdown(let remaining):
            Text("\(remaining)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        case .preRoll:
            Label("Listen…", systemImage: "ear")
                .font(.title3.bold())
        case .paused:
            VStack(spacing: 4) {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.title3.bold())
                Text("Resume to sing this part again.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(.black.opacity(0.5), in: .rect(cornerRadius: 14))
        case .showingResult:
            if let result = viewModel.lastResult {
                CorrectionOverlayView(passed: result.passed, score: Double(result.score),
                                      missedNotes: missedNoteNames(result))
                    .padding(.horizontal)
            }
        case .singing:
            if let result = viewModel.lastResult, result.passed {
                Label("Segment \(result.segmentIndex + 1) passed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }
        case .idle, .ended:
            EmptyView()
        }
    }

    // MARK: - Settings

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(viewModel.progressTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.plumInk)
                    RecordingDisplaySettingsCard()
                    if viewModel.supportsReferenceVocal {
                        Toggle("Reference vocal", isOn: Binding(
                            get: { viewModel.referenceVocalEnabled },
                            set: { viewModel.setReferenceVocalEnabled($0) }))
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
                .padding()
            }
            .background(Color.onboardingBackground)
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Debug builds: is the microphone heard, and how often? 20 samples/s is the target (50 ms hop).
    private var pitchDebug: some View {
        let stats = viewModel.pitchStats
        let level = stats.lastLevelDB.isFinite ? "\(Int(stats.lastLevelDB)) dB" : "silent"
        return Text("Mic \(stats.lastNote ?? "—") · \(stats.samplesPerSecond)/s · voiced \(stats.voicedPercent)% · \(level)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.plumInkSecondary)
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
        let missed = viewModel.loop.phase == .showingResult ? Set(viewModel.lastResult?.missedNoteIDs ?? []) : []
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

    private func missedNoteNames(_ result: RecordingViewModel.SegmentResult) -> [String] {
        let plan = viewModel.song.transposition
        return viewModel.song.segments[result.segmentIndex].targetNotes
            .filter { result.missedNoteIDs.contains($0.id) }
            .map { PitchMath.noteName(midi: plan.transposed($0)) }
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

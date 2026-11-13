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
    @State private var confirmsDeleteLast = false
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.lyricsInGuideKey) private var lyricsInGuide = RecordingDisplaySettings.defaultLyricsInGuide
    @AppStorage(RecordingDisplaySettings.pitchGuideScaleKey) private var pitchGuideScale = RecordingDisplaySettings.defaultPitchGuideScale
    @AppStorage(RecordingDisplaySettings.lyricsTextStepKey) private var lyricsTextStep = RecordingDisplaySettings.defaultLyricsTextStep

    /// Measurements of the design (iPhone 17 Pro, 402 × 874 pt).
    private let backButtonSize: CGFloat = 44
    /// The design puts the back button 1 pt under the status bar; a little more air reads better.
    private let topBarInset: CGFloat = 9
    private let lyricsCardGap: CGFloat = 8
    private let lyricsCardInset: CGFloat = 33
    private let pitchGuideMaxWidth: CGFloat = 316
    /// The controls row is as tall as the record button, so the button stays inside the 9:16 frame;
    /// the gap is the design's 22 less the 6 pt the button used to stick out above its row.
    private let guideControlsGap: CGFloat = 16
    private let recordButtonSize: CGFloat = 80
    private let controlsBottomInset: CGFloat = 9
    private let settingsButtonSize: CGFloat = 50
    private let deleteGlyphSize: CGFloat = 28
    private let doneGlyphSize: CGFloat = 36
    /// Horizontal centres of the controls as a share of the width (85, 201, 284 and 355 of 402).
    private let settingsX = 0.211
    private let recordX = 0.5
    private let deleteX = 0.708
    private let doneX = 0.883
    private let timerRefresh: TimeInterval = 0.25
    private let timerCornerRadius: CGFloat = 10
    private let timerHeight: CGFloat = 26
    private let disabledOpacity = 0.4
    /// See-through enough to show the camera under it, visible enough to line up with.
    private let alignmentGuideOpacity = 0.3
    /// Countdown: the screen dims, the number sits in a white circle (design).
    private let countdownDimOpacity = 0.4
    private let countdownCircleSize: CGFloat = 150

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
                countdownLayer
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .ignoresSafeArea()
            // The design is light only; tokens resolve light even when the phone is in dark mode.
            .environment(\.colorScheme, .light)
        }
        .preferredColorScheme(.dark)
        .task {
            // Right after the camera and microphone prompts the app is not active yet, and a
            // camera or audio session started then may not run (first launch after install).
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            await viewModel.start()
        }
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
            if viewModel.completedCount > 0 {
                Button("Export \(viewModel.completedCount) of \(viewModel.segmentCount)") {
                    Task { await viewModel.finish() }
                }
            }
            Button("Discard", role: .destructive) {
                Task { await viewModel.discard() }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text(viewModel.completedCount > 0
                 ? "Your cover will use the \(viewModel.completedCount) segments you finished."
                 : "No segment has been finished yet.")
        }
        .confirmationDialog("Delete the last segment?", isPresented: $confirmsDeleteLast, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { viewModel.deleteLastSegment() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.completedCount > 0
                 ? "Segment \(viewModel.completedCount) will be sung again from the start."
                 : "The current segment will start again.")
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

    /// Retake / continue: the neighbouring clip, see-through over the camera, so the singer can
    /// line up with it before the first note. Gone once singing starts.
    @ViewBuilder
    private var alignmentGuide: some View {
        if viewModel.showsAlignmentGuide, let image = viewModel.alignmentImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .opacity(alignmentGuideOpacity)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func cameraLayer(_ layout: VideoLayout) -> some View {
        cameraSurface
            .overlay { alignmentGuide }
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
            stoppedState(error, primary: viewModel.completedCount > 0
                         ? ("Export \(viewModel.completedCount) of \(viewModel.segmentCount)", { viewModel.exportAfterInterruption() })
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
                      dimmedBefore: viewModel.singingFrom,
                      isPaused: confirmsEnd || confirmsDeleteLast || showsSettings,
                      wordLabels: wordLabels,
                      lyricsHeight: lyricsInPanel ? RecordingDisplaySettings.guideLyricsHeight : 0,
                      scale: pitchGuideScale)
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
                    // Back leaves without asking: the session is dropped and the setup page opens
                    // (a retake or continue goes back to the cover as it was).
                    Button {
                        Task { await viewModel.discard() }
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
            if viewModel.canDeleteSegment {
                deleteButton.position(x: width * deleteX, y: recordButtonSize / 2)
            }
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

    /// Starts the recording, pauses it, and resumes it while paused (the current segment restarts
    /// after a countdown). The ring around it shows the progress through the song.
    private var recordButton: some View {
        RecordProgressButton(
            mode: viewModel.status == .recording && !viewModel.isPaused ? .recording : .idle,
            progress: viewModel.songProgress,
            boundaries: viewModel.segmentBoundaries
        ) {
            switch viewModel.status {
            case .ready: Task { await viewModel.beginRecording() }
            default: if viewModel.isPaused { viewModel.resume() } else { viewModel.pause() }
            }
        }
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

    /// Deletes the last finished segment (after a confirmation) and sings it again, like deleting
    /// the last clip of a short video. The session pauses while the dialog is open.
    private var deleteButton: some View {
        Button {
            viewModel.pause()
            confirmsDeleteLast = true
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: deleteGlyphSize))
                .foregroundStyle(Color.screenBackground)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.status != .recording)
        .opacity(viewModel.status == .recording ? 1 : disabledOpacity)
        .accessibilityLabel("Delete last segment")
    }

    /// Done: exports the segments finished so far. With none finished yet it asks what to do instead.
    private var doneButton: some View {
        Button {
            if viewModel.hasNewTakes {
                Task { await viewModel.finish() }
            } else if !viewModel.pass.isSession {
                // Nothing new in this retake or continue: back to the cover as it was.
                Task { await viewModel.discard() }
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

    /// Light alert card over a dimmed screen (Sketch "TestFlight UT" 5.1, "Alerts/Light").
    private var tipsCard: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Recording Tips")
                        .font(.appHeadline)
                        .foregroundStyle(Color.primaryBrand)
                        .accessibilityAddTraits(.isHeader)
                    Text("Wear wired headphones, keep your camera steady, and find a quiet spot for the best result.")
                        .font(.appBody)
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 24, trailing: 8))
                Button {
                    Task { await viewModel.beginRecording() }
                } label: {
                    Text("Let’s Record")
                        .font(.appCTA)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Capsule().fill(Color.primaryButton))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: 330)
            .glassCardBackground(cornerRadius: 34)
            .environment(\.colorScheme, .light)
            .padding(.horizontal, AppSpacing.regular)
        }
    }

    // MARK: - Countdown

    /// Dims the screen and shows the number in a white circle, before the first segment and after
    /// a pause. Touches pass through so the controls stay reachable.
    @ViewBuilder
    private var countdownLayer: some View {
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
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var phaseInfo: some View {
        if viewModel.loop.phase == .preRoll {
            Label("Listen…", systemImage: "ear")
                .font(.appTitle3.bold())
                .foregroundStyle(.white)
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
        let plan = viewModel.song.transposition
        return viewModel.song.segments.flatMap(\.targetNotes).map {
            PianoRollView.Note(id: $0.id, midi: plan.transposed($0), start: $0.startTime, end: $0.endTime)
        }
    }

    /// Each lyric word on the note sung at the middle of it. A guide built from the lyrics has one
    /// note per word at the word's own time, so every note gets its word.
    private var wordLabels: [UUID: String] {
        let notes = viewModel.song.segments.flatMap(\.targetNotes)
        var labels: [UUID: String] = [:]
        for word in viewModel.lyrics.flatMap(\.words) {
            let middle = (word.start + word.end) / 2
            if let note = notes.first(where: { labels[$0.id] == nil && $0.startTime <= middle && middle < $0.endTime }) {
                labels[note.id] = word.text
            }
        }
        return labels
    }

    private var focusMIDI: [Int] {
        guard let segment = viewModel.loop.currentSegment else { return [] }
        return segment.targetNotes.map(viewModel.song.transposition.transposed)
    }
}

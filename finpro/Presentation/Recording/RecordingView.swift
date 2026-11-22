//
//  RecordingView.swift
//  finpro
//
//  Recording screen (PRD §5.5): the front camera in its 9:16 frame, a tips alert before recording
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
    /// Height of the open settings sheet, so the pitch guide can sit above it (design 5.2b).
    @State private var settingsSheetHeight: CGFloat = 0
    /// Space between the lifted pitch guide and the settings sheet.
    private let guideSheetGap: CGFloat = 20
    /// The recording tips, shown as a system alert before the first take.
    @State private var showsTips = false
    /// A stopped session (no earphones, interrupted, failed) as a system alert.
    @State private var showsStopped = false
    private static let tipsDelay: Duration = .milliseconds(450)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.showsPitchGuideKey) private var showsPitchGuide = true
    @AppStorage(RecordingDisplaySettings.lyricsInGuideKey) private var lyricsInGuide = RecordingDisplaySettings.defaultLyricsInGuide
    @AppStorage(RecordingDisplaySettings.pitchGuideScaleKey) private var pitchGuideScale = RecordingDisplaySettings.defaultPitchGuideScale
    @AppStorage(RecordingDisplaySettings.lyricsTextStepKey) private var lyricsTextStep = RecordingDisplaySettings.defaultLyricsTextStep
    // Where the user moved / how big they made the pitch guide (width 0 = default place).
    @AppStorage(RecordingDisplaySettings.guideFrameXKey) private var guideFrameX = 0.0
    @AppStorage(RecordingDisplaySettings.guideFrameYKey) private var guideFrameY = 0.0
    @AppStorage(RecordingDisplaySettings.guideFrameWidthKey) private var guideFrameWidth = 0.0
    @AppStorage(RecordingDisplaySettings.guideFrameHeightKey) private var guideFrameHeight = 0.0
    /// The pitch guide's default place (under the camera, above the controls), measured.
    @State private var defaultGuideFrame = CGRect.zero

    /// Measurements of the design (iPhone 17 Pro, 402 × 874 pt).
    private let backButtonSize: CGFloat = 44
    /// The back button and timer sit right under the status bar (design 5.2a, revision 2026-11-21).
    private let topBarInset: CGFloat = 0
    private let lyricsCardGap: CGFloat = 8
    private let lyricsCardInset: CGFloat = 33
    private let pitchGuideMaxWidth: CGFloat = 316
    /// The controls row is as tall as the record button, so the button stays inside the 9:16 frame;
    /// the pitch guide ends 13 pt above the record button's 68 pt frame (design 5.2a).
    private let guideControlsGap: CGFloat = 7
    private let recordButtonSize: CGFloat = 80
    private let controlsBottomInset: CGFloat = 3
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
    /// The pre-roll's small count shows its last `preRollCountFrom` seconds, refreshed this often.
    private let preRollCountFrom = 3
    private let preRollCountStep: TimeInterval = 0.1
    private let preRollCountSize: CGFloat = 36
    private let preRollInfoGap: CGFloat = 8

    /// The song library entry being recorded, to show the tips once per song; nil shows them.
    let tipsSongID: UUID?
    /// Camera and microphone permissions granted by `PermissionGate`; while false, the recording
    /// chrome is shown behind the system permission alert without starting capture yet.
    let isAuthorized: Bool
    @AppStorage(RecordingDisplaySettings.tipsShownSongsKey) private var tipsShownSongs = ""

    init(viewModel: RecordingViewModel, tipsSongID: UUID? = nil, isAuthorized: Bool = true) {
        _viewModel = State(initialValue: viewModel)
        self.tipsSongID = tipsSongID
        self.isAuthorized = isAuthorized
    }

    private var showsTipsForThisSong: Bool {
        guard viewModel.pass.isSession else { return false }
        guard let tipsSongID else { return true }
        return !RecordingDisplaySettings.contains(tipsSongID, in: tipsShownSongs)
    }

    var body: some View {
        // The outer reader respects the safe area, so it reports the insets; the content then
        // lays out on the full screen.
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let layout = VideoLayout(size: CGSize(width: outer.size.width + insets.leading + insets.trailing,
                                                  height: outer.size.height + insets.top + insets.bottom),
                                     top: insets.top, bottom: insets.bottom)
            ZStack(alignment: .top) {
                Color.black
                cameraLayer(layout)
                content(layout)
                countdownLayer
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isCountingDown)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .ignoresSafeArea()
            // The design is light only; tokens resolve light even when the phone is in dark mode.
            .environment(\.colorScheme, .light)
        }
        .preferredColorScheme(.dark)
        // The user sings without touching the phone: the screen must not dim or lock mid-take.
        .keepsScreenAwake()
        .task(id: isAuthorized) {
            guard isAuthorized else { return }
            // Right after the camera and microphone prompts the app is not active yet, and a
            // camera or audio session started then may not run (first launch after install).
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            await viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard isAuthorized, phase == .background else { return }
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
        .alert("Quick Recording Tips", isPresented: $showsTips) {
            Button("Let’s Record") {
                if let tipsSongID { tipsShownSongs = RecordingDisplaySettings.adding(tipsSongID, to: tipsShownSongs) }
                Task { await viewModel.beginRecording() }
            }
        } message: {
            Text("Wear wired headphones, keep your camera steady, and find a quiet spot for the best result.")
        }
        .sheet(isPresented: $showsSettings) {
            RecordingSettingsSheet(viewModel: viewModel) { settingsSheetHeight = $0 }
        }
        .alert(stoppedError?.title ?? "", isPresented: $showsStopped, presenting: stoppedError) { _ in
            // The way forward takes the cancel role, so iOS adds no extra Cancel that would leave
            // an empty screen behind the alert.
            if case .blocked = viewModel.status {
                Button("Try Again", role: .cancel) { Task { await viewModel.start() } }
                Button("Start Over", role: .destructive) { Task { await viewModel.discard() } }
            } else if viewModel.completedCount > 0 {
                Button("Export \(viewModel.completedCount) of \(viewModel.segmentCount)", role: .cancel) {
                    viewModel.exportAfterInterruption()
                }
                Button("Start Over", role: .destructive) { Task { await viewModel.discard() } }
            } else {
                Button("Start Over", role: .cancel) { Task { await viewModel.discard() } }
            }
        } message: { error in
            Text(error.message)
        }
        .task(id: stoppedError) {
            guard stoppedError != nil else { showsStopped = false; return }
            // Like the tips: UIKit refuses an alert while the screen is still sliding in.
            try? await Task.sleep(for: Self.tipsDelay)
            if !Task.isCancelled { showsStopped = true }
        }
        .onChange(of: showsStopped) { _, shown in
            // Try Again that is blocked again (still no earphones) ends in the same state, which the
            // task above does not see as a change: ask again once the alert has gone.
            guard !shown else { return }
            Task {
                try? await Task.sleep(for: Self.tipsDelay)
                if stoppedError != nil, !showsStopped { showsStopped = true }
            }
        }
        .task(id: viewModel.status == .ready) {
            guard viewModel.status == .ready else { showsTips = false; return }
            // Only before the first recording of a song: a retake, continuing, or the same song
            // again starts with the record button instead.
            guard showsTipsForThisSong else { return }
            // UIKit refuses an alert while the screen is still sliding in; wait for it to settle.
            try? await Task.sleep(for: Self.tipsDelay)
            if !Task.isCancelled { showsTips = true }
        }
        .onDisappear { viewModel.cleanupIfStillActive() }
        .edgeSwipeBack(isEnabled: viewModel.loop.phase == .idle && !showsSettings && !showsTips && !showsStopped) {
            Task { await viewModel.discard() }
        }
    }

    // MARK: - Layout

    /// The camera shows in a 9:16 frame under the status bar, the part that ends up in the video;
    /// the rest of the screen is black.
    private struct VideoLayout {
        let size: CGSize
        let top: CGFloat
        /// The home indicator's area, which a sheet also covers.
        var bottom: CGFloat = 0

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
        if !isAuthorized {
            sessionOverlay(layout)
        } else {
            switch viewModel.status {
            case .starting where !viewModel.isCameraReady:
                loading("Getting ready…")
            case .ready, .starting, .recording:
                sessionOverlay(layout)
            case .finishing:
                loading("Saving your recording…")
            case .blocked, .interrupted, .failed:
                // Shown as a system alert (see `stoppedAlert`); the camera stays visible behind it.
                Color.clear
            }
        }
    }

    private func loading(_ title: String) -> some View {
        VStack(spacing: AppSpacing.medium) {
            LoadingMascotView()
            LoadingTextView(title: title)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.loadingOverlay.opacity(AppLayout.loadingOverlayOpacity).ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Before and while recording

    /// Top bar, lyrics, pitch guide and controls over the camera frame; the tips alert is presented on top
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

            if showsPitchGuide {
                // Holds the default place; the guide itself floats above (movable, see below).
                Color.clear
                    .frame(maxWidth: pitchGuideMaxWidth)
                    .frame(height: guideHeight)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.overlaySpace)) } action: {
                        defaultGuideFrame = $0
                    }
                    .padding(.bottom, guideControlsGap)
            }

            controls(width: layout.size.width)
                .padding(.bottom, controlsBottomInset)
        }
        .padding(.top, layout.top)
        .frame(width: layout.size.width, height: layout.top + layout.videoHeight, alignment: .top)
        .coordinateSpace(.named(Self.overlaySpace))
        .overlay(alignment: .topLeading) {
            if showsPitchGuide, defaultGuideFrame.width > 0 {
                // Between the top bar and the controls, so it never covers a button.
                let top = layout.top + topBarInset + backButtonSize + lyricsCardGap
                let bounds = CGRect(x: 0, y: top, width: layout.size.width,
                                    height: max(defaultGuideFrame.height, defaultGuideFrame.maxY - top))
                MovablePanel(defaultFrame: defaultGuideFrame, bounds: bounds,
                             minimumSize: CGSize(width: Self.guideMinimumWidth, height: defaultGuideFrame.height * 0.6),
                             frame: guideFrameBinding) { size in
                    pitchGuide(zoom: guideFrameWidth > 0 ? size.height / defaultGuideFrame.height : 1)
                }
                // While the settings sheet is open the guide rises above it, so a new size shows
                // at once (design 5.2b).
                .offset(y: settingsLift(sheetTop: layout.size.height - layout.bottom))
                .animation(reduceMotion ? nil : .snappy, value: showsSettings)
                .animation(reduceMotion ? nil : .snappy, value: settingsSheetHeight)
            }
        }
        // Above everything, right under the timer: lower down they were hidden by a moved or
        // enlarged pitch guide.
        .overlay(alignment: .top) {
            VStack(spacing: preRollInfoGap) {
                phaseInfo
            }
            .padding(.top, layout.top + topBarInset + backButtonSize + preRollInfoGap)
            .allowsHitTesting(false)
        }
        .animation(.snappy, value: lyricsInGuide)
        .animation(.snappy, value: showsLyrics)
    }

    /// How far the pitch guide moves up while the settings sheet covers it (0 when it is clear).
    /// `sheetTop` is where a sheet of the reported height begins, before its own height.
    private func settingsLift(sheetTop: CGFloat) -> CGFloat {
        guard showsSettings, settingsSheetHeight > 0 else { return 0 }
        let bottom = guideFrameWidth > 0 ? guideFrameY + guideFrameHeight : defaultGuideFrame.maxY
        return min(0, sheetTop - settingsSheetHeight - guideSheetGap - bottom)
    }

    private static let overlaySpace = "recordingOverlay"
    private static let guideMinimumWidth: CGFloat = 200

    /// The user's pitch guide frame, nil while it is in its default place.
    private var guideFrameBinding: Binding<CGRect?> {
        Binding(
            get: { guideFrameWidth > 0 ? CGRect(x: guideFrameX, y: guideFrameY, width: guideFrameWidth, height: guideFrameHeight) : nil },
            set: { rect in
                guideFrameX = Double(rect?.minX ?? 0)
                guideFrameY = Double(rect?.minY ?? 0)
                guideFrameWidth = Double(rect?.width ?? 0)
                guideFrameHeight = Double(rect?.height ?? 0)
            })
    }

    private func pitchGuide(zoom: CGFloat) -> some View {
        PianoRollView(notes: pianoRollNotes,
                      voiceDot: viewModel.voiceDot,
                      focusMIDI: focusMIDI,
                      songTime: viewModel.displaySongTime,
                      dimmedBefore: viewModel.singingFrom,
                      isPaused: confirmsEnd || confirmsDeleteLast || showsSettings,
                      wordLabels: wordLabels,
                      lyricsHeight: lyricsInPanel ? RecordingDisplaySettings.guideLyricsHeight : 0,
                      scale: pitchGuideScale,
                      fixedRows: Double(RecordingDisplaySettings.guideRows),
                      contentZoom: min(max(zoom, 0.6), 2.5))
            .overlay(alignment: .bottom) {
                if lyricsInPanel {
                    RecordingGuideLyricsView(lines: viewModel.lyrics, songTime: viewModel.displaySongTime)
                        .frame(height: RecordingDisplaySettings.guideLyricsHeight)
                        .padding(.bottom, PianoRollView.bottomInset / 2)
                }
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
            .transition(.opacity)
        }
    }

    private var isCountingDown: Bool {
        if case .countdown = viewModel.loop.phase { true } else { false }
    }

    /// During the pre-roll: "Listen…" and, in its last seconds, a small 3-2-1 to the first note of
    /// the segment. It replaces the countdown that dimmed the screen, so the guide stays visible.
    @ViewBuilder
    private var phaseInfo: some View {
        if viewModel.loop.phase == .preRoll {
            TimelineView(.periodic(from: .now, by: preRollCountStep)) { _ in
                let remaining = viewModel.secondsToSegmentStart().map { Int($0.rounded(.up)) }
                HStack(spacing: 10) {
                    Label("Listen…", systemImage: "ear")
                        .font(.appTitle3.bold())
                    if let remaining, (1...preRollCountFrom).contains(remaining) {
                        Text("\(remaining)")
                            .font(.appTitle3.bold())
                            .monospacedDigit()
                            .foregroundStyle(Color.primary800)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: remaining)
                            .frame(width: preRollCountSize, height: preRollCountSize)
                            .background(Circle().fill(.white))
                            .accessibilityLabel("Starting in \(remaining)")
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
            }
            .transition(.opacity)
        }
    }

    private var stoppedError: UserFacingError? {
        switch viewModel.status {
        case .blocked(let error), .interrupted(let error), .failed(let error): error
        default: nil
        }
    }

    // MARK: - Data for the pitch guide

    private var pianoRollNotes: [PianoRollView.Note] {
        let plan = viewModel.song.transposition
        return viewModel.song.segments.flatMap(\.targetNotes).map {
            PianoRollView.Note(id: $0.id, midi: plan.transposed($0), start: $0.startTime, end: $0.endTime)
        }
    }

    private var wordLabels: [UUID: String] { viewModel.wordLabels }

    private var focusMIDI: [Int] {
        guard let segment = viewModel.loop.currentSegment else { return [] }
        return segment.targetNotes.map(viewModel.song.transposition.transposed)
    }
}

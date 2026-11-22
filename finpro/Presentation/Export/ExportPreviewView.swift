//
//  ExportPreviewView.swift
//  finpro
//
//  Final result (PRD §5.9, Sketch 7.0–7.2): the cover being merged (7.0), its preview with the
//  clips used (7.1), and Export, which saves it to Photos with a progress border around the video
//  (7.2). Owner: Zildjian Vito (ZV-13).
//

import AVFoundation
import SwiftUI
import UIKit

struct ExportPreviewView: View {
    private enum Page {
        /// 7.0 while merging, then 7.1.
        case preview
        /// 7.2: saving to Photos.
        case exporting
    }

    @State private var viewModel: CompingViewModel
    @State private var player: CoverPlayerController?
    @State private var showsSound = false
    /// The pitch guide over the video, with each note green or red (remembered for next time).
    @AppStorage("previewShowsPitchGuide") private var showsPitchGuide = true
    @State private var mixerReady = false
    @State private var mixerError: String?
    /// Saving the edited sound before leaving failed: the message, offering to leave without it.
    @State private var soundSaveError: String?
    /// Leaving waits for the cover file (exported in the background) before going home.
    @State private var savingCover = false
    @State private var page = Page.preview
    @State private var confirmsLeave = false
    /// Shown progress of the save to Photos, which reports none: it runs ahead to `saveRunUp`
    /// while saving and completes when the save does.
    @State private var exportProgress: Double = 0
    @State private var showsExported = false
    @State private var showsSaveError = false
    let onRetake: () -> Void
    let onStartOver: () -> Void
    /// Sing one clip again (its segment index); the new take replaces it in the cover.
    let onRetakeClip: (Int) -> Void
    /// Sing on from the first segment not in the cover.
    let onContinue: () -> Void
    /// Leave dialog: keep the cover on Home as a draft and go home.
    let onSaveDraft: () -> Void
    /// Leave dialog: remove the cover from Home and go home.
    let onDiscard: () -> Void
    /// The cover is already kept (reopened from Home's covers, or saved to Photos): back offers
    /// Save and Exit (keeps the sound) or Cancel (leaves without it) instead of Save to Draft / Discard.
    let keepsCoverOnLeave: Bool

    init(viewModel: CompingViewModel, onRetake: @escaping () -> Void, onStartOver: @escaping () -> Void,
         onRetakeClip: @escaping (Int) -> Void = { _ in }, onContinue: @escaping () -> Void = {},
         onSaveDraft: @escaping () -> Void = {}, onDiscard: @escaping () -> Void = {},
         keepsCoverOnLeave: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.onRetake = onRetake
        self.onStartOver = onStartOver
        self.onRetakeClip = onRetakeClip
        self.onContinue = onContinue
        self.onSaveDraft = onSaveDraft
        self.onDiscard = onDiscard
        self.keepsCoverOnLeave = keepsCoverOnLeave
    }

    private let screenInset: CGFloat = 17
    /// Header buttons at y 70, 8 pt under the status bar (design 6.2a).
    private let topBarInset: CGFloat = 5
    private let videoMaxWidth: CGFloat = 280
    private let videoAspectRatio: CGFloat = 9.0 / 16.0
    private let videoCornerRadius: CGFloat = 12
    private let seekBarInset: CGFloat = 15
    private let guideInset: CGFloat = 8
    /// Touch width of the full-screen button next to the time.
    private let fullScreenButtonSize: CGFloat = 36
    /// The retake mark on a chosen clip (design 6.2a).
    private let retakeBadgeSize: CGFloat = 28
    private let retakeVeilOpacity = 0.5
    /// At least 6 lines, as in the recording guide (more when the notes on screen spread wider).
    private let guideRows = RecordingDisplaySettings.guideRows
    private let seekBarBottom: CGFloat = 20
    private let timelineHeight: CGFloat = 2
    private let scrubbingLineHeight: CGFloat = 4
    private let scrubKnobSize: CGFloat = 12
    /// Finger-sized touch area around the 2 pt line.
    private let scrubTouchHeight: CGFloat = 32
    private let accessibilitySeekStep: TimeInterval = 5
    private let sheetCornerRadius: CGFloat = 12
    private let sheetTitleInset: CGFloat = 28
    private let clipsInset: CGFloat = 32
    private let clipWidth: CGFloat = 85
    private let clipHeight: CGFloat = 124
    private let clipSpacing: CGFloat = 12
    private let clipCornerRadius: CGFloat = 12
    private let selectedClipBorder: CGFloat = 4
    private let badgeInset: CGFloat = 4
    private let exportFrameWidth: CGFloat = 288
    private let exportFrameAspectRatio: CGFloat = 288.0 / 453.0
    private let exportVideoInset: CGFloat = 18
    private let exportBorderWidth: CGFloat = 10
    private let saveRunUp = 0.9
    private let saveRunUpDuration: TimeInterval = 1.6
    private let exportedAlertDelay: Duration = .milliseconds(350)

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.exportState {
            // While the live preview plays, a failed background export surfaces on Export or leave.
            case .failed(let message) where !viewModel.isLivePreviewReady:
                failed(message: message)
            default:
                switch page {
                case .preview: preview.transition(.opacity)
                case .exporting: exporting.transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground.ignoresSafeArea())
        .overlay {
            if isMerging {
                ObservationScope { merging(title: "Merging your recording…", progress: mergeProgress) }
            } else if savingCover {
                ObservationScope { merging(title: "Saving your cover…", progress: viewModel.soundProgress ?? mergeProgress) }
            } else if page == .preview, let progress = viewModel.soundProgress {
                merging(title: "Saving sound changes…", progress: progress)
            }
        }
        // A locked phone interrupts the export (AVFoundation -11847), the sound re-export too.
        .keepsScreenAwake(isMerging || viewModel.isExportRunning || viewModel.soundProgress != nil)
        .animation(.default, value: page)
        .animation(.default, value: isMerging)
        .animation(.default, value: savingCover)
        .animation(.default, value: viewModel.soundProgress == nil)
        .task {
            // iOS stops an export started while the app is not in the foreground (screen locked
            // right as the recording ended, Control Center open): wait until it is.
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            // Play the takes straight away; the file for Home, the draft and Photos exports meanwhile.
            if player == nil, await viewModel.prepareLivePreview(), let item = try? viewModel.makeMixerItem() {
                player = CoverPlayerController(item: item)
                mixerReady = true
            }
            viewModel.exportInBackground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.appBecameActive() } }
        }
        .onAppear {
            // An existing video (draft) is ready before the first frame: no merge, no onChange.
            if player == nil, viewModel.hasPlayableFile, let url = viewModel.exportedURL {
                player = CoverPlayerController(url: url)
            }
        }
        .onChange(of: viewModel.exportedURL) { _, url in
            // The sound mixer plays the edited levels live; a re-export with them must not replace it.
            guard !mixerReady else { return }
            player = url.flatMap { viewModel.hasPlayableFile ? CoverPlayerController(url: $0) : nil }
        }
        .onChange(of: viewModel.saveState) { _, state in saveStateChanged(state) }
        // Saving with edited sound re-exports first: its real progress fills the border up to the run-up.
        .onChange(of: viewModel.soundProgress) { _, progress in
            guard page == .exporting else { return }
            withAnimation(.linear(duration: 0.2)) { exportProgress = (progress ?? 1) * saveRunUp }
        }
        .onDisappear {
            player?.pause()
            // Off to a retake, or discarded: this version's file is not needed (leaving to keep
            // the cover waits for it first).
            viewModel.cancelExport()
        }
        .alert("Video Exported", isPresented: $showsExported) {
            // The confirm role draws a filled button in the tint (our dark purple) on iOS 26.
            if #available(iOS 26, *) {
                Button("OK", role: .confirm) { onStartOver() }
            } else {
                Button("OK") { onStartOver() }
            }
        } message: {
            Text("This video was saved to your camera roll.")
        }
        .alert("Couldn't Export", isPresented: $showsSaveError) {
            if viewModel.saveState == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    page = .preview
                }
            }
            Button("OK", role: .cancel) { page = .preview }
        } message: {
            Text(saveErrorMessage)
        }
        // Icons and alert buttons: dark plum, light in dark mode (primary800 has no dark variant).
        .tint(Color.plumNight)
    }

    // MARK: - 7.0 Merging

    /// Waiting for the merge before anything can be shown: only when the live preview can't be built.
    private var isMerging: Bool {
        guard !viewModel.isLivePreviewReady else { return false }
        switch viewModel.exportState {
        case .idle, .exporting: return true
        case .finished, .failed: return false
        }
    }

    private var mergeProgress: Double {
        viewModel.isExportRunning ? viewModel.exportProgress : 0
    }

    private func merging(title: String, progress: Double) -> some View {
        ZStack {
            Color.loadingOverlay.opacity(AppLayout.loadingOverlayOpacity)
                .ignoresSafeArea()
            // Like the preparing screen (design 6.1 / 4.3): the text close under the mascot.
            VStack(spacing: 0) {
                LoadingMascotView()
                LoadingTextView(title: title, progress: progress, font: .appHeadline)
            }
            .offset(y: -AppSpacing.regular)
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    // MARK: - 7.1 Preview

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    player?.pause()
                    requestLeave()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.primary)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Back")

                Spacer()

                Button {
                    withAnimation(.snappy) { showsPitchGuide.toggle() }
                } label: {
                    Image(systemName: showsPitchGuide ? "pianokeys.inverse" : "pianokeys")
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Pitch guide")
                .accessibilityValue(showsPitchGuide ? "Shown" : "Hidden")
                .disabled(!viewModel.canPreview)

                Button {
                    showsSound.toggle()
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Sound")
                .disabled(!viewModel.canPreview)

                Button("Export", action: startExport)
                    .buttonStyle(ExportButtonStyle())
                    .disabled(!viewModel.canPreview)
            }
            .padding(.horizontal, screenInset)
            .padding(.top, topBarInset)

            coverVideo
                .padding(.vertical, 16)
                .frame(maxHeight: .infinity)

            if showsSound {
                VStack(alignment: .leading, spacing: 12) {
                    if !mixerReady { ProgressView() }
                    // Icons and dividers as in design 6.2d.
                    volumeSlider("Vocals", value: $viewModel.vocals, minIcon: "speaker.wave.1.fill", maxIcon: "speaker.wave.2.fill")
                    Divider()
                    volumeSlider("Music", value: $viewModel.music, minIcon: "music.note.slash", maxIcon: "music.note")
                    Divider()
                }
                .padding(24)
                .background(Color.secondaryButton)
                .disabled(!mixerReady)
                .task {
                    guard !mixerReady else { return }
                    do {
                        try await viewModel.prepareMixer()
                        try Task.checkCancellation()
                        let replacement = CoverPlayerController(item: try viewModel.makeMixerItem())
                        let position = player?.player.currentTime().seconds ?? 0
                        let wasPlaying = player?.isPlaying == true
                        player?.pause()
                        replacement.seek(to: position.isFinite ? position : 0)
                        player = replacement
                        if wasPlaying { replacement.play() }
                        mixerReady = true
                    } catch {
                        guard !Task.isCancelled else { return }
                        showsSound = false
                        mixerError = error.localizedDescription
                    }
                }
            } else { clipsSheet }
        }
        .edgeSwipeBack(isEnabled: !confirmsLeave && !showsSound, interactiveSlide: false) {
            player?.pause()
            requestLeave()
        }
        .saveChangesAlert(
            isPresented: $confirmsLeave,
            onCancel: { keepsCoverOnLeave ? onStartOver() : onDiscard() },
            onSave: { saveCoverThen(keepsCoverOnLeave ? onStartOver : onSaveDraft) }
        )
        .alert("Couldn't Save Your Cover", isPresented: Binding(get: { soundSaveError != nil }, set: { if !$0 { soundSaveError = nil } })) {
            Button("Leave Without Changes", role: .destructive) {
                soundSaveError = nil
                keepsCoverOnLeave ? onStartOver() : onSaveDraft()
            }
            Button("Cancel", role: .cancel) { soundSaveError = nil }
        } message: { Text(soundSaveError ?? "") }
        .alert("Sound unavailable", isPresented: Binding(get: { mixerError != nil }, set: { if !$0 { mixerError = nil } })) {
            Button("OK") { mixerError = nil }
        } message: { Text(mixerError ?? "") }
    }

    private var coverVideo: some View {
        Color.clear
            .aspectRatio(videoAspectRatio, contentMode: .fit)
            .frame(maxWidth: videoMaxWidth)
            .overlay { videoContent }
            .clipShape(.rect(cornerRadius: videoCornerRadius, style: .continuous))
            .overlay(alignment: .top) {
                if showsPitchGuide, let player {
                    // Reads the playing time: in its own scope, so the screen isn't rebuilt with it.
                    ObservationScope { pitchGuide(player) }
                        .padding(guideInset)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let player {
                    ObservationScope {
                        seekBar(player)
                            // The purple outline follows the clip that is playing. Read here, not in
                            // the screen's body, so the time doesn't rebuild the whole screen.
                            .onChange(of: player.currentTime) { _, time in viewModel.followPlayback(at: time) }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { player?.togglePlayback() }
    }

    @ViewBuilder
    private var videoContent: some View {
        if let player {
            PlayerLayerView(player: player.player)
        } else if isMerging {
            Color.screenBackground
        } else {
            ZStack {
                Color.clipPlaceholder
                Label("No preview", systemImage: "film")
                    .font(.footnote)
                    .foregroundStyle(Color.primary800)
            }
        }
    }

    /// The song's notes scrolling with the video, green where they were sung well and red where
    /// they were missed, so the singer sees where to retake. Touches pass through to the video.
    private func pitchGuide(_ player: CoverPlayerController) -> some View {
        let isPlaying = player.isPlaying
        // Read `currentTime` only while paused/scrubbing so a seek redraws the guide;
        // while playing, `TimelineView(.animation)` drives every frame from `player.liveTime()`
        // without 10 Hz SwiftUI rebuilds.
        let pausedTime: TimeInterval? = isPlaying ? nil : player.currentTime
        let notes = viewModel.guideNotes
        let focus: [Int]
        if let pausedTime {
            focus = notes.filter { $0.end > pausedTime }.prefix(PianoRollView.upcomingNoteCount).map(\.midi)
        } else {
            focus = viewModel.initialFocusMIDI
        }
        let songTime: () -> TimeInterval? = { pausedTime ?? player.liveTime() }
        // No lyric lines on the preview (user decision 2026-11-21); the word under each note stays.
        return PianoRollView(notes: notes,
                             noteStyle: .review(hit: viewModel.hitNoteIDs, missed: viewModel.missedNoteIDs),
                             focusMIDI: focus,
                             songTime: songTime,
                             isPaused: !isPlaying,
                             showsVoiceDot: false,
                             wordLabels: viewModel.wordLabels,
                             fixedRows: Double(guideRows))
            .frame(height: PianoRollView.height(rows: CGFloat(guideRows)))
            .allowsHitTesting(false)
            .accessibilityLabel("Pitch guide: green notes were sung well, red notes were missed")
    }

    private func seekBar(_ player: CoverPlayerController) -> some View {
        VStack(spacing: 13) {
            HStack {
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Spacer()

                Text("\(CompingViewModel.clock(player.currentTime)) / \(CompingViewModel.clock(player.duration))")
                    .font(.subheadline)
                    .monospacedDigit()

                // The system player, full screen, with its own controls (shares this player).
                Button { FullScreenVideoPresenter.present(player.player) } label: {
                    Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                        .font(.title3)
                        .frame(minWidth: fullScreenButtonSize, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Full screen")
            }
            .foregroundStyle(.white)

            timeline(player)
        }
        .padding(.horizontal, seekBarInset)
        .padding(.bottom, seekBarBottom)
    }

    /// The seek bar: drag (or tap) anywhere on it to move through the cover, like a video player.
    /// The touch area is taller than the line; the line thickens and shows a knob while dragging.
    private func timeline(_ player: CoverPlayerController) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progressWidth = width * player.progress
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.67))
                Capsule().fill(.white)
                    .frame(width: progressWidth)
            }
            .frame(height: player.isScrubbing ? scrubbingLineHeight : timelineHeight)
            .overlay(alignment: .leading) {
                if player.isScrubbing {
                    Circle().fill(.white)
                        .frame(width: scrubKnobSize, height: scrubKnobSize)
                        .offset(x: progressWidth - scrubKnobSize / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        player.beginScrubbing()
                        player.scrub(to: value.location.x / width)
                    }
                    .onEnded { _ in player.endScrubbing() }
            )
        }
        .frame(height: scrubTouchHeight)
        .padding(.vertical, -(scrubTouchHeight - timelineHeight) / 2)
        .animation(.easeOut(duration: 0.15), value: player.isScrubbing)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(CompingViewModel.clock(player.currentTime)) of \(CompingViewModel.clock(player.duration))")
        .accessibilityAdjustableAction { direction in
            guard player.duration > 0 else { return }
            let step = accessibilitySeekStep / player.duration
            player.seek(to: (player.progress + (direction == .increment ? step : -step)) * player.duration)
        }
    }

    private var clipsSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clips")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryBrand)
                .padding(.horizontal, sheetTitleInset)
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: clipSpacing) {
                        ForEach(viewModel.clips) { clip in
                            clipItem(clip).id(clip.id)
                        }
                        if viewModel.canContinueRecording && !isMerging {
                            continueTile
                        }
                    }
                    .padding(.horizontal, clipsInset)
                }
                .scrollIndicators(.hidden)
                // The chosen clip's border sits outside it; don't cut it off at the top and bottom.
                .scrollClipDisabled()
                // Keep the playing clip in view.
                .onChange(of: viewModel.selectedClipID) { _, id in
                    guard let id else { return }
                    withAnimation { scroller.scrollTo(id, anchor: .center) }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: sheetCornerRadius, topTrailingRadius: sheetCornerRadius,
                                   style: .continuous)
                .fill(Color.secondaryButton)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func clipItem(_ clip: CompingViewModel.Clip) -> some View {
        let isSelected = !isMerging && viewModel.selectedClipID == clip.id
        // Retake shows only on a clip the user tapped, not on one the playing video reached.
        let showsRetake = isSelected && viewModel.isClipChosen
        return VStack(spacing: 8) {
            Button {
                // The first tap selects a clip and plays from it; tapping it again (showing Retake) retakes it.
                if showsRetake {
                    player?.pause()
                    onRetakeClip(clip.id)
                } else {
                    viewModel.selectClip(clip.id)
                    player?.seek(to: clip.start)
                }
            } label: {
                clipFrame(of: clip)
                    .frame(width: clipWidth, height: clipHeight)
                    .overlay {
                        if showsRetake {
                            // Design 6.2a: the clip fades under a white veil, with a purple pencil
                            // circle in the middle (tap again to retake it).
                            // The pencil is cut out of the circle (SF "pencil.circle.fill"), so the faded clip shows through.
                            ZStack {
                                Color.white.opacity(retakeVeilOpacity)
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: retakeBadgeSize))
                                    .foregroundStyle(Color.primaryDark)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if clip.needsRetake && !isMerging {
                            Text("Needs retake")
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.noteMiss))
                                .padding(.bottom, badgeInset)
                        }
                    }
                    .clipShape(.rect(cornerRadius: clipCornerRadius, style: .continuous))
                    .overlay {
                        // Outside the clip (Sketch border position "Outside"), so it does not cover the frame.
                        if isSelected {
                            RoundedRectangle(cornerRadius: clipCornerRadius + selectedClipBorder, style: .continuous)
                                .strokeBorder(Color.primaryDark, lineWidth: selectedClipBorder)
                                .padding(-selectedClipBorder)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isMerging)

            if !isMerging {
                Text(viewModel.timeRange(of: clip))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.primary300)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: clipWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clip \(clip.id + 1), \(viewModel.timeRange(of: clip))\(clip.needsRetake ? ", needs retake" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double-tap to sing this clip again" : "Double-tap to select")
    }

    /// Continue Recording: shown when the session ended early.
    private var continueTile: some View {
        Button {
            player?.pause()
            onContinue()
        } label: {
            continueTileLabel
        }
        .buttonStyle(.plain)
    }

    private var continueTileLabel: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.square.fill")
                .font(.title)
                .foregroundStyle(Color.primaryBrand)
            Text("Continue\nRecording")
                .font(.system(size: 10, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.secondaryText)
        }
        .frame(width: clipWidth, height: clipHeight)
        .background(Color.clipAddTile, in: .rect(cornerRadius: clipCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The still frame of a clip, filling its space; a flat tile when there is none.
    @ViewBuilder
    private func clipFrame(of clip: CompingViewModel.Clip?) -> some View {
        if let clip, let image = viewModel.thumbnails[clip.id] {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            isMerging ? Color.screenBackground : Color.clipPlaceholder
        }
    }

    // MARK: - 7.2 Exporting

    private var exporting: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    page = .preview
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.plumNight)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, screenInset)
            .padding(.top, topBarInset)

            VStack(spacing: AppSpacing.tiny) {
                Text("Exporting…")
                    .font(.appTitle2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Please don’t close the app or lock your screen.")
                    .font(.appSubheadline)
            }
            .foregroundStyle(Color.primaryBrand)
            .multilineTextAlignment(.center)
            .padding(.top, AppSpacing.medium)
            .padding(.horizontal, screenInset)

            Spacer(minLength: 24)

            ZStack {
                ExportProgressBorder(progress: exportProgress, lineWidth: exportBorderWidth)
                exportStill
                    .clipShape(.rect(cornerRadius: videoCornerRadius, style: .continuous))
                    .overlay { AnimatedPercent(value: exportProgress) }
                    .padding(exportVideoInset)
            }
            .aspectRatio(exportFrameAspectRatio, contentMode: .fit)
            .frame(maxWidth: exportFrameWidth)
            .padding(.horizontal, screenInset)

            Spacer(minLength: 24)
        }
        // Export tapped before the background export finished: the border follows it.
        .onChange(of: mergeProgress) { _, progress in
            guard viewModel.isExportRunning else { return }
            withAnimation(.linear(duration: 0.2)) { exportProgress = progress * saveRunUp }
        }
    }

    /// The paused frame of the cover, lightened as in the design.
    @ViewBuilder
    private var exportStill: some View {
        Group {
            if let player {
                PlayerLayerView(player: player.player)
            } else {
                clipFrame(of: viewModel.clips.first)
            }
        }
        .overlay(Color.white.opacity(0.3))
    }

    private func volumeSlider(_ title: String, value: Binding<Float>, minIcon: String, maxIcon: String) -> some View {
        let range: ClosedRange<Float> = 0...2
        func set(_ level: Float) {
            value.wrappedValue = level
            viewModel.updatePreviewVolume()
        }
        return VStack(alignment: .leading) {
            Text(title).font(.appBody).padding(.leading, AppSpacing.small)
            HStack {
                // The end icons jump straight to silent and to the loudest level.
                volumeEndButton(minIcon, label: "Mute \(title)") { set(range.lowerBound) }
                Slider(value: Binding(get: { value.wrappedValue }, set: set), in: range)
                    .tint(.blue)
                    .accessibilityLabel(title)
                    .accessibilityValue(Double(value.wrappedValue).formatted(.percent))
                volumeEndButton(maxIcon, label: "\(title) at maximum") { set(range.upperBound) }
            }
        }
    }

    private func volumeEndButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(Color.secondary)
                .frame(minWidth: 32, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func requestLeave() {
        confirmsLeave = true
    }

    private func startExport() {
        player?.pause()
        exportProgress = 0
        page = .exporting
        // With edited sound, or the background export still running, real progress fills the
        // border (see onChange of soundProgress and mergeProgress).
        if viewModel.isExportRunning {
            exportProgress = mergeProgress * saveRunUp
        } else if !viewModel.hasVolumeEdits {
            withAnimation(.easeOut(duration: saveRunUpDuration)) { exportProgress = saveRunUp }
        }
        Task { await viewModel.saveToPhotos() }
    }

    /// Leaving to keep the cover: its file must exist (the background export may still run) and
    /// carry the edited sound, so Home and the draft keep it.
    private func saveCoverThen(_ leave: @escaping () -> Void) {
        guard !viewModel.hasPlayableFile || viewModel.hasVolumeEdits else { return leave() }
        player?.pause()
        savingCover = true
        Task {
            do {
                _ = try await viewModel.waitForExport()
                try await viewModel.applyVolumeEdits()
                savingCover = false
                leave()
            } catch {
                savingCover = false
                soundSaveError = String(describing: error)
            }
        }
    }

    private func saveStateChanged(_ state: CompingViewModel.SaveState) {
        guard page == .exporting else { return }
        switch state {
        case .saved:
            withAnimation(.easeOut(duration: 0.3)) { exportProgress = 1 }
            Task {
                try? await Task.sleep(for: exportedAlertDelay)
                showsExported = true
            }
        case .denied, .failed:
            showsSaveError = true
        case .idle, .saving:
            break
        }
    }

    private var saveErrorMessage: String {
        switch viewModel.saveState {
        case .denied: "Allow access to Photos to save your cover."
        case .failed(let message): message
        default: ""
        }
    }

    // MARK: - Failed

    private func failed(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ErrorStateView(error: .exportFailed(details: message), actionTitle: "Try Again") {
                viewModel.exportInBackground()
            }
            Spacer()
            Button("Create New Cover", action: onStartOver)
                .buttonStyle(.appPrimary)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }
}

/// The small plum "Export" capsule of the top bar (Sketch "Primary Button").
private struct ExportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 45)
            .background(Capsule().fill(configuration.isPressed ? Color.primary800 : Color.primaryButton))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
    }
}

/// A percentage that counts along with its animation.
private struct AnimatedPercent: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(value, format: .percent.precision(.fractionLength(0)))
            .font(.title.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    let container = AppContainer.fakes()
    ExportPreviewView(
        viewModel: CompingViewModel(
            plan: DomainFixtures.compingPlan(),
            songName: "LANY - Stuck",
            useCase: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            videoLibrary: FakeVideoLibrarySaver()),
        onRetake: {},
        onStartOver: {})
}
#endif

//
//  ExportPreviewView.swift
//  finpro
//
//  Final result (PRD §5.9, Sketch 7.0–7.2): the cover being merged (7.0), its preview with the
//  clips used (7.1), and Export, which saves it to Photos with a progress border around the video
//  (7.2). Owner: Zildjian Vito (ZV-13).
//

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
    @State private var page = Page.preview
    @State private var confirmsLeave = false
    /// Shown progress of the save to Photos, which reports none: it runs ahead to `saveRunUp`
    /// while saving and completes when the save does.
    @State private var exportProgress: Double = 0
    @State private var showsExported = false
    @State private var showsSaveError = false
    let onRetake: () -> Void
    let onStartOver: () -> Void

    init(viewModel: CompingViewModel, onRetake: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onRetake = onRetake
        self.onStartOver = onStartOver
    }

    private let screenInset: CGFloat = 17
    private let topBarInset: CGFloat = 13
    private let videoMaxWidth: CGFloat = 280
    private let videoAspectRatio: CGFloat = 9.0 / 16.0
    private let videoCornerRadius: CGFloat = 12
    private let seekBarInset: CGFloat = 15
    private let seekBarBottom: CGFloat = 20
    private let timelineHeight: CGFloat = 2
    private let sheetCornerRadius: CGFloat = 12
    private let sheetTitleInset: CGFloat = 28
    private let clipsInset: CGFloat = 32
    private let clipWidth: CGFloat = 85
    private let clipHeight: CGFloat = 124
    private let clipSpacing: CGFloat = 12
    private let clipCornerRadius: CGFloat = 12
    private let selectedClipBorder: CGFloat = 4
    private let badgeInset: CGFloat = 4
    private let mergingIconSize: CGFloat = 64
    private let exportFrameWidth: CGFloat = 288
    private let exportFrameAspectRatio: CGFloat = 288.0 / 453.0
    private let exportVideoInset: CGFloat = 18
    private let exportBorderWidth: CGFloat = 10
    private let saveRunUp = 0.9
    private let saveRunUpDuration: TimeInterval = 1.6
    private let exportedAlertDelay: Duration = .milliseconds(350)

    var body: some View {
        Group {
            switch viewModel.exportState {
            case .failed(let message):
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
        .overlay { if isMerging { merging } }
        .animation(.default, value: page)
        .animation(.default, value: isMerging)
        .task { await viewModel.export() }
        .onChange(of: viewModel.exportedURL) { _, url in
            player = url.flatMap { viewModel.hasPlayableFile ? CoverPlayerController(url: $0) : nil }
        }
        .onChange(of: viewModel.saveState) { _, state in saveStateChanged(state) }
        .onDisappear { player?.pause() }
        .alert("Video Exported", isPresented: $showsExported) {
            Button("OK") { page = .preview }
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
    }

    // MARK: - 7.0 Merging

    private var isMerging: Bool {
        switch viewModel.exportState {
        case .idle, .exporting: true
        case .finished, .failed: false
        }
    }

    private var mergeProgress: Double {
        if case .exporting(let value) = viewModel.exportState { value } else { 0 }
    }

    private var merging: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "film.stack")
                    .font(.system(size: mergingIconSize))
                    .symbolEffect(.bounce, options: .repeat(.continuous))
                    .accessibilityHidden(true)
                Text("Merging your recording… \(mergeProgress.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
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
                    confirmsLeave = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.primary800)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Back")

                Spacer()

                Button("Export", action: startExport)
                    .buttonStyle(ExportButtonStyle())
                    .disabled(!viewModel.hasPlayableFile)
            }
            .padding(.horizontal, screenInset)
            .padding(.top, topBarInset)

            coverVideo
                .padding(.vertical, 16)
                .frame(maxHeight: .infinity)

            clipsSheet
        }
        .confirmationDialog("Leave this cover?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Record Again", action: onRetake)
            Button("Start Over", role: .destructive, action: onStartOver)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It hasn't been exported yet.")
        }
    }

    private var coverVideo: some View {
        Color.clear
            .aspectRatio(videoAspectRatio, contentMode: .fit)
            .frame(maxWidth: videoMaxWidth)
            .overlay { videoContent }
            .clipShape(.rect(cornerRadius: videoCornerRadius, style: .continuous))
            .overlay(alignment: .bottom) {
                if let player { seekBar(player) }
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
            }
            .foregroundStyle(.white)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.67))
                    Capsule().fill(.white)
                        .frame(width: proxy.size.width * player.progress)
                }
            }
            .frame(height: timelineHeight)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, seekBarInset)
        .padding(.bottom, seekBarBottom)
    }

    private var clipsSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clips")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryBrand)
                .padding(.horizontal, sheetTitleInset)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: clipSpacing) {
                    ForEach(viewModel.clips) { clip in
                        clipItem(clip)
                    }
                    if viewModel.canContinueRecording && !isMerging {
                        continueTile
                    }
                }
                .padding(.horizontal, clipsInset)
            }
            .scrollIndicators(.hidden)
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
        return VStack(spacing: 8) {
            Button {
                viewModel.selectClip(clip.id)
                player?.seek(to: clip.start)
            } label: {
                clipFrame(of: clip)
                    .frame(width: clipWidth, height: clipHeight)
                    .overlay {
                        // Retaking a clip comes later (needs several raw videos per cover).
                        if isSelected {
                            VStack(spacing: 0) {
                                Image(systemName: "arrow.trianglehead.counterclockwise")
                                    .font(.title3.weight(.semibold))
                                Text("Retake")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Color.secBrand)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if clip.needsRetake && !isMerging {
                            Text("Needs Retake")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.noteMiss))
                                .padding(.bottom, badgeInset)
                        }
                    }
                    .clipShape(.rect(cornerRadius: clipCornerRadius, style: .continuous))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: clipCornerRadius, style: .continuous)
                                .strokeBorder(Color.primaryDark, lineWidth: selectedClipBorder)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isMerging)

            if !isMerging {
                Text(viewModel.timeRange(of: clip))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: clipWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clip \(clip.id + 1), \(viewModel.timeRange(of: clip))\(clip.needsRetake ? ", needs retake" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Continue Recording: shown when the session ended early. The action comes later, with Retake.
    private var continueTile: some View {
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
                        .foregroundStyle(Color.primary800)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, screenInset)
            .padding(.top, topBarInset)

            VStack(spacing: 1) {
                Text("Exporting…")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Please don’t close the app or lock your screen.")
                    .font(.footnote)
            }
            .foregroundStyle(Color.primary800)
            .multilineTextAlignment(.center)
            .padding(.top, -12)
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

    private func startExport() {
        player?.pause()
        exportProgress = 0
        page = .exporting
        withAnimation(.easeOut(duration: saveRunUpDuration)) { exportProgress = saveRunUp }
        Task { await viewModel.saveToPhotos() }
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
                Task { await viewModel.export() }
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

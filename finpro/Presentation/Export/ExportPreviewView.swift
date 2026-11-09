//
//  ExportPreviewView.swift
//  finpro
//
//  Final result (PRD §5.9): merging progress, "your recording is complete", the cover preview with
//  the clips used, and Save to Photos. Owner: Zildjian Vito (ZV-13).
//

import AVKit
import SwiftUI
import UIKit

struct ExportPreviewView: View {
    private enum Page {
        /// The cover is ready; Preview Cover opens the player.
        case complete
        case preview
        /// Every clip of the cover.
        case clips
    }

    @State private var viewModel: CompingViewModel
    @State private var player: AVPlayer?
    @State private var page = Page.complete
    let onRetake: () -> Void
    let onStartOver: () -> Void

    init(viewModel: CompingViewModel, onRetake: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onRetake = onRetake
        self.onStartOver = onStartOver
    }

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    private let topBarHeight: CGFloat = 48
    private let cardCornerRadius: CGFloat = 16
    private let ringSize: CGFloat = 120
    private let ringLineWidth: CGFloat = 6
    private let completeIconSize: CGFloat = 72
    private let posterInset: CGFloat = 34
    private let posterAspectRatio: CGFloat = 1.36
    private let playButtonSize: CGFloat = 48
    private let previewInset: CGFloat = 36
    private let playerAspectRatio: CGFloat = 1.54
    private let clipsRowCount = 5
    private let clipGridInset: CGFloat = 44
    private let clipTileAspectRatio: CGFloat = 0.7
    private let clipTileSpacing: CGFloat = 8
    private let clipTileCornerRadius: CGFloat = 12
    private let selectedClipBorder: CGFloat = 3

    var body: some View {
        Group {
            switch viewModel.exportState {
            case .idle, .exporting:
                merging
            case .finished(let url):
                finished(url: url)
            case .failed(let message):
                failed(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.onboardingBackground.ignoresSafeArea())
        .animation(.default, value: page)
        .task { await viewModel.export() }
        .onChange(of: viewModel.exportedURL) { _, url in
            player = url.flatMap { viewModel.hasPlayableFile ? AVPlayer(url: $0) : nil }
        }
        .onDisappear { player?.pause() }
    }

    // MARK: - Merging

    private var progress: Double {
        if case .exporting(let value) = viewModel.exportState { value } else { 0 }
    }

    private var merging: some View {
        VStack(spacing: 0) {
            Text("Merging your recording..")
                .font(.headline)
                .foregroundStyle(Color.plumInk)

            Text("Bringing your recordings together into one seamless video cover")
                .font(.caption2)
                .foregroundStyle(Color.plumInkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
                .padding(.top, 6)

            ZStack {
                Circle()
                    .stroke(Color.ringTrack, lineWidth: ringLineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.plumNight, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.plumInk)
            }
            .frame(width: ringSize, height: ringSize)
            .padding(.top, 20)
            .animation(.easeInOut(duration: 0.3), value: progress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Merging progress")
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
        }
        .padding(.horizontal, buttonInset)
    }

    // MARK: - Finished

    @ViewBuilder
    private func finished(url: URL) -> some View {
        switch page {
        case .complete:
            complete
                .transition(.opacity)
        case .preview:
            preview
                .transition(.opacity)
        case .clips:
            clipsGrid
                .transition(.opacity)
        }
    }

    private var complete: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: completeIconSize, weight: .regular))
                .foregroundStyle(Color.plumInk)
                .accessibilityHidden(true)

            Text("Your recording is complete!")
                .font(.headline)
                .foregroundStyle(Color.plumInk)
                .padding(.top, 16)

            Text("We’re now combining your takes into one smooth cover.")
                .font(.caption2)
                .foregroundStyle(Color.plumInkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Button {
                page = .preview
            } label: {
                poster
            }
            .buttonStyle(.plain)
            .padding(.horizontal, posterInset)
            .padding(.top, 24)
            .accessibilityLabel("Preview cover")

            Spacer()

            Button("Preview Cover") { page = .preview }
                .buttonStyle(.primaryDeep)
                .padding(.horizontal, buttonInset)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, buttonInset)
    }

    /// A frame of the cover with a play button; a flat tile while there is no video file.
    private var poster: some View {
        Color.clear
            .aspectRatio(posterAspectRatio, contentMode: .fit)
            .overlay { clipFrame(of: viewModel.clips.first) }
            .clipShape(.rect(cornerRadius: cardCornerRadius))
            .overlay {
                Image(systemName: "play.fill")
                    .font(.body)
                    .foregroundStyle(Color.plumInk)
                    .frame(width: playButtonSize, height: playButtonSize)
                    .background(Circle().fill(.white.opacity(0.92)))
            }
    }

    /// The still frame of a clip, filling its space; a flat tile when there is none.
    @ViewBuilder
    private func clipFrame(of clip: CompingViewModel.Clip?) -> some View {
        if let clip, let image = viewModel.thumbnails[clip.id] {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Color.clipPlaceholder
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    player?.pause()
                    page = .complete
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.plumInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close preview")

                Text("Preview Cover")
                    .font(.headline)
                    .foregroundStyle(Color.plumInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .frame(minHeight: topBarHeight)
            .padding(.horizontal, buttonInset)

            ScrollView {
                VStack(spacing: 14) {
                    coverPlayer
                    titleCard
                    clipsCard
                }
                .padding(.horizontal, previewInset)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button {
                    Task { await viewModel.saveToPhotos() }
                } label: {
                    saveLabel
                }
                .buttonStyle(.primaryDeep)
                .disabled(viewModel.saveState == .saving || viewModel.saveState == .saved || !viewModel.hasPlayableFile)

                Button("Create New Cover", action: onStartOver)
                    .buttonStyle(.primaryMuted)

                saveMessage
            }
            .padding(.horizontal, buttonInset)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var coverPlayer: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ZStack {
                    Color.clipPlaceholder
                    ContentUnavailableView("No preview",
                                           systemImage: "film",
                                           description: Text("Running on fakes, so no video file was written."))
                        .foregroundStyle(Color.plumInk)
                }
            }
        }
        .aspectRatio(playerAspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cardCornerRadius))
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.noteHit)
                .lineLimit(1)
            Text(viewModel.subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous).fill(Color.guideFrame))
        .accessibilityElement(children: .combine)
    }

    private var clipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clip used")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.noteHit)
                Spacer()
                Button {
                    page = .clips
                } label: {
                    Label("See all", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.caption2)
                        .foregroundStyle(Color.noteHit)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
            }

            HStack(alignment: .top, spacing: clipTileSpacing) {
                // Always five slots wide, so a few clips keep the same tile size.
                ForEach(0..<clipsRowCount, id: \.self) { slot in
                    if slot < viewModel.clips.count {
                        let clip = viewModel.clips[slot]
                        VStack(spacing: 4) {
                            clipTile(clip, selectable: false)
                            Text(viewModel.timeRange(of: clip))
                                .font(.system(size: 8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous).fill(Color.guideFrame))
    }

    // MARK: - All clips

    private var clipsGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    page = .preview
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.plumInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(minHeight: topBarHeight)
            .padding(.horizontal, buttonInset)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clip used")
                        .font(.headline)
                        .foregroundStyle(Color.plumInk)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: clipTileSpacing), count: 3),
                              spacing: clipTileSpacing) {
                        ForEach(viewModel.clips) { clip in
                            clipTile(clip, selectable: true)
                        }
                    }
                }
                .padding(.horizontal, clipGridInset)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Retake cover", action: onRetake)
                .buttonStyle(.primaryDeep)
                .padding(.horizontal, buttonInset)
                .padding(.bottom, 8)
        }
    }

    /// One clip: a frame of it with a play mark; the chosen one has a dark border in the grid.
    private func clipTile(_ clip: CompingViewModel.Clip, selectable: Bool) -> some View {
        let isSelected = selectable && viewModel.selectedClipID == clip.id
        return Button {
            viewModel.selectClip(clip.id)
        } label: {
            Color.clear
                .aspectRatio(clipTileAspectRatio, contentMode: .fit)
                .overlay { clipFrame(of: clip) }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.plumInk)
                        .padding(8)
                }
                .clipShape(.rect(cornerRadius: clipTileCornerRadius))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: clipTileCornerRadius, style: .continuous)
                            .strokeBorder(Color.plumNight, lineWidth: selectedClipBorder)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityLabel("Clip \(clip.id + 1), \(viewModel.timeRange(of: clip))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .buttonStyle(.primaryMuted)
                .padding(.horizontal, buttonInset)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Save

    @ViewBuilder
    private var saveLabel: some View {
        switch viewModel.saveState {
        case .saving: Text("Saving…")
        case .saved: Label("Saved", systemImage: "checkmark")
        default: Text("Save Cover")
        }
    }

    @ViewBuilder
    private var saveMessage: some View {
        switch viewModel.saveState {
        case .denied:
            VStack(spacing: 4) {
                Text("Allow access to Photos to save your cover.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.plumInkSecondary)
        case .failed(let message):
            Text("Couldn't save: \(message)")
                .font(.footnote)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}

/// Title first, icon after it ("See all ›").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .font(.system(size: 8, weight: .semibold))
        }
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

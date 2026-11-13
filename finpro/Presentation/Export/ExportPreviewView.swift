//
//  ExportPreviewView.swift
//  finpro
//

import AVKit
import SwiftUI
import UIKit

/// Portrait playback and real exported clip thumbnails, matching the v2 preview screen.
struct ExportPreviewView: View {
    @State private var viewModel: CompingViewModel
    @State private var player: AVPlayer?
    let onRetake: () -> Void
    let onStartOver: () -> Void

    init(viewModel: CompingViewModel, onRetake: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onRetake = onRetake
        self.onStartOver = onStartOver
    }
    var body: some View {
        Group {
            switch viewModel.exportState {
            case .idle, .exporting:
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white).controlSize(.large).accessibilityLabel("Preparing cover")
                }
            case .finished:
                preview
            case .failed(let message):
                VStack(spacing: AppSpacing.large) {
                    ErrorStateView(error: .exportFailed(details: message), actionTitle: "Try Again") {
                        Task { await viewModel.export() }
                    }
                    Button("Create New Cover", action: onStartOver).buttonStyle(.appSecondary)
                }
                .padding(AppSpacing.large)
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .task {
            if viewModel.exportedURL == nil { await viewModel.export() }
            configurePlayer()
        }
        .onChange(of: viewModel.exportedURL) { _, _ in configurePlayer() }
        .onDisappear { player?.pause() }
    }
    private func configurePlayer() {
        guard let url = viewModel.exportedURL, viewModel.hasPlayableFile else { return }
        if let current = (player?.currentItem?.asset as? AVURLAsset)?.url, current == url { return }
        player = AVPlayer(url: url)
        player?.play()
    }
    private var preview: some View {
        GeometryReader { proxy in
            let videoHeight = max(180, min(proxy.size.height - 300, (proxy.size.width - 120) * 16 / 9))
            VStack(spacing: AppSpacing.regular) {
                HStack {
                    Button { player?.pause(); onStartOver() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.appIcon(.tinted)).accessibilityLabel("Back to covers")
                    Spacer()
                    Button { Task { await viewModel.saveToPhotos() } } label: {
                        Text(viewModel.saveState == .saved ? "Saved" : viewModel.saveState == .saving ? "Saving…" : "Export")
                            .font(.appHeadline).foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.large).padding(.vertical, AppSpacing.medium)
                            .background(Color.primaryButton, in: Capsule())
                    }
                    .disabled(!viewModel.hasPlayableFile || viewModel.saveState == .saving || viewModel.saveState == .saved)
                }
                .padding(.horizontal, AppSpacing.regular)
                Group {
                    if let player { VideoPlayer(player: player) }
                    else {
                        ErrorStateView(error: .exportFailed(details: "The exported video is unavailable. Please export again."),
                                       actionTitle: "Try Again") { Task { await viewModel.export() } }
                    }
                }
                .frame(width: videoHeight * 9 / 16, height: videoHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.tiny)

                saveFeedback
                Spacer(minLength: 0)
                clipStrip
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    private var clipStrip: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Clips").font(.appSubheadline.weight(.semibold)).foregroundStyle(Color.primaryBrand)
                .padding(.horizontal, AppSpacing.large)
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: AppSpacing.medium) {
                    ForEach(viewModel.clips) { clip in
                        VStack(spacing: AppSpacing.tiny) {
                            Button {
                                viewModel.selectClip(clip.id)
                                player?.seek(to: CMTime(seconds: clip.start, preferredTimescale: 600))
                                player?.play()
                            } label: {
                                Group {
                                    if let image = viewModel.thumbnails[clip.id] {
                                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                                    } else { Color.secondaryButton }
                                }
                                .frame(width: 88, height: 128).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppRadius.small)
                                        .strokeBorder(viewModel.selectedClipID == clip.id ? Color.primary800 : .clear, lineWidth: 3)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play clip \(clip.id + 1), \(viewModel.timeRange(of: clip))")
                            .accessibilityAddTraits(viewModel.selectedClipID == clip.id ? .isSelected : [])
                            Text(viewModel.timeRange(of: clip)).font(.appCaption2).foregroundStyle(Color.secondaryText)
                        }
                    }
                    Menu {
                        Button("Record another take", action: onRetake)
                        Button("Create a new cover", action: onStartOver)
                    } label: { Image(systemName: "plus") }
                    .buttonStyle(.appIcon(.primary))
                    .accessibilityLabel("Recording options")
                }
                .padding(.horizontal, AppSpacing.large)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, AppSpacing.medium)
        .background(Color.secondaryButton, in: UnevenRoundedRectangle(topLeadingRadius: AppRadius.small, topTrailingRadius: AppRadius.small))
    }
    @ViewBuilder private var saveFeedback: some View {
        switch viewModel.saveState {
        case .denied:
            Button("Allow Photos access in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.appCaption).foregroundStyle(Color.primaryBrand)
        case .failed(let message):
            Text(UserFacingError.exportFailed(details: message).message)
                .font(.appCaption).foregroundStyle(Color.primaryBrand)
        default: EmptyView()
        }
    }
}

//
//  ImportSongView.swift
//  finpro
//

import SwiftUI
import UniformTypeIdentifiers

/// Presented as a sheet above Covers or Song list.
struct ImportSongView: View {
    @State private var viewModel: ImportSongViewModel
    @State private var picking = false
    #if DEBUG
    /// `-importFile` opens once per app launch, not every time this sheet opens again.
    private static var openedLaunchFile = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    let onBack: () -> Void
    var isEditingSavedSong = false

    init(viewModel: ImportSongViewModel, onBack: @escaping () -> Void,
         isEditingSavedSong: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.onBack = onBack
        self.isEditingSavedSong = isEditingSavedSong
    }

    var body: some View {
        ZStack {
            Group {
                switch viewModel.status {
                case .idle, .loading: importPrompt.disabled(viewModel.status == .loading)
                case .trimming(let audio): sectionPicker(audio)
                case .preparing, .prepared:
                    if let audio = viewModel.selectionAudio { sectionPicker(audio).disabled(true) }
                case .failed(let error):
                    ErrorStateView(error: error, actionTitle: "Choose another song") {
                        viewModel.reset(); picking = true
                    }
                }
            }
            .padding(.horizontal, AppSpacing.large).padding(.top, AppSpacing.large).padding(.bottom, AppSpacing.large)
            if viewModel.isPreparing {
                Color.black.opacity(0.75).ignoresSafeArea()
                VStack(spacing: AppSpacing.regular) {
                    Image(systemName: "film.stack")
                        .font(.system(size: AppLayout.loadingIcon, weight: .regular))
                        .accessibilityHidden(true)
                    Text("Preparing your song… \(Int(((viewModel.preparationProgress?.fraction ?? 0) * 100).rounded()))%")
                        .font(.appHeadline).monospacedDigit()
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(.ultraThinMaterial)
        .interactiveDismissDisabled(viewModel.isPreparing)
        .presentationDetents(viewModel.isPreparing ? [.large] : [.height(sheetHeight), .large])
        .presentationDragIndicator(viewModel.isPreparing ? .hidden : .visible)
        .presentationCornerRadius(AppRadius.sheet)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .audio, .movie]) {
            viewModel.picked($0)
        }
        .task {
            viewModel.openInitialSong()
            #if DEBUG
            if !Self.openedLaunchFile, let url = DebugOptions.launchImportFile {
                Self.openedLaunchFile = true
                viewModel.picked(.success(url))
            }
            #endif
        }
        .onChange(of: viewModel.status) { _, status in
            if status == .prepared { viewModel.continueWithPreparedSong() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.stopSelectionPreview() }
        }
        .onDisappear { viewModel.suspend() }
    }

    private var importPrompt: some View {
        VStack(spacing: 0) {
            Text("Import Song").font(.appHeadline).foregroundStyle(Color.primaryBrand)
                .padding(.top, AppSpacing.tiny)
            // Design asset (Sketch "TestFlight UT" 4.1, "Music Symbol").
            Image("ImportMusicNotes").resizable().scaledToFit()
                .frame(width: 64, height: 68)
                .frame(width: 142, height: 142)
                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.medium))
                .padding(.top, AppSpacing.regular)
                .accessibilityHidden(true)
            Text("Select an audio file containing full vocals and instrumental. We'll use the vocals as your pitch reference.")
                .font(.appFootnote).foregroundStyle(Color.primaryBrand)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260)
                .padding(.top, AppSpacing.regular)
            Text("Supported formats: MP3, M4A, WAV")
                .font(.appCaption).foregroundStyle(Color.tertiaryText)
                .padding(.top, AppSpacing.small)
            Spacer(minLength: AppSpacing.large)
            Button("Choose File") { picking = true }.buttonStyle(.appPrimary)
        }
    }

    private var sheetHeight: CGFloat {
        if isEditingSavedSong { return AppLayout.songSectionSheetHeight }
        if case .idle = viewModel.status { return AppLayout.importSheetHeight }
        if case .loading = viewModel.status { return AppLayout.importSheetHeight }
        return AppLayout.clipSheetHeight
    }
    private func sectionPicker(_ audio: ImportedAudio) -> some View {
        VStack(spacing: AppSpacing.regular) {
            Text(isEditingSavedSong ? "Choose Song Section" : "Select Clip")
                .font(.appHeadline).foregroundStyle(Color.primaryBrand)
                .frame(maxWidth: .infinity, minHeight: AppLayout.iconButton)
                .overlay(alignment: .trailing) {
                    if isEditingSavedSong {
                        Button(action: viewModel.prepareSelection) { Image(systemName: "checkmark") }
                            .buttonStyle(.appIcon(.primary))
                            .accessibilityLabel("Use selected section and find key")
                    }
                }
            SongSectionLyrics(viewModel: viewModel)
            Spacer(minLength: AppSpacing.regular)
            SongSectionWaveform(viewModel: viewModel, audio: audio)
                .frame(height: isEditingSavedSong ? 72 : 86)
                // The waveform scrolls off the sheet's edges (design 4.3).
                .padding(.horizontal, -AppSpacing.large)
            HStack {
                Text("\(Int(viewModel.selectionLength.rounded()))s selected")
                Spacer()
                Text("\(time(viewModel.playbackTime ?? viewModel.selectionStart)) / \(time(audio.duration))")
            }
            .font(.appCaption).foregroundStyle(Color.primaryDark).monospacedDigit()
            if let error = viewModel.actionError {
                Label(error.title, systemImage: error.systemImage)
                    .font(.appCaption).foregroundStyle(Color.primaryBrand)
            }
            Spacer(minLength: AppSpacing.large)
            if !isEditingSavedSong {
                Button("Start Recording", action: viewModel.prepareSelection).buttonStyle(.appPrimary)
                Button("Save to Song List", action: viewModel.saveToSongList).buttonStyle(.appSecondary)
            }
        }
    }
    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}

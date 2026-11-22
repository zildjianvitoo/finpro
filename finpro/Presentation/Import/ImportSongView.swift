//
//  ImportSongView.swift
//  finpro
//

import SwiftUI
import UniformTypeIdentifiers

/// Presented as a sheet above Covers or Song list.
struct ImportSongView: View {
    @State private var viewModel: ImportSongViewModel
    /// The sheet's current size, kept while the song is prepared.
    @State private var detent: PresentationDetent = .height(AppLayout.importSheetHeight)
    @State private var picking = false
    #if DEBUG
    /// `-importFile` opens once per app launch, not every time this sheet opens again.
    private static var openedLaunchFile = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    let onBack: () -> Void

    init(viewModel: ImportSongViewModel, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onBack = onBack
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
            .padding(.horizontal, AppSpacing.large).padding(.top, AppSpacing.large).padding(.bottom, AppSpacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(.ultraThinMaterial)
        .interactiveDismissDisabled(viewModel.isPreparing)
        // While the song is prepared the sheet stays at the height it has (only resizing is locked).
        .presentationDetents(viewModel.isPreparing ? [detent] : [.height(sheetHeight), .large], selection: $detent)
        .onAppear { detent = .height(sheetHeight) }
        .onChange(of: sheetHeight) { _, height in
            if detent != .large { detent = .height(height) }
        }
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
        // The preparing screen covers the whole app (fading in); the sheet keeps its half height underneath.
        .crossDissolveCover(isPresented: viewModel.isPreparing) { preparingScreen }
        // Preparing a song can take a minute or more; locking would pause it.
        .keepsScreenAwake(viewModel.isPreparing)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.stopSelectionPreview()
                viewModel.pausePreseparation()
            } else {
                viewModel.resumePreseparationIfTrimming()
            }
        }
        .onDisappear { viewModel.suspend() }
    }

    private var preparingScreen: some View {
        // Design 4.3: the text close under the mascot, the pair a little above the middle.
        VStack(spacing: 0) {
            LoadingMascotView()
            // Redrawn a few times a second: the progress moves with time inside a step.
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                LoadingTextView(title: "Preparing your song…",
                                progress: ((viewModel.preparationProgress?.fraction ?? 0) * 100).rounded() / 100,
                                font: .appHeadline)
            }
        }
        .offset(y: -AppSpacing.regular)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .background(Color.loadingOverlay.opacity(AppLayout.loadingOverlayOpacityBusy).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var importPrompt: some View {
        VStack(spacing: 0) {
            Text("Import Song").font(.appHeadline).foregroundStyle(Color.plumNight)
                .padding(.top, AppSpacing.tiny)
            // Design asset (Sketch "TestFlight UT" 4.1, "Music Symbol").
            // Tinted as a template so it follows the brand colour (light and dark mode).
            Image("ImportMusicNotes").renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Color.primaryBrand)
                .frame(width: 64, height: 68)
                .frame(width: 142, height: 142)
                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.medium))
                .padding(.top, 24)
                .accessibilityHidden(true)
            Text("Select an audio file containing full vocals and instrumental. We'll use the vocals as your pitch reference.")
                .font(.appFootnote).foregroundStyle(Color.primaryBrand)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260)
                .padding(.top, 21)
            Text("Supported formats: MP3, M4A, WAV")
                .font(.appCaption).foregroundStyle(Color.tertiaryText)
                .padding(.top, AppSpacing.small)
            Spacer(minLength: AppSpacing.large)
            Button("Choose File") { picking = true }.buttonStyle(.appPrimary)
        }
    }

    private var sheetHeight: CGFloat {
        if case .idle = viewModel.status { return AppLayout.importSheetHeight }
        if case .loading = viewModel.status { return AppLayout.importSheetHeight }
        return AppLayout.clipSheetHeight
    }
    private func sectionPicker(_ audio: ImportedAudio) -> some View {
        VStack(spacing: AppSpacing.regular) {
            Text("Select Clip")
                .font(.appHeadline).foregroundStyle(Color.plumNight)
                .frame(maxWidth: .infinity, minHeight: AppLayout.iconButton)
            // Select Clip (design 4.4) keeps the lyrics close under the title.
            SongSectionLyrics(viewModel: viewModel, tint: .primaryBrand, dimmedOpacity: 0.5)
                .padding(.top, -15)
            Spacer(minLength: 0)
            SongSectionWaveform(viewModel: viewModel, audio: audio)
                .frame(height: 80)
                // The waveform scrolls off the sheet's edges (design 4.3).
                .padding(.horizontal, -AppSpacing.large)
            HStack {
                Text(viewModel.selectionLength < 60 ? "\(Int(viewModel.selectionLength.rounded()))s selected"
                     : "\(time(viewModel.selectionLength)) selected")
                Spacer()
                Text("\(time(viewModel.playbackTime ?? viewModel.selectionStart)) / \(time(audio.duration))")
            }
            .font(.appFootnote.weight(.medium)).foregroundStyle(Color.primaryBrand).monospacedDigit()
            .padding(.top, 11)
            // The sheet keeps its height: an error takes the gap above the buttons instead of adding a row.
            Group {
                if let error = viewModel.actionError {
                    Label(error.title, systemImage: error.systemImage)
                        .font(.appCaption).foregroundStyle(Color.primaryBrand)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppSpacing.large)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button("Start Recording", action: viewModel.prepareSelection).buttonStyle(.appPrimary)
                Button("Save to Song List", action: viewModel.saveToSongList).buttonStyle(.appSecondary)
            }
        }
    }
    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}

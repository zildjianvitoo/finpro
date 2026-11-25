//
//  ImportSongView.swift
//  finpro
//

import SwiftUI
import UniformTypeIdentifiers

/// Presented as a sheet above Covers or Song list.
struct ImportSongView: View {
    @State private var viewModel: ImportSongViewModel
    private enum ClipPreset: String, CaseIterable {
        case short = "15sec"
        case long = "60sec"
        case custom = "Custom"

        var duration: TimeInterval? {
            switch self {
            case .short: 15
            case .long: 60
            case .custom: nil
            }
        }
    }

    @State private var picking = false
    @State private var preset: ClipPreset = .custom
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
        Group {
            switch viewModel.status {
            case .idle, .loading:
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.24).ignoresSafeArea()
                        .onTapGesture(perform: onBack)
                        .accessibilityHidden(true)
                    VStack(spacing: AppSpacing.small) {
                        Capsule().fill(Color.secondary.opacity(0.35))
                            .frame(width: 36, height: 5)
                            .accessibilityHidden(true)
                        importPrompt.disabled(viewModel.status == .loading)
                    }
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.vertical, AppSpacing.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppLayout.importSheetHeight)
                    .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
                        if drag.translation.height > 48 && drag.translation.height > abs(drag.translation.width) {
                            onBack()
                        }
                    })
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: AppRadius.sheet, topTrailingRadius: AppRadius.sheet)
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            case .trimming(let audio):
                sectionPicker(audio)
            case .preparing, .prepared:
                if let audio = viewModel.selectionAudio { sectionPicker(audio).disabled(true) }
            case .failed(let error):
                ErrorStateView(error: error, actionTitle: "Choose another song") {
                    viewModel.reset(); picking = true
                }
                .padding(AppSpacing.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    backButton.padding(.leading, AppSpacing.regular)
                }
                .background(Color.screenBackground.ignoresSafeArea())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(.clear)
        .accessibilityAction(.escape) {
            if !viewModel.isPreparing { onBack() }
        }
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
        // Preparation covers the clip picker until Find Your Key is ready.
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
                // Only while the separation model finishes its first run (slow right after install).
                let firstSetup = viewModel.isWaitingForSeparationModel
                VStack(spacing: AppSpacing.tiny) {
                    LoadingTextView(title: firstSetup ? "Getting things ready…" : "Preparing your song…",
                                    progress: ((viewModel.preparationProgress?.fraction ?? 0) * 100).rounded() / 100,
                                    font: .appHeadline)
                    if firstSetup {
                        Text("This takes a little longer the first time.")
                            .font(.appCaption)
                            .opacity(0.8)
                    }
                }
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

    private var backButton: some View {
        Button(action: onBack) { Image(systemName: "chevron.left") }
            .buttonStyle(.appIcon(.glass)).accessibilityLabel("Close song import")
    }

    private func sectionPicker(_ audio: ImportedAudio) -> some View {
        VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }
            .padding(.horizontal, AppSpacing.regular)

            ViewThatFits(in: .vertical) {
                clipControls(audio)
                ScrollView { clipControls(audio) }
            }
            Spacer(minLength: AppSpacing.small)
            VStack(spacing: AppSpacing.small) {
                if let error = viewModel.actionError {
                    Label(error.title, systemImage: error.systemImage)
                        .font(.appCaption).foregroundStyle(Color.primaryBrand)
                }
                Button("Start Recording", action: viewModel.prepareSelection).buttonStyle(.appPrimary)
                Button("Save to Song List", action: viewModel.saveToSongList).buttonStyle(.appSecondary)
            }
            .padding(.horizontal, 25).padding(.bottom, 9)
        }
        .background(Color.screenBackground.ignoresSafeArea())
    }

    private func clipControls(_ audio: ImportedAudio) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Select Clip").font(.appLargeTitle).accessibilityAddTraits(.isHeader)
                Text("Scroll lyrics or drag waveform to choose your clip.").font(.appSubheadline)
            }
            .padding(.horizontal, AppSpacing.regular)
            .padding(.top, 15)

            SongSectionLyrics(viewModel: viewModel)
                .frame(height: 215)
                .background(Color.primary100, in: RoundedRectangle(cornerRadius: AppRadius.large))
                .padding(.horizontal, 25)
                .padding(.top, 25)

            HStack(spacing: AppSpacing.regular) {
                Text("Selected clip")
                Spacer()
                Text(clipTime(viewModel.selectionStart)).foregroundStyle(Color.secondaryText)
                Image(systemName: "arrow.right").foregroundStyle(Color.secondaryText)
                    .accessibilityHidden(true)
                Text(clipTime(viewModel.selectionStart + viewModel.selectionLength))
            }
            .font(.appSubheadline).monospacedDigit()
            .padding(.horizontal, 25)
            .padding(.top, 20)
            .accessibilityElement(children: .combine)

            SongSectionWaveform(viewModel: viewModel, audio: audio)
                .frame(height: 80)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Quick presets").font(.appSubheadline)
                HStack(spacing: 0) {
                    ForEach(ClipPreset.allCases, id: \.self) { option in
                        Button {
                            if let duration = option.duration {
                                viewModel.beginSelectionEditing()
                                viewModel.selectionStart = min(viewModel.selectionStart, audio.duration - duration)
                                viewModel.selectionLength = duration
                                viewModel.endSelectionEditing()
                            }
                            preset = option
                        } label: {
                            Text(option.rawValue)
                                .font(.appSubheadline)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(preset == option ? Color.white : Color.primary)
                                .background(preset == option ? Color.primaryButton : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled((option.duration ?? 0) > audio.duration)
                        .opacity((option.duration ?? 0) > audio.duration ? 0.4 : 1)
                        .accessibilityAddTraits(preset == option ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Color.primary100, in: Capsule())
                .shadow(color: .black.opacity(0.24), radius: 4, y: 4)
            }
            .padding(.horizontal, 25)
            .padding(.top, 22)
        }
        .onChange(of: viewModel.selectionLength) { _, length in
            if let duration = preset.duration, abs(length - duration) > 0.05 { preset = .custom }
        }
    }

    private func clipTime(_ seconds: TimeInterval) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + "s"
    }
}

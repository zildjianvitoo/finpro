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
        case short = "30sec"
        case long = "60sec"
        case custom = "Custom"

        var duration: TimeInterval? {
            switch self {
            case .short: 30
            case .long: ImportSongViewModel.defaultLength
            case .custom: nil
            }
        }
    }

    @State private var picking = false
    @State private var showsImportPrompt = false
    @State private var isDismissingPrompt = false
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var promptDragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let promptAnimation = Animation.easeOut(duration: 0.24)
    @State private var preset: ClipPreset = .long
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
            case .idle where viewModel.restoresClip:
                Color.screenBackground.ignoresSafeArea()
            case _ where isDismissingPrompt, .idle, .loading:
                ZStack(alignment: .bottom) {
                    Color.black.opacity(isDismissingPrompt ? 0 : 0.60).ignoresSafeArea()
                        .animation(nil, value: isDismissingPrompt)
                        .onTapGesture(perform: dismissImportPrompt)
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        Button(action: dismissImportPrompt) {
                            Capsule().fill(Color.secondary.opacity(0.35))
                                .frame(width: 60, height: 4)
                                .frame(width: 80, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss import sheet")
                        importPrompt.disabled(viewModel.status == .loading)
                    }
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.bottom, AppSpacing.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppLayout.importSheetHeight)
                    .background {
                        let corners = UnevenRoundedRectangle(topLeadingRadius: AppRadius.sheet, topTrailingRadius: AppRadius.sheet)
                        corners.fill(.ultraThinMaterial)
                            .overlay { corners.fill(Color.screenBackground.opacity(0.55)) }
                            .overlay { corners.strokeBorder(.white.opacity(0.4), lineWidth: 1) }
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(promptDismissDrag)
                    .offset(y: showsImportPrompt ? promptDragOffset : AppLayout.importSheetHeight + 64)
                    .allowsHitTesting(!isDismissingPrompt)
                    .task {
                        guard !showsImportPrompt, !isDismissingPrompt else { return }
                        await Task.yield()
                        guard !Task.isCancelled, !isDismissingPrompt else { return }
                        withAnimation(reduceMotion ? nil : promptAnimation) {
                            showsImportPrompt = true
                        }
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
        .edgeSwipeBack(isEnabled: !picking && !viewModel.isPreparing, action: onBack)
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

    private var promptDismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($promptDragOffset) { drag, offset, _ in
                if drag.translation.height > abs(drag.translation.width) {
                    offset = drag.translation.height
                }
            }
            .onEnded { drag in
                let down = drag.translation.height
                guard down > abs(drag.translation.width),
                      down > 48 || (down > 16 && drag.predictedEndTranslation.height > 80) else { return }
                dismissImportPrompt()
            }
    }

    private func dismissImportPrompt() {
        guard !isDismissingPrompt else { return }
        isDismissingPrompt = true
        withAnimation(reduceMotion ? nil : promptAnimation) {
            showsImportPrompt = false
        } completion: {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { onBack() }
        }
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
            Text("Import Song").font(.appHeadline).foregroundStyle(.primary)
                .padding(.top, AppSpacing.tiny)
            // Design asset (Sketch "TestFlight UT" 4.1, "Music Symbol").
            // Tinted as a template so it follows the brand colour (light and dark mode).
            Image("ImportMusicNotes").renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: 64, height: 68)
                .frame(width: 142, height: 142)
                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.medium))
                .padding(.top, 24)
                .accessibilityHidden(true)
            Text("Select an audio file containing full vocals and instrumental. We'll use the vocals as your pitch reference.")
                .font(.appFootnote).foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260)
                .padding(.top, 21)
            Text("Supported formats: MP3, M4A, WAV")
                .font(.caption2).foregroundStyle(.primary)
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
                Button("Start Recording", action: viewModel.prepareSelection)
                    .buttonStyle(AppButtonStyle(kind: .primary, height: 52))
                if !viewModel.openedSavedSong {
                    Button(action: viewModel.saveToSongList) {
                        Text("Save to Song List").foregroundStyle(.primary)
                    }
                    .buttonStyle(AppButtonStyle(kind: .secondary, height: 52))
                }
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
                .background(Color.primary100, in: RoundedRectangle(cornerRadius: AppRadius.large))
                .padding(.horizontal, 25)
                .padding(.top, 25)

            HStack(spacing: AppSpacing.regular) {
                Text("Selected clip")
                Spacer()
                Text(clipTime(viewModel.selectionLength))
            }
            .font(.appSubheadline).monospacedDigit()
            .padding(.leading, 25).padding(.trailing, 41)
            .padding(.top, 20)
            .accessibilityElement(children: .combine)

            SongSectionWaveform(viewModel: viewModel, audio: audio)
                .frame(height: 80)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 12) {
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
                                .frame(width: 100, height: 28)
                                .foregroundStyle(preset == option ? Color.white : Color.primary)
                                .background(preset == option ? Color.primaryButton : .clear, in: Capsule())
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled((option.duration ?? 0) > audio.duration)
                        .opacity((option.duration ?? 0) > audio.duration ? 0.4 : 1)
                        .accessibilityAddTraits(preset == option ? .isSelected : [])
                    }
                }
                .background(Color.primary100, in: Capsule())
            }
            .padding(.horizontal, 25)
            .padding(.top, 22)
        }
        .onAppear {
            preset = ClipPreset.allCases.first { $0.duration == viewModel.selectionLength } ?? .custom
        }
        .onChange(of: viewModel.selectionLength) { _, length in
            if let duration = preset.duration, abs(length - duration) > 0.05 { preset = .custom }
        }
    }

    private func clipTime(_ seconds: TimeInterval) -> String {
        seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX"))) + "s"
    }
}

//
//  RootView.swift
//  finpro
//
//  Shows the screen for the current AppFlow step. Owner: Zildjian Vito (ZV-04).
//  To plug in your screen, replace its placeholder below with your view
//  and call the matching AppFlow method when your step is done.
//  Keep the PermissionGate around it: permissions are handled here, not in feature screens.
//

import SwiftUI

struct RootView: View {
    let flow: AppFlow
    #if DEBUG
    @State private var showsDebugSettings = false
    @State private var opensSyncTest = false
    @State private var showsSyncTest = false
    #endif

    var body: some View {
        Group {
            switch flow.step {
            case .onboarding:
                OnboardingView(onFinish: flow.onboardingFinished)
            case .vocalRange:
                PermissionGate([.microphone], provider: flow.container.permissions) {
                    VocalRangeTestView(
                        viewModel: VocalRangeViewModel(
                            source: flow.container.livePitch,
                            repository: flow.container.vocalRange,
                            configuration: flow.container.configuration,
                            onSaved: flow.vocalRangeSaved),
                        routeMonitor: flow.container.audioRoute,
                        onDismiss: flow.dismissVocalRange)
                }
            case .home, .songList, .importSong:
                let showsSongList = flow.step == .songList || (flow.step == .importSong && flow.importOrigin == .songList)
                ZStack {
                    homeScreen
                        .accessibilityHidden(showsSongList)
                    if showsSongList {
                        songListScreen
                            .transition(.move(edge: .trailing))
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showsSongList)
            case .chooseKey:
                if let choices = flow.keyChoices {
                    KeySelectionView(viewModel: KeySelectionViewModel(
                        choices: choices, previewer: flow.container.audioPreview,
                        renderer: RenderSongKeyUseCase(transposition: flow.container.audioTransposition),
                        automaticallySelectRecommended: true, onChoose: flow.songPrepared), routeMonitor: flow.container.audioRoute,
                        onChooseAnother: flow.returnToSongSection, onRetest: flow.retestVocalRange)
                    .edgeSwipeBack(action: flow.returnToSongSection)
                }
            case .recording:
                PermissionGate([.camera, .microphone], provider: flow.container.permissions) {
                    if let song = flow.preparedSong {
                        RecordingView(viewModel: makeRecordingViewModel(song: song), tipsSongID: flow.selectedLibrarySongID)
                    }
                }
            case .export:
                if let plan = flow.compingPlan {
                    ExportPreviewView(viewModel: makeCompingViewModel(plan: plan), onRetake: flow.retakeCover,
                                      onStartOver: flow.startOver, onRetakeClip: flow.retakeClip(segment:),
                                      onContinue: flow.continueRecording,
                                      onSaveDraft: flow.saveCoverAsDraft, onDiscard: flow.discardCover,
                                      keepsCoverOnLeave: flow.isReopenedCover || flow.isCoverExported)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(get: { flow.step == .importSong }, set: { if !$0 { flow.closeImport() } })) {
            ImportSongView(viewModel: makeImportViewModel(), onBack: flow.closeImport,
                           isEditingSavedSong: flow.importEditsSavedSong && flow.selectedLibrarySong != nil)
        }
        .animation(.default, value: flow.step)
        #if DEBUG
        // Debug Settings has no button (the designed screens have none): launch with
        // `-startScreen debugSettings` to open it.
        .onAppear {
            if DebugOptions.launchScreen == "debugSettings" { showsDebugSettings = true }
        }
        .sheet(isPresented: $showsDebugSettings, onDismiss: {
            if opensSyncTest {
                opensSyncTest = false
                showsSyncTest = true
            }
        }) {
            DebugSettingsView(configuration: flow.container.configuration,
                              onSave: { flow.updateConfiguration($0) },
                              onRetestVocalRange: { flow.retestVocalRange() },
                              onMeasureSync: { opensSyncTest = true })
        }
        .fullScreenCover(isPresented: $showsSyncTest) {
            PermissionGate([.camera, .microphone], provider: flow.container.permissions) {
                SyncCalibrationView(viewModel: SyncCalibrationViewModel(
                    capture: flow.container.capture,
                    playback: flow.container.referencePlayback,
                    currentCalibration: flow.container.configuration.manualLatencyCalibration,
                    onApply: { value in
                        var configuration = flow.container.configuration
                        configuration.manualLatencyCalibration = value
                        flow.updateConfiguration(configuration)
                    }))
            }
        }
        #endif
    }

    private var homeScreen: some View {
        HomeView(viewModel: HomeViewModel(
            vocalRangeRepository: flow.container.vocalRange,
            songLibrary: flow.container.songLibrary, coverLibrary: flow.container.coverLibrary,
            onSongs: flow.openSongList, onOpenSong: flow.openSong, onOpenDraft: flow.openDraft,
            onCreateCover: flow.createNewCover,
            onRetestVocalRange: flow.retestVocalRange))
    }

    private var songListScreen: some View {
        SongListView(viewModel: SongListViewModel(library: flow.container.songLibrary,
                                                previewer: flow.container.audioPreview),
                     onBack: flow.openHome, onAdd: flow.createNewCover, onOpen: flow.openSong)
    }

    private func makeImportViewModel() -> ImportSongViewModel {
        let container = flow.container
        return ImportSongViewModel(
            inspector: container.audioInspector,
            lyrics: container.lyrics,
            recognizer: container.songRecognizer,
            previewer: container.audioPreview,
            prepare: PrepareSongUseCase(separation: container.stemSeparation,
                                        analysis: container.audioAnalysis,
                                        fallbackAnalysis: nil,
                                        transposition: container.audioTransposition,
                                        configuration: container.configuration,
                                        wordRecognition: container.wordRecognition),
            vocalRange: { container.vocalRange.load() },
            library: container.songLibrary, initialSong: flow.selectedLibrarySong,
            onSavedToList: flow.savedToSongList, onSelectionSaved: flow.sourceSongSaved,
            onPrepared: { flow.keysPrepared($0, lyrics: $1, songName: $2) })
    }

    private func makeRecordingViewModel(song: PreparedSong) -> RecordingViewModel {
        let container = flow.container
        return RecordingViewModel(
            song: song,
            capture: container.capture,
            playback: container.referencePlayback,
            routeMonitor: container.audioRoute,
            takeLog: container.takeLog,
            planner: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            configuration: container.configuration,
            allowsSpeaker: DebugOptions.allowsSpeakerRecording,
            lyrics: flow.recordingLyrics,
            pass: flow.recordingPass,
            onFinish: flow.sessionEnded,
            onDiscard: flow.sessionDiscarded)
    }

    private func makeCompingViewModel(plan: CompingCompositionPlan) -> CompingViewModel {
        let container = flow.container
        return CompingViewModel(
            plan: plan,
            songName: flow.songName,
            existingExport: flow.compingPlanExportURL,
            useCase: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            videoLibrary: container.videoLibrary,
            passThreshold: container.configuration.passThreshold,
            onExported: { flow.coverExported($0, plan: $1) },
            onSavedToPhotos: flow.coverSavedToPhotos,
            transposition: flow.preparedSong?.transposition,
            lyrics: flow.recordingLyrics)
    }
}

#if DEBUG
#Preview {
    RootView(flow: AppFlow(container: .fakes()))
}
#endif

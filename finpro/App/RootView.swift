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
                        onDismiss: flow.dismissVocalRange)
                }
            case .home, .songList, .importSong:
                if flow.step == .songList || (flow.step == .importSong && flow.importOrigin == .songList) {
                    songListScreen
                } else { homeScreen }
            case .chooseKey:
                if let choices = flow.keyChoices {
                    KeySelectionView(viewModel: KeySelectionViewModel(
                        choices: choices, previewer: flow.container.audioPreview,
                        renderer: RenderSongKeyUseCase(transposition: flow.container.audioTransposition),
                        automaticallySelectRecommended: true, onChoose: flow.songPrepared), routeMonitor: flow.container.audioRoute,
                        onChooseAnother: flow.returnToSongSection, onRetest: flow.retestVocalRange)
                }
            case .recording:
                PermissionGate([.camera, .microphone], provider: flow.container.permissions) {
                    if let song = flow.preparedSong {
                        RecordingView(viewModel: makeRecordingViewModel(song: song))
                    }
                }
            case .export:
                if let plan = flow.compingPlan {
                    ExportPreviewView(viewModel: makeCompingViewModel(plan: plan), onRetake: flow.retakeCover,
                                      onStartOver: flow.startOver, onRetakeClip: flow.retakeClip(segment:),
                                      onContinue: flow.continueRecording,
                                      onSaveDraft: flow.saveCoverAsDraft, onDiscard: flow.discardCover)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(get: { flow.step == .importSong }, set: { if !$0 { flow.closeImport() } })) {
            ImportSongView(viewModel: makeImportViewModel(), onBack: flow.closeImport,
                           isEditingSavedSong: flow.selectedLibrarySong != nil)
        }
        .animation(.default, value: flow.step)
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            // Debug builds only, and only on Home: the designed screens have no button for it.
            if flow.step == .home {
                Button("Debug Settings", systemImage: "slider.horizontal.3") {
                    showsDebugSettings = true
                }
                .labelStyle(.iconOnly)
                .padding()
            }
        }
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
            onSongs: flow.openSongList, onOpenSong: flow.openSong,
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
            previewer: container.audioPreview,
            prepare: PrepareSongUseCase(separation: container.stemSeparation,
                                        analysis: container.audioAnalysis,
                                        fallbackAnalysis: nil,
                                        transposition: container.audioTransposition,
                                        configuration: container.configuration),
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
            useCase: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            videoLibrary: container.videoLibrary,
            passThreshold: container.configuration.passThreshold,
            onExported: { flow.coverExported($0, plan: plan) })
    }
}

#if DEBUG
#Preview {
    RootView(flow: AppFlow(container: .fakes()))
}
#endif

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
import UIKit

struct RootView: View {
    let flow: AppFlow
    @State private var songListRevealProgress: CGFloat = 0
    @State private var vocalRangeRevealProgress: CGFloat = 0
    @State private var showsMicrophoneSettings = false
    #if DEBUG
    @State private var showsDebugSettings = false
    @State private var opensSyncTest = false
    @State private var showsSyncTest = false
    #endif

    var body: some View {
        Group {
            switch flow.step {
            case .onboarding, .vocalRange where flow.vocalRangeOrigin == .onboarding:
                let showsVocalRange = flow.step == .vocalRange
                ZStack {
                    OnboardingView(startsAtWelcome: showsVocalRange, onContinue: {
                        vocalRangeRevealProgress = 0
                        flow.startOnboardingVocalRange()
                    })
                    .hierarchicalUnderlay(isCovered: showsVocalRange, revealProgress: vocalRangeRevealProgress)
                    if showsVocalRange {
                        vocalRangeScreen
                            .transition(.move(edge: .trailing))
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showsVocalRange)
            case .home, .songList, .importSong, .vocalRange:
                let showsSongList = flow.step == .songList || (flow.step == .importSong && flow.importOrigin == .songList)
                let showsVocalRange = flow.step == .vocalRange
                ZStack {
                    homeScreen(isActive: !showsSongList && !showsVocalRange)
                        .hierarchicalUnderlay(
                            isCovered: showsSongList || showsVocalRange,
                            revealProgress: showsVocalRange ? (showsSongList ? 0 : vocalRangeRevealProgress) : (showsSongList ? songListRevealProgress : 0)
                        )
                    if showsSongList {
                        songListScreen(isActive: !showsVocalRange)
                            .hierarchicalUnderlay(isCovered: showsVocalRange, revealProgress: vocalRangeRevealProgress)
                            .transition(.move(edge: .trailing))
                            .zIndex(1)
                    }
                    if showsVocalRange {
                        vocalRangeScreen
                            .transition(.move(edge: .trailing))
                            .zIndex(2)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showsSongList)
                .animation(.easeInOut(duration: 0.3), value: showsVocalRange)
            case .chooseKey:
                if let choices = flow.keyChoices {
                    KeySelectionView(viewModel: KeySelectionViewModel(
                        choices: choices, previewer: flow.container.audioPreview,
                        renderer: RenderSongKeyUseCase(transposition: flow.container.audioTransposition),
                        automaticallySelectRecommended: true, onChoose: flow.songPrepared), routeMonitor: flow.container.audioRoute,
                        onChooseAnother: flow.returnToSongSection, onRetest: flow.retestVocalRange)
                }
            case .recording:
                PermissionGate([.camera, .microphone], provider: flow.container.permissions) { isGranted in
                    if let song = flow.preparedSong {
                        RecordingView(viewModel: makeRecordingViewModel(song: song),
                                      tipsSongID: flow.selectedLibrarySongID,
                                      isAuthorized: isGranted)
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
            ImportSongView(viewModel: makeImportViewModel(), onBack: flow.closeImport)
        }
        .animation(.default, value: flow.step)
        .alert(UserFacingError.permissionDenied([.microphone]).title, isPresented: $showsMicrophoneSettings) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(UserFacingError.permissionDenied([.microphone]).message)
        }
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

    private var vocalRangeScreen: some View {
        VocalRangeTestView(
            viewModel: VocalRangeViewModel(
                source: flow.container.livePitch,
                repository: flow.container.vocalRange,
                configuration: flow.container.configuration,
                onSaved: {
                    vocalRangeRevealProgress = 0
                    flow.vocalRangeSaved()
                }),
            routeMonitor: flow.container.audioRoute,
            onDismiss: {
                vocalRangeRevealProgress = 0
                flow.dismissVocalRange()
            },
            onDismissRevealProgress: { vocalRangeRevealProgress = $0 },
            authorizeMicrophone: authorizeVocalTestMicrophone)
    }

    private func authorizeVocalTestMicrophone() async -> Bool {
        let gate = PermissionGateModel(permissions: [.microphone], provider: flow.container.permissions)
        switch gate.state {
        case .granted: return true
        case .needsRequest:
            await gate.requestMissing()
            return gate.state == .granted
        case .denied:
            showsMicrophoneSettings = true
            return false
        case .checking: return false
        }
    }

    private func homeScreen(isActive: Bool) -> some View {
        HomeView(viewModel: HomeViewModel(
            vocalRangeRepository: flow.container.vocalRange,
            songLibrary: flow.container.songLibrary, coverLibrary: flow.container.coverLibrary,
            onSongs: {
                songListRevealProgress = 0
                flow.openSongList()
            }, onOpenSong: flow.openSong, onOpenDraft: flow.openDraft,
            onCreateCover: flow.createNewCover,
            onRetestVocalRange: {
                vocalRangeRevealProgress = 0
                flow.retestVocalRange()
            }),
            isActive: isActive,
            vocalRangeCompletionCount: flow.vocalRangeCompletionCount)
    }

    private func songListScreen(isActive: Bool) -> some View {
        SongListView(viewModel: SongListViewModel(library: flow.container.songLibrary,
                                                previewer: flow.container.audioPreview),
                     onBack: {
                         songListRevealProgress = 0
                         flow.openHome()
                     }, onAdd: flow.createNewCover, onOpen: flow.openSong,
                     isSwipeBackEnabled: isActive,
                     onSwipeProgress: { songListRevealProgress = $0 })
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
            lyrics: song.leadIn == nil ? flow.recordingLyrics.filter { $0.end > 0 } : flow.recordingLyrics,
            leadInNotes: song.leadIn == nil ? [] : (flow.keyChoices?.leadInGuideNotes ?? []),
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
            lyrics: flow.recordingLyrics.filter { $0.end > 0 })
    }
}

#if DEBUG
#Preview {
    RootView(flow: AppFlow(container: .fakes()))
}
#endif

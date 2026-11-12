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
            case .home:
                HomeView(viewModel: HomeViewModel(
                    vocalRangeRepository: flow.container.vocalRange,
                    onCreateCover: flow.createNewCover,
                    onRetestVocalRange: flow.retestVocalRange))
            case .importSong:
                VStack {
                    if let error = flow.preparationError { ErrorStateView(error: error) }
                    if flow.loadingDemo {
                        ProgressView("Preparing demo keys…")
                    } else {
                        ImportSongView(viewModel: makeImportViewModel(), onBack: flow.startOver) {
                            Task { await flow.loadDemoSong() }
                        }
                    }
                }
            case .chooseKey:
                if let choices = flow.keyChoices {
                    KeySelectionView(viewModel: KeySelectionViewModel(
                        choices: choices, previewer: flow.container.audioPreview,
                        onChoose: flow.songPrepared), routeMonitor: flow.container.audioRoute,
                        onChooseAnother: flow.startOver, onRetest: flow.retestVocalRange)
                }
            case .ready:
                if let song = flow.preparedSong {
                    ReadyView(song: song, lyrics: flow.recordingLyrics,
                              routeMonitor: flow.container.audioRoute,
                              allowsSpeaker: DebugOptions.allowsSpeakerRecording,
                              onRecord: flow.startRecording, onChooseAnother: flow.startOver,
                              onChangeKey: flow.changeKey)
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
                                      onStartOver: flow.startOver)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: flow.step)
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            // Debug builds only, and only on Home: the designed screens have no button there.
            if flow.step == .home {
                Button("Debug Settings", systemImage: "slider.horizontal.3") {
                    showsDebugSettings = true
                }
                .labelStyle(.iconOnly)
                .padding()
            }
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
            passThreshold: container.configuration.passThreshold)
    }
}

#if DEBUG
#Preview {
    RootView(flow: AppFlow(container: .fakes()))
}
#endif

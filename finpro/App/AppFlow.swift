//
//  AppFlow.swift
//  finpro
//
//  The app's linear flow and the data handed between steps. Owner: Zildjian Vito (ZV-04).
//  Screens call these methods instead of navigating themselves, so every handoff
//  goes through one place and is checked against the contracts.
//

import Foundation
import Observation

@Observable
final class AppFlow {
    enum Step: Equatable {
        case onboarding
        case vocalRange
        case home
        case importSong
        case chooseKey
        case ready
        case recording
        case export
    }

    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    let container: AppContainer
    private(set) var step: Step
    private(set) var preparedSong: PreparedSong?
    private(set) var keyChoices: PrepareSongUseCase.Choices?
    private(set) var preparationError: UserFacingError?
    private(set) var loadingDemo = false
    /// Stems of the chosen song before transposition (Ready screen, original key).
    var separatedStems: SeparatedStems? { keyChoices?.stems }
    private(set) var compingPlan: CompingCompositionPlan?
    /// Lyrics of the chosen part on the prepared song's timeline, for the recording screen.
    private(set) var recordingLyrics: [LyricLine] = []

    init(container: AppContainer) {
        self.container = container
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
        if !hasCompletedOnboarding {
            step = .onboarding
        } else {
            step = container.vocalRange.load() == nil ? .vocalRange : .home
        }
        #if DEBUG
        // `-startScreen` launch argument (DebugOptions): only steps that need no earlier data.
        switch DebugOptions.launchScreen {
        case "onboarding": step = .onboarding
        case "vocalRange": step = .vocalRange
        case "home": step = .home
        case "importSong": step = .importSong
        case "recording": step = .importSong // the demo song is prepared below, then recording starts
        default: break
        }
        #endif
        // Leftovers from a session that ended in a crash.
        SessionFiles.cleanUp()
        container.modelPrewarmer?.start()
        #if DEBUG
        if DebugOptions.launchScreen == "recording" {
            Task { await openRecordingWithDemoSong() }
        }
        #endif
    }

    #if DEBUG
    /// `-startScreen recording`: prepares the demo song, picks its first key and starts recording,
    /// so the recording screen can be checked without tapping through the flow.
    private func openRecordingWithDemoSong() async {
        await loadDemoSong()
        guard let song = keyChoices?.options.first?.song else { return }
        songPrepared(song)
        startRecording()
    }
    #endif

    /// User completed or skipped the onboarding walkthrough.
    func onboardingFinished() {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        step = container.vocalRange.load() == nil ? .vocalRange : .home
    }

    /// Replay onboarding (for testing or debugging).
    func replayOnboarding() {
        container.audioPreview.stop()
        step = .onboarding
    }

    /// Dismiss vocal range test back to previous step (Home if already tested, or Onboarding).
    func dismissVocalRange() {
        container.audioPreview.stop()
        step = container.vocalRange.load() == nil ? .onboarding : .home
    }

    /// Vocal range screen (Ikzaz) saved a range.
    func vocalRangeSaved() {
        step = .home
    }

    /// Home screen: user tapped Create New Cover.
    func createNewCover() {
        step = .importSong
    }

    /// Import/prep screen (Ikzaz) finished preparing a song.
    func songPrepared(_ song: PreparedSong) {
        Contract.assertValid(song.validate())
        preparedSong = song
        step = .ready
    }

    func changeKey() {
        guard keyChoices != nil else { return }
        container.audioPreview.stop()
        step = .chooseKey
    }

    func keysPrepared(_ choices: PrepareSongUseCase.Choices, lyrics: [LyricLine] = []) {
        recordingLyrics = lyrics
        choices.options.forEach { Contract.assertValid($0.song.validate()) }
        keyChoices = choices
        preparedSong = nil
        preparationError = nil
        step = .chooseKey
    }

    /// The demo uses its known melody, then follows the same key-choice flow as imports.
    func loadDemoSong() async {
        guard !loadingDemo, let range = container.vocalRange.load() else { return }
        loadingDemo = true
        preparationError = nil
        defer { loadingDemo = false }
        do {
            let demo = container.demo
            let stems = try await demo.separateStems(from: URL(fileURLWithPath: "/demo"), trimRange: 0...demo.duration)
            let prepare = PrepareSongUseCase(separation: demo, analysis: container.audioAnalysis,
                fallbackAnalysis: nil, transposition: container.audioTransposition, configuration: container.configuration)
            let choices = try await prepare.makeChoices(stems: stems, notes: demo.segments.flatMap(\.targetNotes),
                                                        duration: demo.duration, vocalRange: range)
            guard step == .importSong else { return }
            keysPrepared(choices)
        } catch {
            preparationError = .keyPreparationFailed
        }
    }

    /// Ready screen: user tapped Record. A new session starts, so files from the last one go (ZV-16).
    func startRecording() {
        guard let preparedSong else { return }
        // A key preview from the previous screens must not play over the recording.
        container.audioPreview.stop()
        #if DEBUG
        container.simulatedSinger?.prepare(song: preparedSong)
        #endif
        container.takeLog.clear()
        SessionFiles.cleanUp()
        try? SessionFiles.prepareDirectory()
        step = .recording
    }

    /// Recording screen (Takin) ended the session with at least one passed segment.
    func sessionEnded(with plan: CompingCompositionPlan) {
        Contract.assertValid(plan.validate())
        compingPlan = plan
        step = .export
    }

    /// Recording screen (Takin) ended with nothing passed, or the user discarded the session.
    func sessionDiscarded() {
        container.takeLog.clear()
        step = .ready
    }

    func startOver() {
        keyChoices = nil
        recordingLyrics = []
        preparationError = nil
        preparedSong = nil
        compingPlan = nil
        container.takeLog.clear()
        step = .home
    }

    func retestVocalRange() {
        container.audioPreview.stop()
        keyChoices = nil
        preparedSong = nil
        step = .vocalRange
    }

    /// Debug Settings saved new values (ZV-15). Takes effect the next time a value is read.
    func updateConfiguration(_ configuration: AppConfiguration, store: ConfigurationStore = ConfigurationStore()) {
        container.configuration = configuration
        store.save(configuration)
    }
}

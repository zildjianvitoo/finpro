//
//  AppFlow.swift
//  finpro
//
//  The app's linear flow and the data handed between steps. Owner: Zildjian Vito (ZV-04).
//  Screens call these methods instead of navigating themselves, so every handoff
//  goes through one place and is checked against the contracts.
//

import CoreMedia
import Foundation
import Observation

@Observable
final class AppFlow {
    enum Step: Equatable {
        case onboarding
        case vocalRange
        case home
        case songList
        case importSong
        case chooseKey
        case recording
        case export
    }

    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    let container: AppContainer
    private(set) var step: Step
    private(set) var importOrigin: Step = .home
    private(set) var selectedLibrarySongID: UUID?
    var selectedLibrarySong: SavedSong? { container.songLibrary.songs.first { $0.id == selectedLibrarySongID } }
    private(set) var preparedSong: PreparedSong?
    private(set) var keyChoices: PrepareSongUseCase.Choices?
    private(set) var preparationError: UserFacingError?
    private(set) var loadingDemo = false
    /// Stems of the chosen song before transposition (Ready screen, original key).
    var separatedStems: SeparatedStems? { keyChoices?.stems }
    private(set) var compingPlan: CompingCompositionPlan?
    /// What the recording screen records next: the session, or a retake / continue of the cover.
    private(set) var recordingPass = RecordingPass.session
    /// Lyrics of the chosen part on the prepared song's timeline, for the recording screen.
    private(set) var recordingLyrics: [LyricLine] = []
    /// "Artist - Title" of the imported song, for the final result screens (nil for the demo).
    private(set) var songName: String?
    /// The Home library entry of the cover being made, so a re-export after a retake or
    /// continue replaces it instead of adding a second one. Cleared when a new cover starts.
    private var savedCoverID: UUID?

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
        case "songList": step = .songList
        case "importSong": step = .importSong
        case "recording": step = .importSong // the demo song is prepared below, then recording starts
        case "export":
            // The fixture plan on the fakes container: the final result screens without recording.
            compingPlan = DomainFixtures.compingPlan()
            songName = "LANY - Stuck"
            step = .export
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
        importOrigin = step == .songList ? .songList : .home
        selectedLibrarySongID = nil
        step = .importSong
    }

    func openSongList() { step = .songList }
    func openHome() { container.audioPreview.stop(); step = .home }
    func openSong(_ song: SavedSong) {
        container.audioPreview.stop()
        importOrigin = step == .songList ? .songList : .home
        selectedLibrarySongID = song.id
        step = .importSong
    }
    func sourceSongSaved(_ id: UUID) { selectedLibrarySongID = id }
    func closeImport() {
        container.audioPreview.stop()
        guard step == .importSong else { return }
        step = importOrigin
    }
    func savedToSongList() { container.audioPreview.stop(); step = .songList }
    func returnToSongSection() { container.audioPreview.stop(); step = .importSong }


    /// Import/prep screen (Ikzaz) finished preparing a song.
    func songPrepared(_ song: PreparedSong) {
        Contract.assertValid(song.validate())
        preparedSong = song
        startRecording()
    }

    func changeKey() {
        guard keyChoices != nil else { return }
        container.audioPreview.stop()
        step = .chooseKey
    }

    func keysPrepared(_ choices: PrepareSongUseCase.Choices, lyrics: [LyricLine] = [], songName: String? = nil) {
        recordingLyrics = lyrics
        self.songName = songName
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
            #if DEBUG
            // The demo has no lyrics; placeholder lines let the lyrics settings be tried.
            keysPrepared(choices, lyrics: DummyLyricsProvider.placeholder(duration: demo.duration).lines)
            #else
            keysPrepared(choices)
            #endif
        } catch {
            preparationError = .keyPreparationFailed
        }
    }

    /// Ready screen: user tapped Record. A new session starts, so files from the last one go (ZV-16).
    func startRecording() {
        guard preparedSong != nil else { return }
        container.takeLog.clear()
        SessionFiles.cleanUp()
        try? SessionFiles.prepareDirectory()
        savedCoverID = nil
        // A new cover: its first recording locks the camera look again.
        (container.capture as? any CameraLookLocking)?.resetCameraLook()
        record(.session)
    }

    /// Final result screen: sing one clip again; its new take replaces the old one in the cover.
    func retakeClip(segment: Int) {
        guard let compingPlan else { return }
        // Line up with the end of the clip before it; for the first clip, the start of the one after.
        let frame = segment > 0 ? alignmentFrame(compingPlan, takeAt: segment - 1, atEnd: true)
            : alignmentFrame(compingPlan, takeAt: segment + 1, atEnd: false)
        record(RecordingPass(kind: .retake(segment: segment), earlierRawVideoURLs: compingPlan.rawVideoURLs,
                             alignmentFrame: frame))
    }

    /// Final result screen: the session ended early; sing on from the first segment not in the cover.
    func continueRecording() {
        guard let compingPlan, compingPlan.isPartial else { return }
        record(RecordingPass(kind: .continueFrom(segment: compingPlan.validTakes.count),
                             earlierRawVideoURLs: compingPlan.rawVideoURLs,
                             alignmentFrame: alignmentFrame(compingPlan, takeAt: compingPlan.validTakes.count - 1, atEnd: true)))
    }

    /// The frame where a take of the cover meets its neighbour (its handles excluded).
    private func alignmentFrame(_ plan: CompingCompositionPlan, takeAt position: Int, atEnd: Bool) -> RecordingPass.AlignmentFrame? {
        guard plan.validTakes.indices.contains(position) else { return nil }
        let take = plan.validTakes[position]
        guard plan.rawVideoURLs.indices.contains(take.recordingPass) else { return nil }
        let handle = plan.crossfadeDuration.seconds
        let time = atEnd ? take.videoTimeRange.end.seconds - handle : take.videoTimeRange.start.seconds + handle
        return RecordingPass.AlignmentFrame(videoURL: plan.rawVideoURLs[take.recordingPass], time: time)
    }

    /// Opens the recording screen for a pass. The take log and earlier raw videos are kept.
    private func record(_ pass: RecordingPass) {
        guard let preparedSong else { return }
        // A key preview from the previous screens must not play over the recording.
        container.audioPreview.stop()
        #if DEBUG
        container.simulatedSinger?.prepare(song: preparedSong)
        #endif
        recordingPass = pass
        step = .recording
    }

    /// Final result screen: the cover was exported; keep one Home library entry per cover.
    func coverExported(_ url: URL, plan: CompingCompositionPlan) {
        savedCoverID = container.coverLibrary.save(url, title: songName, duration: plan.endTime,
                                                   isDraft: plan.isPartial, replacing: savedCoverID) ?? savedCoverID
    }

    /// Recording screen (Takin) ended the session with at least one passed segment.
    func sessionEnded(with plan: CompingCompositionPlan) {
        Contract.assertValid(plan.validate())
        compingPlan = plan
        step = .export
    }

    /// Recording screen (Takin) ended with nothing passed, or the user discarded the session.
    /// A discarded retake or continue goes back to the cover as it was.
    func sessionDiscarded() {
        if !recordingPass.isSession, compingPlan != nil {
            step = .export
            return
        }
        container.takeLog.clear()
        step = keyChoices == nil ? .home : .chooseKey
    }

    /// Final result screen: record the same song again.
    func retakeCover() {
        compingPlan = nil
        startRecording()
    }

    func startOver() {
        songName = nil
        keyChoices = nil
        recordingLyrics = []
        preparationError = nil
        preparedSong = nil
        compingPlan = nil
        savedCoverID = nil
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

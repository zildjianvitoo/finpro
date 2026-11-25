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
import os

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

    enum VocalRangeOrigin: Equatable {
        case onboarding
        case home
    }

    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    let container: AppContainer
    private(set) var step: Step {
        didSet { if step != oldValue { Self.log.notice("step: \(String(describing: oldValue), privacy: .public) → \(String(describing: self.step), privacy: .public)") } }
    }
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Flow")
    private(set) var importOrigin: Step = .home
    private(set) var vocalRangeOrigin: VocalRangeOrigin = .onboarding
    /// Incremented whenever the user saves a vocal range, so Home can close its saved-result overlay.
    private(set) var vocalRangeCompletionCount = 0
    private(set) var selectedLibrarySongID: UUID?
    var selectedLibrarySong: SavedSong? { container.songLibrary.songs.first { $0.id == selectedLibrarySongID } }
    private(set) var preparedSong: PreparedSong?
    private(set) var keyChoices: PrepareSongUseCase.Choices?
    private(set) var preparationError: UserFacingError?
    private(set) var loadingDemo = false
    private(set) var compingPlan: CompingCompositionPlan? {
        didSet { compingPlanExportURL = nil }
    }
    /// The saved cover video made from exactly `compingPlan`, so the result screen can show it
    /// without merging the takes again (opening a draft, or coming back from a discarded retake).
    private(set) var compingPlanExportURL: URL?
    /// What the recording screen records next: the session, or a retake / continue of the cover.
    private(set) var recordingPass = RecordingPass.session
    /// Lyrics of the chosen part on the prepared song's timeline, for the recording screen.
    private(set) var recordingLyrics: [LyricLine] = []
    /// "Artist - Title" of the imported song, for the final result screens (nil for the demo).
    private(set) var songName: String?
    /// The Home library entry of the cover being made, so a re-export after a retake or
    /// continue replaces it instead of adding a second one. Cleared when a new cover starts.
    private var savedCoverID: UUID?
    /// The result screen shows a cover reopened from Home, not one just recorded: leaving it only
    /// asks whether to keep the sound changes. A new session's result clears it.
    private(set) var isReopenedCover = false
    /// The cover on the result screen was saved to Photos and has not changed since: it is
    /// finished on Home, so leaving keeps it finished instead of making it a draft again.
    private(set) var isCoverExported = false
    /// The last copy of the cover's working files to `CoverDraftStore`; later saves and deletes wait for it.
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var warmUpStarted = false

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
        // Leftovers from a session that ended in a crash, plus working files of deleted covers:
        // clean off the main thread so fresh launch paints its first frame immediately.
        let savedCoverIDs = Set(container.coverLibrary.covers.map(\.id))
        let drafts = container.coverDrafts
        draftSave = Task.detached(priority: .utility) {
            SessionFiles.cleanUp()
            drafts.deleteAll(except: savedCoverIDs)
        }
        #if DEBUG
        if DebugOptions.launchScreen == "recording" {
            Task { await openRecordingWithDemoSong() }
        }
        #endif
    }

    /// Starts CoreML and video encoder warm-up after the first frame (and splash) have painted,
    /// so fresh installs do not stall on a white launch screen competing with GPU/ANE/VideoToolbox.
    func startBackgroundWarmUp() {
        guard !warmUpStarted else { return }
        warmUpStarted = true
        container.modelPrewarmer?.start()
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

    /// The splash continues directly to the vocal test intro.
    func startOnboardingVocalRange() {
        vocalRangeOrigin = .onboarding
        step = .vocalRange
    }

    /// Replay onboarding (for testing or debugging).
    func replayOnboarding() {
        container.audioPreview.stop()
        vocalRangeOrigin = .onboarding
        step = .onboarding
    }

    /// Dismiss vocal range test back to previous step (Home if already tested, or Onboarding).
    func dismissVocalRange() {
        container.audioPreview.stop()
        step = vocalRangeOrigin == .onboarding ? .onboarding : .home
    }

    /// Vocal range screen (Ikzaz) saved a range.
    func vocalRangeSaved() {
        if vocalRangeOrigin == .onboarding {
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        }
        vocalRangeCompletionCount += 1
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
    /// The import sheet was dismissed. SwiftUI also calls this after the sheet closed because the
    /// flow moved on (e.g. to Find Your Key); the next screen's audio must keep playing then.
    func closeImport() {
        guard step == .importSong else { return }
        container.audioPreview.stop()
        step = importOrigin
    }
    func savedToSongList() { container.audioPreview.stop(); step = .songList }
    func returnToSongSection() {
        container.audioPreview.stop()
        step = .importSong
    }


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
        // The previous cover's draft may still be copying its raw videos out of the session
        // folder; clearing the folder before that ends would leave the draft incomplete.
        guard draftSave == nil else {
            let pending = draftSave
            draftSave = nil
            Task {
                await pending?.value
                startRecording()
            }
            return
        }
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
    /// Also keeps its working files (raw videos, song audio, takes), so it can be opened as a
    /// draft later, even after the app was closed without choosing Save to Draft.
    func coverExported(_ url: URL, plan: CompingCompositionPlan) {
        savedCoverID = container.coverLibrary.save(url, title: songName, duration: plan.endTime,
                                                   isDraft: plan.isPartial, replacing: savedCoverID) ?? savedCoverID
        compingPlanExportURL = savedCoverURL
        guard let id = savedCoverID, let preparedSong else { return }
        let draft = CoverDraft(song: preparedSong, plan: plan, attempts: container.takeLog.allAttempts(),
                               lyrics: recordingLyrics, songName: songName)
        let drafts = container.coverDrafts
        let previous = draftSave
        draftSave = Task {
            await previous?.value
            try? await drafts.save(draft, id: id)
        }
    }

    private var savedCoverURL: URL? {
        let library = container.coverLibrary
        return library.covers.first { $0.id == savedCoverID }.map(library.url(for:))
    }

    /// Home: a saved cover (draft or exported) was tapped. Opens it on the result screen with its
    /// takes, so it can be retaken, continued, remixed or exported again. False when its working
    /// files are gone (the caller falls back to playing the exported video).
    func openDraft(_ id: UUID) -> Bool {
        guard let draft = container.coverDrafts.load(id: id), draft.plan.validate().isEmpty,
              draft.song.validate().isEmpty else { return false }
        container.audioPreview.stop()
        container.takeLog.clear()
        draft.attempts.forEach(container.takeLog.logAttempt)
        keyChoices = nil
        preparationError = nil
        preparedSong = draft.song
        recordingLyrics = draft.lyrics
        songName = draft.songName
        compingPlan = draft.plan
        recordingPass = .session
        savedCoverID = id
        // The draft's plan is the one its saved video was exported from.
        compingPlanExportURL = savedCoverURL
        isReopenedCover = true
        step = .export
        return true
    }

    /// Final result screen: the cover was saved to Photos, so it counts as finished on Home.
    func coverSavedToPhotos() {
        if let savedCoverID { container.coverLibrary.markFinished(savedCoverID) }
        isCoverExported = true
    }

    /// Final result screen, leave dialog: keep the cover on Home as a draft, then go home.
    /// A cover already saved to Photos stays finished.
    func saveCoverAsDraft() {
        if let savedCoverID, !isCoverExported { container.coverLibrary.markDraft(savedCoverID) }
        startOver()
    }

    /// Final result screen, leave dialog: remove the cover and its working files, then go home.
    func discardCover() {
        if let id = savedCoverID {
            container.coverLibrary.delete(id)
            let drafts = container.coverDrafts
            let previous = draftSave
            draftSave = Task {
                await previous?.value
                drafts.delete(id: id)
            }
        }
        startOver()
    }

    /// Recording screen (Takin) ended the session with at least one passed segment.
    func sessionEnded(with plan: CompingCompositionPlan) {
        Contract.assertValid(plan.validate())
        compingPlan = plan
        isReopenedCover = false
        // A retake or continue changed the cover after it was saved to Photos.
        isCoverExported = false
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
        isReopenedCover = false
        isCoverExported = false
        container.takeLog.clear()
        step = .home
    }

    func retestVocalRange() {
        container.audioPreview.stop()
        keyChoices = nil
        preparedSong = nil
        vocalRangeOrigin = .home
        step = .vocalRange
    }

    /// Debug Settings saved new values (ZV-15). Takes effect the next time a value is read.
    func updateConfiguration(_ configuration: AppConfiguration, store: ConfigurationStore = ConfigurationStore()) {
        container.configuration = configuration
        store.save(configuration)
    }
}

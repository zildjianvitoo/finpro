//
//  RecordingViewModel.swift
//  finpro
//
//  Runs one recording session (PRD §5.5–5.8): the camera keeps recording while the loop
//  plays, evaluates, rewinds and continues; at the end the passed takes become a
//  CompingCompositionPlan. Every cut point comes from the capture clock (PRD §7.1).
//

import CoreMedia
import Foundation
import os
import Observation

@Observable
final class RecordingViewModel {
    enum Status: Equatable {
        case starting
        /// Camera and song are ready; recording starts when the user confirms the tips.
        case ready
        case recording
        /// Finalizing the raw video file.
        case finishing
        /// Could not start; the user can fix the cause and retry.
        case blocked(UserFacingError)
        /// Stopped by a call, another app, unplugged earphones or a limit; the file is finalized.
        case interrupted(UserFacingError)
        case failed(UserFacingError)
    }

    /// The lime dot on the pitch guide: the smoothed voice pitch and when it was last heard.
    struct VoiceDot: Equatable {
        let midi: Float
        let songTime: TimeInterval
    }

    /// One point of the user's pitch trail on the song timeline.
    struct TrailPoint {
        let songTime: TimeInterval
        let midi: Float?
        let isHit: Bool
    }

    struct PitchStats: Equatable {
        var samplesPerSecond = 0
        var voicedPercent = 0
        var lastNote: String?
        var lastLevelDB: Float = -.infinity
    }

    /// PRD §5.8: required free space before Record, and the floor that stops a running session.
    static let requiredStorageBytes: Int64 = 1_500_000_000
    static let reserveStorageBytes: Int64 = 128_000_000
    private static let storageCheckInterval: TimeInterval = 5
    private static let tickInterval: Duration = .milliseconds(20)
    /// How long to wait for the first video frame before giving up.
    private static let firstFrameTimeout: TimeInterval = 3
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Capture")
    /// While held, the segment start sits this far behind the playhead (the roll's past window).
    private static let heldSegmentLead: TimeInterval = 1
    /// Enough trail for the piano roll's past window.
    private static let trailLength: TimeInterval = 2

    private(set) var referenceVocalEnabled = true
    private var karaoke: ConfigureReferenceVocalUseCase {
        ConfigureReferenceVocalUseCase(playback: playback as? any ReferenceVocalPlayback)
    }
    var supportsReferenceVocal: Bool { karaoke.isAvailable }
    func setReferenceVocalEnabled(_ enabled: Bool) {
        referenceVocalEnabled = enabled
        karaoke.execute(enabled: enabled)
    }

    let song: PreparedSong
    /// The session, a retake of one clip, or continuing the song.
    let pass: RecordingPass
    /// Synced lyrics on the song timeline (empty when none were found).
    let lyrics: [LyricLine]
    /// The word drawn under each guide note; built once, the guide redraws with every pitch sample.
    @ObservationIgnored private(set) lazy var wordLabels: [UUID: String] = {
        let plan = song.transposition
        let notes = song.segments.flatMap(\.targetNotes).map {
            PianoRollView.Note(id: $0.id, midi: plan.transposed($0), start: $0.startTime, end: $0.endTime)
        }
        return GuideWordLabels.make(words: lyrics.flatMap(\.words), notes: notes)
    }()
    private(set) var status: Status = .starting
    private(set) var loop: LoopStateController
    private(set) var trail: [TrailPoint] = []
    /// Display only (see VoiceDotFilter); colours and scores use the raw samples.
    private(set) var voiceDot: VoiceDot?
    /// How each guide note was sung so far, for its colour (see NoteTally; display only).
    private(set) var noteTallies: [UUID: NoteTally] = [:]
    /// Feeds the live pitch into `noteTallies` (timing grace, glitch filter; see NoteColoring).
    @ObservationIgnored private var noteColoring = NoteColoring(notes: [])
    @ObservationIgnored private var loggedNoteIDs: Set<UUID> = []
    @ObservationIgnored private var guideNotes: [NoteColoring.GuideNote] = []
    /// Singing time shown by the timer (see `elapsedRecordingTime`), and the tick it was last
    /// brought up to date (nil outside singing).
    @ObservationIgnored private var singingTime: TimeInterval = 0
    @ObservationIgnored private var lastTimerTick: TimeInterval?
    @ObservationIgnored private var voiceDotFilter = VoiceDotFilter()
    /// Song time at which the part being sung starts (the segment a start or a resume began with);
    /// notes before it are previous material.
    private(set) var singingFrom: TimeInterval?
    private(set) var route: AudioOutputRoute
    /// Debug readout: pitch samples in the last second, how many were voiced, and the last note.
    private(set) var pitchStats = PitchStats()
    private(set) var microphoneName: String?
    /// The camera is configured, so its preview can be shown (also while recording starts).
    private(set) var isCameraReady = false
    /// Retake / continue: the neighbouring clip's frame to line up with (see `RecordingPass.alignmentFrame`).
    private(set) var alignmentImage: CGImage?

    @ObservationIgnored private let capture: any CaptureRepository
    @ObservationIgnored private let playback: any ReferencePlaybackRepository
    @ObservationIgnored private let routeMonitor: any AudioRouteMonitor
    @ObservationIgnored private let takeLog: any SessionTakeLogRepository
    @ObservationIgnored private let planner: AutoCompingVideoUseCase
    @ObservationIgnored private let configuration: AppConfiguration
    @ObservationIgnored private let onFinish: (CompingCompositionPlan) -> Void
    @ObservationIgnored private let onDiscard: () -> Void
    @ObservationIgnored private let allowsSpeaker: Bool
    @ObservationIgnored private let frames: any ClipThumbnailProviding

    /// Capture-clock time at which song time 0 is heard. Set on every playback start.
    @ObservationIgnored private var anchor: CMTime?
    /// Pitch evaluations since the current playback started, in song time.
    @ObservationIgnored private var evaluations: [PitchEvaluation] = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var sessionStart: TimeInterval = 0
    @ObservationIgnored private var lastStorageCheck: TimeInterval = 0
    @ObservationIgnored private var rawVideoURL: URL?
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var recentSamples: [(time: TimeInterval, voiced: Bool)] = []
    @ObservationIgnored private var trailDisplay: StabilizePitchDisplayUseCase
    @ObservationIgnored private var noteDisplay: StabilizePitchDisplayUseCase
    @ObservationIgnored private var displayTargetID: UUID?

    init(song: PreparedSong,
         capture: any CaptureRepository,
         playback: any ReferencePlaybackRepository,
         routeMonitor: any AudioRouteMonitor,
         takeLog: any SessionTakeLogRepository,
         planner: AutoCompingVideoUseCase,
         configuration: AppConfiguration,
         allowsSpeaker: Bool = false,
         lyrics: [LyricLine] = [],
         pass: RecordingPass = .session,
         frames: any ClipThumbnailProviding = AVClipThumbnailProvider(),
         onFinish: @escaping (CompingCompositionPlan) -> Void,
         onDiscard: @escaping () -> Void) {
        self.song = song
        self.pass = pass
        self.frames = frames
        self.lyrics = lyrics
        self.capture = capture
        self.playback = playback
        self.routeMonitor = routeMonitor
        self.takeLog = takeLog
        self.planner = planner
        self.configuration = configuration
        self.onFinish = onFinish
        self.onDiscard = onDiscard
        self.allowsSpeaker = allowsSpeaker
        trailDisplay = StabilizePitchDisplayUseCase(configuration: configuration)
        noteDisplay = StabilizePitchDisplayUseCase(configuration: configuration)
        guideNotes = song.segments.flatMap(\.targetNotes).map {
            NoteColoring.GuideNote(id: $0.id, start: $0.startTime, end: $0.endTime, midi: Float(song.transposition.transposed($0)))
        }
        noteColoring = NoteColoring(notes: guideNotes)
        loop = LoopStateController(segments: song.segments, configuration: configuration,
                                   range: pass.segmentRange(segmentCount: song.segments.count))
        route = routeMonitor.currentRoute
    }

    // MARK: - What the screen shows

    var previewSource: (any CameraPreviewSource)? { capture as? any CameraPreviewSource }
    var segmentCount: Int { song.segments.count }
    /// Segments sung to the end; they go into the cover.
    var completedCount: Int { loop.completedCount }
    var showsBluetoothWarning: Bool { route == .bluetooth }
    /// Debug speaker test: recording on the loudspeaker is allowed and flagged on screen.
    var isSpeakerTest: Bool { route == .speaker && allowsSpeaker }

    /// "Segment 3 / 7" (index + 1 for display).
    var progressTitle: String {
        let segment = min(loop.segmentIndex, segmentCount - 1) + 1
        return "Segment \(segment) / \(segmentCount)"
    }

    /// Song time now, from the capture clock; nil before playback started.
    func currentSongTime() -> TimeInterval? {
        anchor.map { (capture.currentCaptureTime() - $0).seconds }
    }

    /// Time until the current segment's first note is heard (pre-roll count), nil before playback.
    func secondsToSegmentStart() -> TimeInterval? {
        guard let start = loop.currentSegment?.audioStartTime, let now = currentSongTime() else { return nil }
        return start - now
    }

    /// What the piano roll shows: live song time while singing; during the countdown and a pause
    /// it holds on the start of the segment that will be sung.
    func displaySongTime() -> TimeInterval? {
        switch loop.phase {
        case .countdown, .paused:
            loop.currentSegment.map { $0.audioStartTime + Self.heldSegmentLead }
        default:
            currentSongTime()
        }
    }

    /// Share of the song sung so far, 0...1, for the ring of the record button. It stays at the
    /// start of the current segment during the countdown, the pre-roll and a pause.
    func songProgress() -> Double {
        let duration = max(song.duration, 0.001)
        let segmentStart = loop.currentSegment?.audioStartTime ?? 0
        let time: TimeInterval
        switch loop.phase {
        case .idle: time = 0
        case .countdown, .preRoll, .paused: time = segmentStart
        case .singing: time = currentSongTime() ?? segmentStart
        case .ended: time = duration
        }
        return min(max(time / duration, 0), 1)
    }

    /// Share of the song at which each segment after the first starts.
    var segmentBoundaries: [Double] {
        let duration = max(song.duration, 0.001)
        return song.segments.dropFirst().map { $0.audioStartTime / duration }
    }

    var isPaused: Bool { loop.phase == .paused }

    /// The alignment frame shows until the first note of this pass is played.
    var showsAlignmentGuide: Bool {
        guard alignmentImage != nil, singingFrom == nil else { return false }
        switch status {
        case .starting, .ready, .recording: return true
        default: return false
        }
    }
    /// This pass sang something that goes into the cover: a finished segment of the session, or a
    /// take of this retake or continue that was not deleted.
    var hasNewTakes: Bool {
        if pass.isSession { return completedCount > 0 }
        let latest = Dictionary(grouping: takeLog.allAttempts(), by: \.segmentIndex).compactMapValues(\.last)
        return latest.values.contains { $0.recordingPass == pass.index && $0.status != .failed }
    }
    /// A retake sings one clip, so there is no earlier segment of this pass to delete.
    var canDeleteSegment: Bool {
        if case .retake = pass.kind { false } else { true }
    }
    var canPause: Bool { status == .recording && (loop.canPause || isPaused) }

    /// Time spent singing, on the capture clock (display only; cuts never use it). It starts when
    /// a countdown ends and stands still during countdowns and pauses: the camera already runs then
    /// (one continuous raw file), but those moments are never part of the cover.
    func elapsedRecordingTime() -> TimeInterval {
        guard status == .recording || status == .finishing else { return 0 }
        guard isSingingPhase, let lastTimerTick else { return singingTime }
        return singingTime + max(0, capture.currentCaptureTime().seconds - lastTimerTick)
    }

    private var isSingingPhase: Bool { loop.phase == .preRoll || loop.phase == .singing }

    // MARK: - Session

    /// Prepares the camera and the song, then waits in `.ready` for `beginRecording()`.
    func start() async {
        guard status == .starting || isBlocked else { return }
        status = .starting
        route = routeMonitor.currentRoute
        guard route.allowsRecording || allowsSpeaker else {
            status = .blocked(.speakerOutput)
            return
        }
        guard SessionFiles.availableCapacity() >= Self.requiredStorageBytes else {
            status = .blocked(.lowStorage(requiredGB: Double(Self.requiredStorageBytes) / 1_000_000_000))
            return
        }
        do {
            try await capture.prepare()
            isCameraReady = true
            await loadAlignmentImage()
            microphoneName = (capture as? any MicrophoneInputProviding)?.microphoneName
            if karaoke.isAvailable {
                try karaoke.load(song: song)
                karaoke.execute(enabled: referenceVocalEnabled)
            } else {
                try playback.load(earphoneMixURL: song.earphoneMixURL)
            }
            // The song before the selected part plays in the pre-roll before 0; without it, silence.
            try? playback.loadLeadIn(mixURL: song.leadIn?.mixURL, instrumentalURL: song.leadIn?.instrumentalURL)
            guard status == .starting else { return }
            status = .ready
        } catch {
            guard status == .starting else { return }
            if let inputError = error as? any UserFacingConvertible {
                status = .blocked(inputError.userFacingError)
            } else {
                status = .failed(.recordingFailed(details: error.localizedDescription))
            }
        }
    }

    private func loadAlignmentImage() async {
        guard alignmentImage == nil, let frame = pass.alignmentFrame else { return }
        alignmentImage = await frames.thumbnails(for: frame.videoURL, at: [frame.time]).first ?? nil
    }

    /// Starts the camera recording and the loop, after the user confirmed the tips.
    func beginRecording() async {
        guard status == .ready else { return }
        status = .starting
        route = routeMonitor.currentRoute
        guard route.allowsRecording || allowsSpeaker else {
            status = .blocked(.speakerOutput)
            return
        }
        do {
            observe()
            try await capture.startRecording()
            isCapturing = true
            // The file starts at the first video frame; playing before it exists would put the
            // first take's handle before the start of the file.
            do {
                try await waitForFirstFrame()
            } catch RecordingError.noVideoFrames {
                Self.log.error("no video frame within \(Self.firstFrameTimeout) s; preparing the camera again")
                // A cold camera (first run after install) can stop before its first frame; a
                // second prepare() starts it again, as leaving and reopening the screen did.
                isCapturing = false
                _ = try? await capture.stopRecording()
                guard status == .starting else { return }
                try await capture.prepare()
                try await capture.startRecording()
                isCapturing = true
                try await waitForFirstFrame()
            }
            guard status == .starting else { return }
            sessionStart = capture.currentCaptureTime().seconds
            lastStorageCheck = sessionStart
            singingTime = 0
            lastTimerTick = nil
            status = .recording
            perform(loop.begin(now: capture.currentCaptureTime().seconds))
            startTicking()
        } catch {
            guard status == .starting else { return }
            stopObserving()
            if let inputError = error as? any UserFacingConvertible {
                status = .blocked(inputError.userFacingError)
            } else {
                status = .failed(.recordingFailed(details: error.localizedDescription))
            }
        }
    }

    private func waitForFirstFrame() async throws {
        // A real-time timeout: the capture clock stops when the camera session does, and the
        // wait never ended (the record button stayed disabled).
        let deadline = ContinuousClock.now + .seconds(Self.firstFrameTimeout)
        while capture.fileTime(forCaptureTime: capture.currentCaptureTime()) == nil {
            guard ContinuousClock.now < deadline else {
                throw RecordingError.noVideoFrames
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private enum RecordingError: LocalizedError {
        case noVideoFrames
        var errorDescription: String? { "The camera didn't deliver any video. Close other camera apps and try again." }
    }

    /// Pauses the song and the scoring; the camera keeps running, but nothing recorded while
    /// paused is used, because only logged takes reach the cover.
    func pause() {
        guard status == .recording, loop.canPause else { return }
        perform(loop.pause())
        anchor = nil
        evaluations = []
        trail = []
        resetVoiceDot()
    }

    /// Resumes with a countdown and restarts the current segment.
    func resume() {
        guard status == .recording, isPaused else { return }
        perform(loop.resume(now: capture.currentCaptureTime().seconds))
    }

    /// Deletes the last finished segment and goes back to sing it again after the countdown (the
    /// current one when none is finished). Capture keeps running; the deleted take stays in the
    /// raw video but is marked as removed in the take log, so it never reaches the cover.
    func deleteLastSegment() {
        // Not once the last segment is done: the session is already finishing.
        guard status == .recording, canDeleteSegment, loop.canPause || isPaused else { return }
        let target = max(loop.range.lowerBound, loop.segmentIndex - 1)
        if loop.segmentIndex > loop.range.lowerBound,
           let removed = takeLog.allAttempts().last(where: { $0.segmentIndex == target }), removed.status != .failed {
            takeLog.logAttempt(TakeAttemptLog(
                segmentIndex: target,
                attemptNumber: removed.attemptNumber + 1,
                recordingPass: pass.index,
                videoTimeRange: removed.videoTimeRange,
                accuracyScore: 0,
                missedNoteIDs: [],
                status: .failed))
        }
        anchor = nil
        evaluations = []
        trail = []
        resetVoiceDot()
        perform(loop.goBackOneSegment(now: capture.currentCaptureTime().seconds))
    }

    /// End Session → "Export N of M", or the session limit / last segment.
    func finish() async {
        guard let url = await stopCapture() else { return }
        if let plan = planner.makePlan(rawVideoURLs: pass.earlierRawVideoURLs + [url], song: song, configuration: configuration) {
            onFinish(plan)
        } else {
            status = .interrupted(.nothingToExport)
        }
    }

    /// Stops after an interruption (PRD §5.8) and keeps the passed takes for a partial export.
    func interrupt() async {
        guard status == .recording else { return }
        let microphoneMissing = (capture as? any MicrophoneInputProviding)?.isHeadsetMicrophoneActive == false
        if await stopCapture() != nil {
            status = .interrupted(microphoneMissing ? .headsetMicrophoneRequired
                                  : (takeLog.passedTakesPrefix().isEmpty ? .nothingToExport : .recordingInterrupted))
        }
    }

    private func headsetMicrophoneChanged() async {
        guard isCapturing else { return }
        if await stopCapture() != nil { status = .interrupted(.headsetMicrophoneRequired) }
    }

    /// Export what passed before the interruption.
    func exportAfterInterruption() {
        guard let rawVideoURL,
              let plan = planner.makePlan(rawVideoURLs: pass.earlierRawVideoURLs + [rawVideoURL], song: song, configuration: configuration) else { return }
        onFinish(plan)
    }

    /// Drops what this pass recorded. A retake or continue goes back to the cover as it was.
    func discard() async {
        if isCapturing { _ = await stopCapture() }
        if pass.isSession {
            takeLog.clear()
            SessionFiles.cleanUp()
        } else {
            takeLog.discardAttempts(inPass: pass.index)
            if let rawVideoURL { SessionFiles.remove(rawVideoURL) }
        }
        onDiscard()
    }

    private var isBlocked: Bool {
        if case .blocked = status { true } else { false }
    }

    /// Finalizes RawMasterVideo.mov. Returns nil (and shows the error) when that fails.
    private func stopCapture() async -> URL? {
        guard isCapturing else { return rawVideoURL }
        isCapturing = false
        loop.end()
        stopObserving()
        playback.stop()
        status = .finishing
        do {
            let url = try await capture.stopRecording()
            rawVideoURL = url
            return url
        } catch {
            status = .failed(.recordingFailed(details: error.localizedDescription))
            return nil
        }
    }

    // MARK: - Loop

    private func startTicking() {
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        })
    }

    private func tick() {
        guard status == .recording else { return }
        let now = capture.currentCaptureTime()
        let seconds = now.seconds
        if seconds - sessionStart >= configuration.maxSessionDuration {
            Task { await interrupt() }
            return
        }
        if seconds - lastStorageCheck >= Self.storageCheckInterval {
            lastStorageCheck = seconds
            if SessionFiles.availableCapacity() < Self.reserveStorageBytes {
                Task { await interrupt() }
                return
            }
        }
        // The timer counts the interval since the last tick if it was spent singing.
        if isSingingPhase, let lastTimerTick { singingTime += max(0, seconds - lastTimerTick) }
        perform(loop.tick(now: seconds, songTime: anchor.map { (now - $0).seconds }))
        lastTimerTick = isSingingPhase ? seconds : nil
    }

    private func perform(_ action: LoopStateController.Action) {
        switch action {
        case .none:
            break
        case .startPlayback(let referenceTime):
            singingFrom = loop.currentSegment?.audioStartTime
            evaluations = []
            trail = []
        resetVoiceDot()
            resetVoiceDot()
            trailDisplay.reset()
            noteDisplay.reset()
            displayTargetID = nil
            do {
                let heard = try playback.play(from: referenceTime)
                anchor = heard - CMTime(seconds: referenceTime, preferredTimescale: heard.timescale)
            } catch {
                Task { await fail(.recordingFailed(details: error.localizedDescription)) }
            }
        case .stopPlayback:
            playback.stop()
        case .evaluate(let index):
            evaluate(segmentIndex: index)
        case .finish:
            Task { await finish() }
        }
    }

    private func evaluate(segmentIndex index: Int) {
        let segment = song.segments[index]
        let inSegment = evaluations.filter {
            $0.referenceTime >= segment.audioStartTime - configuration.pitchHop
                && $0.referenceTime < segment.audioEndTime + configuration.pitchHop
        }
        let result = EvaluateSegmentUseCase(configuration: configuration).execute(segment: segment, evaluations: inSegment)
        let voicedShare = inSegment.isEmpty ? 0 : Double(inSegment.filter { $0.detectedMIDINote != nil }.count) / Double(inSegment.count)
        Self.noteLog.notice("segment \(index + 1, privacy: .public): score \(result.score, format: .fixed(precision: 2), privacy: .public), missed notes \(result.missedNoteIDs.count, privacy: .public)/\(segment.targetNotes.count, privacy: .public), voiced samples \(voicedShare, format: .fixed(precision: 2), privacy: .public)")
        // The take range is what makes comping possible; never pretend a take was kept without one.
        guard let anchor,
              let referenceZero = capture.fileTime(forCaptureTime: anchor),
              let range = TakeRangeBuilder(configuration: configuration).execute(segment: segment, referenceZeroFileTime: referenceZero)
        else {
            Task { await fail(.recordingFailed(details: "This take couldn't be placed on the video timeline.")) }
            return
        }
        // A segment is never repeated: it is kept whatever its score, which stays in the log.
        takeLog.logAttempt(TakeAttemptLog(
            segmentIndex: index,
            attemptNumber: takeLog.allAttempts().filter { $0.segmentIndex == index }.count + 1,
            recordingPass: pass.index,
            videoTimeRange: range,
            accuracyScore: result.score,
            missedNoteIDs: result.missedNoteIDs,
            status: .completed))
        // The next segment is already being sung; keep only its evaluations.
        evaluations.removeAll { $0.referenceTime < segment.audioEndTime - configuration.pitchHop }
        perform(loop.segmentEvaluated())
    }

    private func fail(_ error: UserFacingError) async {
        _ = await stopCapture()
        status = .failed(error)
    }

    // MARK: - Debug readout

    private func updatePitchStats(_ sample: PitchSample) {
        let time = sample.captureTime.seconds
        let voiced = sample.frequency != nil && sample.rmsDecibels >= configuration.noiseGateDBFS
        recentSamples.append((time, voiced))
        recentSamples.removeAll { $0.time < time - 1 }
        var stats = PitchStats()
        stats.samplesPerSecond = recentSamples.count
        stats.voicedPercent = recentSamples.isEmpty ? 0 : recentSamples.filter(\.voiced).count * 100 / recentSamples.count
        let rawMIDI = voiced ? sample.frequency.flatMap { PitchMath.midi(fromFrequency: Double($0)) }.map(Float.init) : nil
        stats.lastNote = noteDisplay.execute(midi: rawMIDI, time: time).map { PitchMath.noteName(midi: Int($0.rounded())) }
        stats.lastLevelDB = sample.rmsDecibels
        pitchStats = stats
    }

    // MARK: - Inputs

    private func observe() {
        let pitch = capture.pitchSamples()
        let routes = routeMonitor.routeChanges()
        let interruptions = routeMonitor.interruptions()
        tasks.append(Task { [weak self] in
            for await sample in pitch { self?.handle(sample) }
        })
        tasks.append(Task { [weak self] in
            for await route in routes {
                guard let self else { return }
                self.route = route
                if !route.allowsRecording && !self.allowsSpeaker { await self.interrupt() }
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in interruptions { await self?.interrupt() }
        })
        tasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .headsetMicrophoneChanged) {
                await self?.headsetMicrophoneChanged()
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .captureRepositoryFailure) {
                await self?.fail(.recordingFailed(details: "The camera or microphone stopped. Your passed segments are saved."))
            }
        })
    }

    private func stopObserving() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// One line per sung note in the event log, to tune the colouring from real takes.
    private func logFinishedNotes(before time: TimeInterval) {
        for note in guideNotes where note.end < time && !loggedNoteIDs.contains(note.id) {
            guard let tally = noteTallies[note.id] else { continue }
            loggedNoteIDs.insert(note.id)
            Self.noteLog.notice("note \(PitchMath.noteName(midi: Int(note.midi)), privacy: .public) \(note.start, format: .fixed(precision: 2), privacy: .public)-\(note.end, format: .fixed(precision: 2), privacy: .public) s: \(tally.summary, privacy: .public)")
        }
    }
    private static let noteLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Notes")

    private func resetVoiceDot() {
        voiceDotFilter.reset()
        voiceDot = nil
        noteTallies = [:]
        noteColoring.reset()
        loggedNoteIDs.removeAll()
    }

    private func handle(_ sample: PitchSample) {
        updatePitchStats(sample)
        guard let anchor, loop.phase == .preRoll || loop.phase == .singing else { return }
        let evaluation = TrackLivePitchUseCase(configuration: configuration)
            .execute(sample: sample, playbackAnchor: anchor, song: song)
        evaluations.append(evaluation)
        if displayTargetID != evaluation.targetNoteID {
            trailDisplay.reset()
            displayTargetID = evaluation.targetNoteID
        }
        let midi = trailDisplay.execute(midi: evaluation.detectedMIDINote, time: evaluation.referenceTime)
        trail.append(TrailPoint(songTime: evaluation.referenceTime, midi: midi, isHit: evaluation.isHit))
        // Note colours (user decision 2026-11-16): a whole note is green or red by NoteTally's
        // looser rule; the clip score still uses every raw sample with its own tolerance.
        noteColoring.add(time: evaluation.referenceTime, midi: evaluation.detectedMIDINote)
        if noteColoring.tallies != noteTallies { noteTallies = noteColoring.tallies }
        logFinishedNotes(before: evaluation.referenceTime - NoteColoring.lateGrace)
        voiceDotFilter.update(midi: evaluation.detectedMIDINote, time: evaluation.referenceTime,
                              foldToDot: evaluation.targetNoteID == nil)
        if let dotMIDI = voiceDotFilter.midi, let heard = voiceDotFilter.lastVoicedTime {
            let dot = VoiceDot(midi: dotMIDI, songTime: heard)
            if dot != voiceDot { voiceDot = dot }
        }
        trail.removeAll { $0.songTime < evaluation.referenceTime - Self.trailLength }
    }
}

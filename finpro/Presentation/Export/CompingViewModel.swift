//
//  CompingViewModel.swift
//  finpro
//
//  Runs the export and the Save to Photos action for ExportPreviewView. Owner: Zildjian Vito (ZV-13).
//

import AVFoundation
import CoreGraphics
import Foundation
import Observation

@Observable
final class CompingViewModel {
    enum ExportState: Equatable {
        case idle
        case exporting(progress: Double)
        case finished(URL)
        case failed(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case denied
        case failed(String)
    }

    /// One take of the cover, with the part of the song it covers.
    struct Clip: Identifiable, Equatable {
        /// The segment index.
        let id: Int
        let start: TimeInterval
        let end: TimeInterval
        /// Sung below the pass threshold: marked "Off-pitch".
        let needsRetake: Bool
    }

    private var editable: CompingCompositionBuilder.Output?
    var vocals: Float
    var music: Float

    /// Levels of the cover file on disk: the plan's, then the last applied edit.
    private var appliedVocals: Float
    private var appliedMusic: Float
    /// The cover re-exported with edited levels; it replaces the first export from then on.
    private var remixedURL: URL?
    /// Progress (0...1) of re-exporting the cover with edited levels; nil when not running.
    private(set) var soundProgress: Double?

    var hasVolumeEdits: Bool { vocals != appliedVocals || music != appliedMusic }

    func prepareMixer() async throws {
        if editable == nil { editable = try await CompingCompositionBuilder().build(plan) }
    }

    private var previewGains: [(isVocal: Bool, gain: PreviewTrackGain)] = []

    func makeMixerItem() throws -> AVPlayerItem {
        guard let editable else { throw CompingError.exportUnavailable }
        let item = AVPlayerItem(asset: editable.composition)
        let mix = editable.makeMix(1, 1)
        let scale = editable.previewGainScale(vocals, music)
        var gains: [(Bool, PreviewTrackGain)] = []
        // Fresh inputs without volume ramps: the taps apply the crossfades and fade-out themselves.
        mix.inputParameters = try mix.inputParameters.map { parameter in
            let input = AVMutableAudioMixInputParameters()
            input.trackID = parameter.trackID
            guard let envelope = editable.previewEnvelopes[input.trackID] else { throw CompingError.exportUnavailable }
            let isVocal = editable.vocalTrackIDs.contains(input.trackID)
            let gain = PreviewTrackGain((isVocal ? vocals : music) * scale, envelope: envelope)
            input.audioTapProcessor = try gain.makeTap()
            gains.append((isVocal, gain))
            return input
        }
        previewGains = gains
        item.videoComposition = editable.videoComposition
        item.audioMix = mix
        item.forwardPlaybackEndTime = CMTime(seconds: plan.endTime, preferredTimescale: 48000)
        return item
    }

    func updatePreviewVolume() {
        guard let editable else { return }
        let scale = editable.previewGainScale(vocals, music)
        for (isVocal, gain) in previewGains {
            gain.set((isVocal ? vocals : music) * scale)
        }
    }

    let plan: CompingCompositionPlan
    /// Notes of the song in the key it was sung in, for the pitch guide over the preview.
    let guideNotes: [PianoRollView.Note]
    /// Notes of the cover's takes sung well and missed (`TakeAttemptLog.missedNoteIDs`).
    let hitNoteIDs: Set<UUID>
    let missedNoteIDs: Set<UUID>
    /// Synced lyrics of the song, shown under the pitch guide (empty when none were found).
    let lyrics: [LyricLine]
    /// The word sung on each guide note, drawn under the note.
    let wordLabels: [UUID: String]
    /// "Artist - Title" of the imported song, when known.
    let songName: String?
    private(set) var exportState: ExportState = .idle
    private(set) var saveState: SaveState = .idle
    /// A frame of each clip, by segment index; filled once the cover is exported.
    private(set) var thumbnails: [Int: CGImage] = [:]
    private(set) var selectedClipID: Int?
    /// True when the user tapped the selected clip (it then shows Retake); false when the
    /// selection only follows the playing video.
    private(set) var isClipChosen = false
    /// The last export failed because iOS interrupted it (app in the background, video hardware
    /// busy); it is retried when the app is active again.
    private(set) var wasInterrupted = false

    private let useCase: AutoCompingVideoUseCase
    private let videoLibrary: any VideoLibrarySaving
    private let onExported: (URL, CompingCompositionPlan) -> Void
    /// The cover was saved to Photos (the user's way of finishing it).
    private let onSavedToPhotos: () -> Void
    private let thumbnailProvider: any ClipThumbnailProviding
    private let passThreshold: Float

    /// - Parameter existingExport: a video already exported from `plan`; it is shown as is
    ///   instead of merging the takes again.
    init(plan: CompingCompositionPlan, songName: String? = nil, existingExport: URL? = nil,
         useCase: AutoCompingVideoUseCase,
         videoLibrary: any VideoLibrarySaving,
         thumbnailProvider: any ClipThumbnailProviding = AVClipThumbnailProvider(),
         passThreshold: Float = AppConfiguration().passThreshold,
         onExported: @escaping (URL, CompingCompositionPlan) -> Void = { _, _ in },
         onSavedToPhotos: @escaping () -> Void = {},
         transposition: TranspositionPlan? = nil,
         lyrics: [LyricLine] = []) {
        guideNotes = plan.segments.flatMap(\.targetNotes).map {
            PianoRollView.Note(id: $0.id, midi: transposition?.transposed($0) ?? $0.midiNote, start: $0.startTime, end: $0.endTime)
        }
        self.lyrics = lyrics
        wordLabels = GuideWordLabels.make(words: lyrics.flatMap(\.words), notes: guideNotes)
        var hit = Set<UUID>(), missed = Set<UUID>()
        for take in plan.validTakes where plan.segments.indices.contains(take.segmentIndex) {
            let missedHere = Set(take.missedNoteIDs)
            for note in plan.segments[take.segmentIndex].targetNotes {
                if missedHere.contains(note.id) { missed.insert(note.id) } else { hit.insert(note.id) }
            }
        }
        hitNoteIDs = hit
        missedNoteIDs = missed
        vocals = plan.vocalGain
        music = plan.instrumentalGain
        appliedVocals = plan.vocalGain
        appliedMusic = plan.instrumentalGain
        self.plan = plan
        self.songName = songName
        self.useCase = useCase
        self.videoLibrary = videoLibrary
        self.thumbnailProvider = thumbnailProvider
        self.passThreshold = passThreshold
        self.onExported = onExported
        self.onSavedToPhotos = onSavedToPhotos
        selectedClipID = plan.validTakes.first?.segmentIndex
        if let existingExport, FileManager.default.fileExists(atPath: existingExport.path) {
            exportState = .finished(existingExport)
        }
    }

    var title: String { songName ?? "Your cover" }

    var clips: [Clip] {
        plan.validTakes.compactMap { take in
            plan.segments.first { $0.index == take.segmentIndex }
                .map { Clip(id: $0.index, start: $0.audioStartTime, end: $0.audioEndTime,
                            needsRetake: take.accuracyScore < passThreshold) }
        }
    }

    /// The session ended before the last segment, so recording can go on (Continue Recording).
    var canContinueRecording: Bool { plan.isPartial }

    /// "2:18 • 5 clips"
    var subtitle: String {
        let count = clips.count
        return "\(Self.format(plan.endTime)) • \(count) \(count == 1 ? "clip" : "clips")"
    }

    /// "00:13-00:17"
    func timeRange(of clip: Clip) -> String {
        "\(Self.clock(clip.start))-\(Self.clock(clip.end))"
    }

    func selectClip(_ id: Int) {
        selectedClipID = id
        isClipChosen = true
    }

    /// The video is at `time` on the cover timeline: select the clip playing there (the last one
    /// that started, so a gap between clips keeps the previous clip).
    private static let clipStartSlack: TimeInterval = 1.0 / 30

    func followPlayback(at time: TimeInterval) {
        let sorted = clips.sorted { $0.start < $1.start }
        // One video frame of slack: a seek to a clip's start can land just before it.
        guard let clip = sorted.last(where: { $0.start <= time + Self.clipStartSlack }) ?? sorted.first,
              clip.id != selectedClipID else { return }
        selectedClipID = clip.id
        isClipChosen = false
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    /// Minutes and seconds, both with two digits ("01:05").
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var summary: String {
        let passed = plan.validTakes.count, total = plan.segments.count
        return plan.isPartial ? "Partial cover · \(passed) of \(total) segments" : "Full cover · \(total) segments"
    }

    var exportedURL: URL? {
        if case .finished(let url) = exportState { remixedURL ?? url } else { nil }
    }

    /// False while running on fakes: the fake export returns a URL without writing a file.
    var hasPlayableFile: Bool {
        exportedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func export() async {
        if case .exporting = exportState { return }
        // Already exported (an existing video was passed in): only the clip frames are missing.
        if hasPlayableFile, let url = exportedURL {
            if thumbnails.isEmpty { await loadThumbnails(from: url) }
            return
        }
        exportState = .exporting(progress: 0)
        saveState = .idle
        wasInterrupted = false
        do {
            // The view model is MainActor-isolated (so Sendable); holding it until the export ends is fine.
            let url = try await useCase.export(plan) { progress in
                Task { @MainActor in
                    guard case .exporting = self.exportState else { return }
                    self.exportState = .exporting(progress: progress)
                }
            }
            if FileManager.default.fileExists(atPath: url.path) { onExported(url, plan) }
            exportState = .finished(url)
            await loadThumbnails(from: url)
        } catch {
            if case CompingError.exportInterrupted = error { wasInterrupted = true }
            exportState = .failed(String(describing: error))
        }
    }

    /// The app is active again: an export that iOS interrupted starts over by itself.
    func appBecameActive() async {
        guard wasInterrupted, case .failed = exportState else { return }
        await export()
    }

    /// A frame from the middle of each clip.
    private func loadThumbnails(from url: URL) async {
        let clips = clips
        let frames = await thumbnailProvider.thumbnails(for: url, at: clips.map { ($0.start + $0.end) / 2 })
        for (clip, frame) in zip(clips, frames) {
            if let frame { thumbnails[clip.id] = frame }
        }
    }

    /// Re-exports the cover with the edited levels and stores it (Home, draft) in place of the
    /// earlier file. Does nothing without edits.
    func applyVolumeEdits() async throws {
        guard hasVolumeEdits, soundProgress == nil else { return }
        guard let editable else { throw CompingError.exportUnavailable }
        let edited = CompingCompositionPlan(rawVideoURLs: plan.rawVideoURLs, instrumentalURL: plan.instrumentalURL,
            segments: plan.segments, validTakes: plan.validTakes, endTime: plan.endTime,
            crossfadeDuration: plan.crossfadeDuration, instrumentalFadeOut: plan.instrumentalFadeOut,
            vocalGain: vocals, instrumentalGain: music)
        soundProgress = 0
        defer { soundProgress = nil }
        let output = try editable.applyingVolumes(vocals: edited.vocalGain, music: edited.instrumentalGain)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cover-\(UUID().uuidString).mp4")
        do {
            try await VideoCompositionRepositoryImpl().export(output, plan: edited, to: url) { progress in
                Task { @MainActor in
                    if let current = self.soundProgress { self.soundProgress = max(current, progress) }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        if let remixedURL { try? FileManager.default.removeItem(at: remixedURL) }
        remixedURL = url
        appliedVocals = edited.vocalGain
        appliedMusic = edited.instrumentalGain
        onExported(url, edited)
    }

    func saveToPhotos() async {
        guard exportedURL != nil, saveState != .saving else { return }
        saveState = .saving
        do {
            try await applyVolumeEdits()
            guard let url = exportedURL else { throw CompingError.exportUnavailable }
            try await videoLibrary.saveVideo(at: url)
            saveState = .saved
            onSavedToPhotos()
        } catch VideoLibraryError.accessDenied {
            saveState = .denied
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    isolated deinit {
        if let remixedURL { try? FileManager.default.removeItem(at: remixedURL) }
    }
}

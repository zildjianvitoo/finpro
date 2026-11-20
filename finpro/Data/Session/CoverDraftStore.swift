//
//  CoverDraftStore.swift
//  finpro
//

import CoreMedia
import Foundation

/// Keeps a cover's working files (raw videos, song audio) and its plan in Application Support,
/// so a draft can be opened on the result screen after the app was closed. One folder per cover,
/// named by the cover's id. Session files live in a temporary folder and are deleted when a new
/// session starts, so they are copied here; files already here are not copied again.
nonisolated struct CoverDraftStore: Sendable {
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CoverDrafts", isDirectory: true)) {
        self.directory = directory
    }

    func save(_ draft: CoverDraft, id: UUID) async throws {
        let folder = folder(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mix = try keep(draft.song.earphoneMixURL, in: folder, as: "mix")
        let instrumental = try keep(draft.song.instrumentalURL, in: folder, as: "instrumental")
        let planInstrumental = draft.plan.instrumentalURL == draft.song.instrumentalURL
            ? instrumental : try keep(draft.plan.instrumentalURL, in: folder, as: "plan-instrumental")
        let rawVideos = try draft.plan.rawVideoURLs.map { try keep($0, in: folder, as: nil) }
        let record = Record(draft: draft, mix: mix, instrumental: instrumental,
                            planInstrumental: planInstrumental, rawVideos: rawVideos)
        try JSONEncoder().encode(record).write(to: folder.appendingPathComponent(Self.manifest), options: .atomic)
        // Raw videos of passes no longer in the plan are not needed any more.
        let kept = Set([mix, instrumental, planInstrumental, Self.manifest] + rawVideos)
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !kept.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    /// Nil when the cover has no saved working files (or they are incomplete).
    func load(id: UUID) -> CoverDraft? {
        let folder = folder(for: id)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifest)),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        let files = [record.mix, record.instrumental, record.planInstrumental] + record.rawVideos
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }) else {
            return nil
        }
        return record.draft(in: folder)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    /// Deletes the working files of every cover not in `ids` (finished or removed covers).
    func deleteAll(except ids: Set<UUID>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where UUID(uuidString: name).map({ !ids.contains($0) }) ?? true {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static let manifest = "draft.json"

    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Copies a file into the folder unless it is already there. Returns its name in the folder.
    private func keep(_ url: URL, in folder: URL, as name: String?) throws -> String {
        if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return url.lastPathComponent
        }
        let fileName = name.map { "\($0).\(url.pathExtension)" } ?? url.lastPathComponent
        let destination = folder.appendingPathComponent(fileName)
        // Copied at an earlier export (raw videos are large): keep it.
        if Self.size(of: destination) != nil, Self.size(of: destination) == Self.size(of: url) { return fileName }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return fileName
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}

// MARK: - Stored form

/// Domain types are not Codable (contracts), so the draft is stored in this mirror. File URLs are
/// stored as names inside the cover's folder.
private nonisolated struct Record: Codable {
    struct Take: Codable {
        let id: UUID
        let segmentIndex: Int
        let attemptNumber: Int
        let recordingPass: Int
        let start: CMTimeValue
        let duration: CMTimeValue
        let timescale: CMTimeScale
        let accuracyScore: Float
        let missedNoteIDs: [UUID]
        let status: SegmentAttemptStatus

        init(_ take: TakeAttemptLog) {
            let range = take.videoTimeRange
            let timescale = max(range.start.timescale, range.duration.timescale, 1)
            id = take.id
            segmentIndex = take.segmentIndex
            attemptNumber = take.attemptNumber
            recordingPass = take.recordingPass
            start = range.start.convertScale(timescale, method: .default).value
            duration = range.duration.convertScale(timescale, method: .default).value
            self.timescale = timescale
            accuracyScore = take.accuracyScore
            missedNoteIDs = take.missedNoteIDs
            status = take.status
        }

        var attempt: TakeAttemptLog {
            TakeAttemptLog(id: id, segmentIndex: segmentIndex, attemptNumber: attemptNumber, recordingPass: recordingPass,
                           videoTimeRange: CMTimeRange(start: CMTime(value: start, timescale: timescale),
                                                       duration: CMTime(value: duration, timescale: timescale)),
                           accuracyScore: accuracyScore, missedNoteIDs: missedNoteIDs, status: status)
        }
    }

    // Song
    let mix: String
    let instrumental: String
    let segments: [SongSegment]
    let transposition: TranspositionPlan
    let songDuration: TimeInterval
    let separationMethod: StemSeparationMethod
    // Plan
    let rawVideos: [String]
    let planInstrumental: String
    let validTakeIDs: [UUID]
    let endTime: TimeInterval
    let crossfadeSeconds: Double
    let instrumentalFadeOut: TimeInterval
    let vocalGain: Float
    let instrumentalGain: Float
    // Session
    let attempts: [Take]
    let lyrics: [LyricLine]
    let songName: String?

    init(draft: CoverDraft, mix: String, instrumental: String, planInstrumental: String, rawVideos: [String]) {
        self.mix = mix
        self.instrumental = instrumental
        segments = draft.song.segments
        transposition = draft.song.transposition
        songDuration = draft.song.duration
        separationMethod = draft.song.separationMethod
        self.rawVideos = rawVideos
        self.planInstrumental = planInstrumental
        validTakeIDs = draft.plan.validTakes.map(\.id)
        endTime = draft.plan.endTime
        crossfadeSeconds = draft.plan.crossfadeDuration.seconds
        instrumentalFadeOut = draft.plan.instrumentalFadeOut
        vocalGain = draft.plan.vocalGain
        instrumentalGain = draft.plan.instrumentalGain
        // The plan's takes are in the log too; keep them even if the log was cleared.
        let logged = Set(draft.attempts.map(\.id))
        attempts = (draft.attempts + draft.plan.validTakes.filter { !logged.contains($0.id) }).map(Take.init)
        lyrics = draft.lyrics
        songName = draft.songName
    }

    func draft(in folder: URL) -> CoverDraft {
        let url = { (name: String) in folder.appendingPathComponent(name) }
        let attempts = self.attempts.map(\.attempt)
        let byID = Dictionary(attempts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let song = PreparedSong(earphoneMixURL: url(mix), instrumentalURL: url(instrumental), segments: segments,
                                transposition: transposition, duration: songDuration, separationMethod: separationMethod)
        let plan = CompingCompositionPlan(
            rawVideoURLs: rawVideos.map(url), instrumentalURL: url(planInstrumental), segments: segments,
            validTakes: validTakeIDs.compactMap { byID[$0] }, endTime: endTime,
            crossfadeDuration: CMTime(seconds: crossfadeSeconds, preferredTimescale: 48_000),
            instrumentalFadeOut: instrumentalFadeOut, vocalGain: vocalGain, instrumentalGain: instrumentalGain)
        return CoverDraft(song: song, plan: plan, attempts: attempts, lyrics: lyrics, songName: songName)
    }
}

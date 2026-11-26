//
//  LRCLibLyricsProvider.swift
//  finpro
//
//  Synced lyrics from LRCLIB (https://lrclib.net: free, open, no key). Only the title, artist and
//  duration are sent, never audio. The version whose duration is closest to the file is used, so
//  the line times match this recording.
//

import Foundation
import os

nonisolated final class LRCLibLyricsProvider: LyricsProviding, @unchecked Sendable {
    /// One search record (fields the app uses).
    struct Record: Decodable, Equatable, Sendable {
        let trackName: String
        let artistName: String
        let duration: Double
        let instrumental: Bool
        let syncedLyrics: String?
    }

    /// Versions further than this from the file's duration are another edit (intro, radio cut),
    /// so their line times wouldn't match.
    static let durationTolerance: TimeInterval = 5
    /// Minimum share of the song's duration that the last synced line should reach for a record
    /// to be considered plausible (skips broken LRCLIB uploads where an entire song is crammed
    /// into the opening minute while healthy siblings exist within `durationTolerance`).
    static let minimumTimelineCoverage: Double = 0.5
    private static let endpoint = URL(string: "https://lrclib.net/api/search")!
    /// LRCLIB asks clients to identify themselves. Add the repo URL once it exists.
    private static let userAgent = "finpro/1.0 (Apple Developer Academy)"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Lyrics")

    private let session: URLSession
    private let lock = NSLock()
    private var cache: [String: SongLyrics?] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lyrics(title: String, artist: String?, duration: TimeInterval) async throws -> SongLyrics? {
        let key = "\(title.lowercased())|\(artist?.lowercased() ?? "")|\(Int(duration.rounded()))"
        if let cached = lock.withLock({ cache[key] }) { return cached }
        var queries: [[URLQueryItem]] = []
        if let artist, !artist.isEmpty {
            queries.append([URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)])
        }
        queries.append([URLQueryItem(name: "q", value: [title, artist].compactMap { $0 }.joined(separator: " "))])
        var result: SongLyrics?
        for query in queries {
            let records: [Record]
            do { records = try await search(query) } catch {
                Self.log.error("search \(title, privacy: .public) / \(artist ?? "-", privacy: .public) failed: \(String(describing: error), privacy: .public)")
                throw error
            }
            if let match = Self.bestMatch(records, duration: duration) {
                let lines = LRCLyricsParser.lines(from: match.syncedLyrics ?? "", duration: duration)
                result = SongLyrics(lines: lines, chorus: ChorusFinder.chorus(in: lines),
                                    matchedTitle: match.trackName, matchedArtist: match.artistName)
                break
            }
        }
        if result?.lines.isEmpty == true { result = nil }
        if let result {
            Self.log.notice("found \(result.matchedArtist ?? "-", privacy: .public) - \(result.matchedTitle ?? "-", privacy: .public) for \(title, privacy: .public) / \(artist ?? "-", privacy: .public)")
        } else {
            Self.log.notice("no synced lyrics within \(Int(Self.durationTolerance), privacy: .public) s of \(Int(duration), privacy: .public) s for \(title, privacy: .public) / \(artist ?? "-", privacy: .public)")
        }
        lock.withLock { cache[key] = result }
        return result
    }

    /// The synced, non-instrumental record closest in duration, if within `durationTolerance`.
    /// Deprioritizes corrupted community LRC records whose timestamps collapse into the opening
    /// fraction of the track when a healthy sibling exists within tolerance.
    static func bestMatch(_ records: [Record], duration: TimeInterval) -> Record? {
        let candidates = records.filter {
            !$0.instrumental && !($0.syncedLyrics ?? "").isEmpty && abs($0.duration - duration) <= durationTolerance
        }
        guard !candidates.isEmpty else { return nil }
        let healthy = candidates.filter { hasPlausibleTimeline($0.syncedLyrics ?? "", duration: duration) }
        let pool = healthy.isEmpty ? candidates : healthy
        return pool.min { abs($0.duration - duration) < abs($1.duration - duration) }
    }

    static func hasPlausibleTimeline(_ syncedLyrics: String, duration: TimeInterval) -> Bool {
        guard duration > 0 else { return true }
        let lines = LRCLyricsParser.lines(from: syncedLyrics, duration: duration)
        guard let last = lines.last else { return false }
        return last.start >= duration * minimumTimelineCoverage
    }

    private func search(_ query: [URLQueryItem]) async throws -> [Record] {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        // LRCLIB often answers 503 "server busy" for a few seconds; retry after 1 s and 2 s.
        let retryDelays: [Duration] = [.seconds(1), .seconds(2)]
        for attempt in 0...retryDelays.count {
            let data: Data, response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LyricsLookupError.unavailable
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 503, attempt < retryDelays.count {
                try await Task.sleep(for: retryDelays[attempt])
                continue
            }
            guard status == 200 else { throw LyricsLookupError.unavailable }
            // LRCLIB's JSON sometimes has raw control characters inside lyrics, which strict
            // parsers reject; between JSON tokens they are only whitespace, so drop them all.
            let text = String(decoding: data, as: UTF8.self)
            let cleaned = Data(String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value >= 0x20 })).utf8)
            return (try? JSONDecoder().decode([Record].self, from: cleaned)) ?? []
        }
        throw LyricsLookupError.unavailable
    }
}

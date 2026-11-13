//
//  HomeViewModel.swift
//  finpro
//
//  ViewModel for the home dashboard screen.
//

import Foundation
import Observation

@Observable
final class HomeViewModel {
    struct RecentCoverItem: Identifiable, Sendable {
        enum Status: Sendable {
            case finished
            case draft
        }

        let id: UUID
        let title: String
        let date: Date
        let duration: TimeInterval
        let status: Status
        var videoURL: URL? = nil
    }

    let songLibrary: SongLibrary
    let coverLibrary: CoverLibrary?
    private let onSongs: () -> Void
    private let onOpenSong: (SavedSong) -> Void
    private let vocalRangeRepository: VocalRangeRepository
    private let onStartCreateCover: () -> Void
    private let onRetestVocalRangeAction: () -> Void

    var vocalRangeText: String {
        guard let range = vocalRangeRepository.load() else {
            return "Not tested"
        }
        let low = PitchMath.noteName(midi: Int(range.lowestMIDI.rounded()))
        let high = PitchMath.noteName(midi: Int(range.highestMIDI.rounded()))
        return "\(low)-\(high)"
    }

    /// Saved exports and partial covers; fixtures can still be injected for previews.
    private var previewCovers: [RecentCoverItem]
    var recentCovers: [RecentCoverItem] {
        guard let coverLibrary else { return previewCovers }
        return coverLibrary.covers.map {
            RecentCoverItem(id: $0.id, title: $0.title, date: $0.date, duration: $0.duration,
                            status: $0.isDraft ? .draft : .finished, videoURL: coverLibrary.url(for: $0))
        }
    }

    init(
        vocalRangeRepository: VocalRangeRepository,
        recentCovers: [RecentCoverItem] = [],
        songLibrary: SongLibrary = SongLibrary(), coverLibrary: CoverLibrary? = nil,
        onSongs: @escaping () -> Void = {},
        onOpenSong: @escaping (SavedSong) -> Void = { _ in },
        onCreateCover: @escaping () -> Void,
        onRetestVocalRange: @escaping () -> Void
    ) {
        self.songLibrary = songLibrary
        self.coverLibrary = coverLibrary
        self.onSongs = onSongs
        self.onOpenSong = onOpenSong
        self.vocalRangeRepository = vocalRangeRepository
        self.previewCovers = recentCovers
        self.onStartCreateCover = onCreateCover
        self.onRetestVocalRangeAction = onRetestVocalRange
    }

    func createCoverTapped() {
        onStartCreateCover()
    }

    func vocalRangeTapped() {
        onRetestVocalRangeAction()
    }

    func songsTapped() { onSongs() }
    func openSong(_ song: SavedSong) { onOpenSong(song) }
}

#if DEBUG
extension HomeViewModel.RecentCoverItem {
    /// Sample covers for previews, matching the design.
    static let samples: [Self] = {
        let day: TimeInterval = 24 * 60 * 60
        let now = Date()
        let dates = [now, now.addingTimeInterval(-3 * day), now.addingTimeInterval(-day), now, now, now]
        let statuses: [Status] = [.finished, .draft, .draft, .finished, .finished, .finished]
        return zip(dates, statuses).map { date, status in
            Self(id: UUID(), title: "LANY - Stuck", date: date, duration: 138, status: status)
        }
    }()
}
#endif

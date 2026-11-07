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
        // TODO(logic): Add video thumbnail URL or asset reference
    }

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

    /// Empty until saved covers are wired up; the screen then shows its empty state.
    // TODO(logic): connect to saved recent covers library / photo album
    private(set) var recentCovers: [RecentCoverItem]

    init(
        vocalRangeRepository: VocalRangeRepository,
        recentCovers: [RecentCoverItem] = [],
        onCreateCover: @escaping () -> Void,
        onRetestVocalRange: @escaping () -> Void
    ) {
        self.vocalRangeRepository = vocalRangeRepository
        self.recentCovers = recentCovers
        self.onStartCreateCover = onCreateCover
        self.onRetestVocalRangeAction = onRetestVocalRange
    }

    func createCoverTapped() {
        onStartCreateCover()
    }

    func vocalRangeTapped() {
        onRetestVocalRangeAction()
    }

    func seeAllTapped() {
        // TODO(logic): open full recent covers list or gallery
    }
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

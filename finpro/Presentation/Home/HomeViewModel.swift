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
        let id: UUID
        let title: String
        let date: Date
        // TODO(logic): Add video thumbnail URL or asset reference
    }

    private let vocalRangeRepository: VocalRangeRepository
    private let onStartCreateCover: () -> Void
    private let onRetestVocalRangeAction: () -> Void

    var vocalRangeText: String {
        guard let range = vocalRangeRepository.load() else {
            return "C3-A5"
        }
        let low = PitchMath.noteName(midi: Int(range.lowestMIDI.rounded()))
        let high = PitchMath.noteName(midi: Int(range.highestMIDI.rounded()))
        return "\(low)-\(high)"
    }

    // TODO(logic): connect to saved recent covers library / photo album
    private(set) var recentCovers: [RecentCoverItem] = (0..<6).map { index in
        RecentCoverItem(id: UUID(), title: "Cover \(index + 1)", date: Date())
    }

    init(
        vocalRangeRepository: VocalRangeRepository,
        onCreateCover: @escaping () -> Void,
        onRetestVocalRange: @escaping () -> Void
    ) {
        self.vocalRangeRepository = vocalRangeRepository
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

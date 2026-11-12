//
//  FakeSessionTakeLogRepository.swift
//  finpro
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

#if DEBUG
import Foundation
import Synchronization

nonisolated final class FakeSessionTakeLogRepository: SessionTakeLogRepository, Sendable {
    private let attempts = Mutex<[TakeAttemptLog]>([])

    func logAttempt(_ attempt: TakeAttemptLog) {
        attempts.withLock { $0.append(attempt) }
    }

    func allAttempts() -> [TakeAttemptLog] {
        attempts.withLock { $0 }
    }

    func passedTakesPrefix() -> [TakeAttemptLog] {
        let all = attempts.withLock { $0 }
        var prefix: [TakeAttemptLog] = []
        // The latest take of a segment is the one that counts; a `.failed` one marks it as deleted.
        while let latest = all.last(where: { $0.segmentIndex == prefix.count }), latest.status != .failed {
            prefix.append(latest)
        }
        return prefix
    }

    func discardAttempts(inPass recordingPass: Int) {
        attempts.withLock { $0.removeAll { $0.recordingPass == recordingPass } }
    }

    func clear() {
        attempts.withLock { $0.removeAll() }
    }
}

#endif

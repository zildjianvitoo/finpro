//
//  SessionTakeLogRepositoryImpl.swift
//  finpro
//

import Foundation

nonisolated final class SessionTakeLogRepositoryImpl: SessionTakeLogRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var attempts: [TakeAttemptLog] = []

    func logAttempt(_ attempt: TakeAttemptLog) {
        lock.lock()
        defer { lock.unlock() }
        guard !attempts.contains(where: { $0.id == attempt.id }) else { return }
        attempts.append(attempt)
    }

    func allAttempts() -> [TakeAttemptLog] {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func passedTakesPrefix() -> [TakeAttemptLog] {
        lock.lock()
        defer { lock.unlock() }
        var prefix: [TakeAttemptLog] = []
        // The latest take of a segment is the one that counts; a `.failed` one marks it as deleted.
        while let latest = attempts.last(where: { $0.segmentIndex == prefix.count }), latest.status != .failed {
            prefix.append(latest)
        }
        return prefix
    }

    func discardAttempts(inPass recordingPass: Int) {
        lock.lock()
        defer { lock.unlock() }
        attempts.removeAll { $0.recordingPass == recordingPass }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        attempts.removeAll()
    }
}

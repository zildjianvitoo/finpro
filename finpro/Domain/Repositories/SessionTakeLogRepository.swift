//
//  SessionTakeLogRepository.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Takin
//

import Foundation

nonisolated protocol SessionTakeLogRepository: AnyObject {
    func logAttempt(_ attempt: TakeAttemptLog)
    func allAttempts() -> [TakeAttemptLog]
    /// The take that goes into the cover for segments 0...N-1 (status `.passed` or `.completed`), ordered by segment index.
    func passedTakesPrefix() -> [TakeAttemptLog]
    func clear()
}

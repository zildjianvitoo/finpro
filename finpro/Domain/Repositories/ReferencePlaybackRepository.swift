//
//  ReferencePlaybackRepository.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Takin
//

import CoreMedia
import Foundation

nonisolated protocol ReferencePlaybackRepository: AnyObject {
    /// Also forgets the lead-in: call `loadLeadIn` again after it.
    func load(earphoneMixURL: URL) throws
    /// The song before the trimmed part (`PreparedSong.LeadIn`), heard before 0 instead of
    /// silence; it must end where the loaded song starts. `instrumentalURL` is heard instead while
    /// the reference vocal is off. Nil clears it. Added 2026-11-21 with the user's OK.
    func loadLeadIn(mixURL: URL?, instrumentalURL: URL?) throws
    /// Schedules playback from `referenceTime` and returns the capture-clock time
    /// at which that point is HEARD (scheduled host time + output latency).
    /// A negative `referenceTime` plays the end of the lead-in, and silence before it where the
    /// lead-in is shorter (all silence without one).
    func play(from referenceTime: TimeInterval) throws -> CMTime
    func stop()
}

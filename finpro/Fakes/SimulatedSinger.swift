//
//  SimulatedSinger.swift
//  finpro
//
//  Simulator only: a "singer" that follows the fake reference playback, so the real recording
//  loop (evaluation, pause, partial export) runs without a camera or microphone. It sings every
//  note in tune.
//

#if DEBUG
import CoreMedia
import Foundation
import Synchronization

nonisolated final class SimulatedSinger: Sendable {
    private struct State {
        var notes: [(start: TimeInterval, end: TimeInterval, midi: Int)] = []
        var songZero: CMTime?
    }

    private let state = Mutex(State())

    /// Call when a recording session starts.
    func prepare(song: PreparedSong) {
        let notes = song.segments.flatMap(\.targetNotes).map {
            (start: $0.startTime, end: $0.endTime, midi: song.transposition.transposed($0))
        }
        state.withLock { $0 = State(notes: notes) }
    }

    /// Hook for FakeReferencePlaybackRepository(onPlay:).
    func playbackStarted(from referenceTime: TimeInterval, heard: CMTime) {
        state.withLock {
            $0.songZero = heard - CMTime(seconds: referenceTime, preferredTimescale: heard.timescale)
        }
    }

    /// Voice for FakeCaptureRepository: the frequency sung right now (host clock = fake capture clock).
    func frequencyNow() -> Float? {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        return state.withLock { state -> Float? in
            guard let songZero = state.songZero else { return nil }
            let songTime = (now - songZero).seconds
            guard let note = state.notes.first(where: { songTime >= $0.start && songTime < $0.end }) else { return nil }
            return Float(440 * pow(2, (Double(note.midi) - 69) / 12))
        }
    }
}

#endif

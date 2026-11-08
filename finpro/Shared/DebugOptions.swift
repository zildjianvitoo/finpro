//
//  DebugOptions.swift
//  finpro
//
//  Developer-only switches that are not part of AppConfiguration (the shared contract).
//  Always off in Release builds.
//

import Foundation

nonisolated enum DebugOptions {
    private static let speakerKey = "DebugOptions.allowsSpeakerRecording"

    /// Launch argument `-startScreen <onboarding|vocalRange|home|importSong>`: opens the app on
    /// that step, so a screen can be checked without tapping through the flow:
    /// `xcrun simctl launch booted <bundle id> -startScreen importSong`.
    static var launchScreen: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "startScreen")
        #else
        nil
        #endif
    }

    /// Launch argument `-importFile <absolute path>`: the Add a song screen opens that file as
    /// if it was picked (the simulator reads host paths directly), landing on the trimmer.
    static var launchImportFile: URL? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "importFile").map { URL(fileURLWithPath: $0) }
        #else
        nil
        #endif
    }

    /// Lets a session record with the built-in speaker (no earphones) and plays the song through
    /// the loudspeaker. For device testing only: the song leaks into the microphone, so scores and
    /// the final mix are not representative (PRD §7.2 blocks this in the real app).
    static var allowsSpeakerRecording: Bool {
        get {
            #if DEBUG
            UserDefaults.standard.bool(forKey: speakerKey)
            #else
            false
            #endif
        }
        set { UserDefaults.standard.set(newValue, forKey: speakerKey) }
    }
}

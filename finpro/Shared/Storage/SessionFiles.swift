//
//  SessionFiles.swift
//  finpro
//
//  Where a recording session keeps its large files, and how they are cleaned up (ZV-16).
//  Owner: Zildjian Vito. Capture (Takin) writes each recording pass to its own `newRawVideoURL()`;
//  comping writes the final cover to `finalVideoURL`.
//

import Foundation

nonisolated enum SessionFiles {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Session", isDirectory: true)
    }

    /// A new raw video file for one recording pass: the session, then each retake or continue
    /// gets its own, so earlier passes stay available for the cover.
    static func newRawVideoURL() -> URL {
        directory.appendingPathComponent("RawMasterVideo-\(UUID().uuidString).mov")
    }
    static var finalVideoURL: URL { directory.appendingPathComponent("FinalCoverVideo.mp4") }

    /// Free space for important data on the app's volume, in bytes (PRD §5.8 storage checks).
    static func availableCapacity() -> Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Creates the session folder if needed.
    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Deletes one file of this session (the raw video of a discarded pass).
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes every file from earlier sessions (raw recording, final export, leftovers after a crash).
    /// The synthesized demo cache lives elsewhere and is kept.
    @discardableResult
    static func cleanUp() -> Int {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for file in files where (try? fileManager.removeItem(at: file)) != nil {
            removed += 1
        }
        return removed
    }
}

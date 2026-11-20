//
//  AppEventLog.swift
//  finpro
//
//  Copies the app's own log messages (every `Logger` with the app's subsystem: Import,
//  Recognition, Lyrics, Preparation, KeyPreview, Preview, Export, Capture, Prewarm, Flow…) into
//  Library/Logs/events.log in the app's container, so they can be read after a test on a phone
//  without Console.app (how to pull the file: docs/DEVICE-LOGS.md). Local only; nothing is sent.
//

import Foundation
import OSLog

nonisolated final class AppEventLog: @unchecked Sendable {
    static let shared = AppEventLog()

    /// The file is cut back to its newest half beyond this size.
    private static let maximumBytes = 2_000_000
    /// While the app is open, new messages are copied this often.
    private static let flushInterval: Duration = .seconds(10)

    private let queue = DispatchQueue(label: "app-event-log", qos: .utility)
    private var lastCopied: Date?
    private var flushing: Task<Void, Never>?
    private let subsystem = Bundle.main.bundleIdentifier ?? "finpro"

    static var fileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/events.log")
    }

    /// Marks a new app launch in the file and starts copying every `flushInterval`.
    func start() {
        let device = ProcessInfo.processInfo.operatingSystemVersionString
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        queue.async { [self] in
            lastCopied = Date()
            append("\n===== launch \(Self.stamp(Date())) app \(version) (\(build)), iOS \(device) =====\n")
        }
        flushing?.cancel()
        flushing = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.flushInterval)
                self?.flush()
            }
        }
    }

    /// Copies the messages logged since the last copy (also call it when the app goes to the background).
    func flush() {
        queue.async { [self] in
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return }
            let since = lastCopied ?? Date().addingTimeInterval(-60)
            let position = store.position(date: since)
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            guard let entries = try? store.getEntries(at: position, matching: predicate) else { return }
            var text = ""
            var newest = since
            for case let entry as OSLogEntryLog in entries where entry.date > since {
                let level = switch entry.level {
                case .error: "ERROR"
                case .fault: "FAULT"
                default: "     "
                }
                text += "\(Self.stamp(entry.date)) \(level) [\(entry.category)] \(entry.composedMessage)\n"
                newest = max(newest, entry.date)
            }
            lastCopied = newest
            if !text.isEmpty { append(text) }
        }
    }

    private func append(_ text: String) {
        let url = Self.fileURL
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
        let size = (try? handle.offset()) ?? 0
        try? handle.close()
        if size > Self.maximumBytes, let data = try? Data(contentsOf: url) {
            try? data.suffix(Self.maximumBytes / 2).write(to: url, options: .atomic)
        }
    }

    /// Local time, used on `queue` only.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func stamp(_ date: Date) -> String { formatter.string(from: date) }
}

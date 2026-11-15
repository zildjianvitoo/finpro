//
//  AudioFileInspector.swift
//  finpro
//
//  Copies a file picked in Files into the app and reads its duration and a coarse waveform
//  for the trimmer (PRD §5.2). Audio and video files (audio track) are supported; DRM is rejected.
//

import AVFoundation
import os

nonisolated struct AudioFileInspector: AudioFileInspecting {
    /// Bars in the trimmer waveform.
    static let waveformBins = 160
    /// The waveform only needs a coarse picture, so read at a low rate
    /// (AVAssetReader accepts 8–192 kHz; lower values throw an Objective-C exception).
    private static let analysisSampleRate = 8_000.0
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Import")

    static var importDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
    }

    func importFile(at pickedURL: URL) async throws -> ImportedAudio {
        let copy = try copyIntoApp(pickedURL)
        do {
            return try await inspect(copy, pickedURL: pickedURL)
        } catch {
            Self.log.error("import failed for \(pickedURL.lastPathComponent, privacy: .public) (content \(Self.detectedExtension(of: copy) ?? "unknown", privacy: .public)): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// A copy whose extension does not match its content (an M4A saved as .mp3 by a converter)
    /// gets the extension of its content: AVAudioPlayer and AVAudioFile go by the name.
    private static func withMatchingExtension(_ url: URL) -> URL {
        guard let detected = detectedExtension(of: url), detected != url.pathExtension.lowercased() else { return url }
        let renamed = url.deletingPathExtension().appendingPathExtension(detected)
        try? FileManager.default.removeItem(at: renamed)
        guard (try? FileManager.default.moveItem(at: url, to: renamed)) != nil else { return url }
        log.notice("\(url.lastPathComponent, privacy: .public) is \(detected, privacy: .public) content; renamed")
        return renamed
    }

    /// The audio format of a file from its first bytes, as a file extension; nil when unknown.
    static func detectedExtension(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let bytes = try? handle.read(upToCount: 12), bytes.count >= 12 else { return nil }
        try? handle.close()
        let header = [UInt8](bytes)
        // ID3 tag, or an MPEG audio frame sync whose layer bits are set (ADTS AAC has layer 00).
        if header[0...2] == [0x49, 0x44, 0x33] || (header[0] == 0xFF && header[1] & 0xE0 == 0xE0 && header[1] & 0x06 != 0) {
            return "mp3"
        }
        if header[0] == 0xFF && header[1] & 0xF6 == 0xF0 { return "aac" }
        if header[4...7] == [0x66, 0x74, 0x79, 0x70] { return "m4a" }
        if header[0...3] == [0x52, 0x49, 0x46, 0x46] { return "wav" }
        if header[0...3] == [0x46, 0x4F, 0x52, 0x4D] { return "aiff" }
        if header[0...3] == [0x66, 0x4C, 0x61, 0x43] { return "flac" }
        if header[0...3] == [0x63, 0x61, 0x66, 0x66] { return "caf" }
        return nil
    }

    private func inspect(_ copy: URL, pickedURL: URL) async throws -> ImportedAudio {
        let asset = AVURLAsset(url: copy)
        let (duration, isProtected) = try await asset.load(.duration, .hasProtectedContent)
        guard !isProtected else { throw AudioImportError.protectedContent }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw AudioImportError.noAudio }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw AudioImportError.unreadable }
        let waveform = try await Task.detached(priority: .userInitiated) {
            try Self.readWaveform(asset: asset, track: track, duration: seconds)
        }.value
        let name = pickedURL.deletingPathExtension().lastPathComponent
        let (title, artist) = await Self.titleAndArtist(asset: asset, fileName: name)
        return ImportedAudio(url: copy, name: name, duration: seconds, waveform: waveform, title: title, artist: artist)
    }

    /// Title and artist tags when the file has both, otherwise a guess from the file name.
    private static func titleAndArtist(asset: AVAsset, fileName: String) async -> (String, String?) {
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func value(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
                  let text = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespaces), !text.isEmpty
            else { return nil }
            return text
        }
        let guess = SongTitleGuess.from(fileName: fileName)
        guard let title = await value(.commonIdentifierTitle) else { return (guess.title, guess.artist) }
        return (title, await value(.commonIdentifierArtist) ?? guess.artist)
    }

    /// Files from the picker are security-scoped and may vanish; work on a private copy.
    private func copyIntoApp(_ pickedURL: URL) throws -> URL {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }
        let directory = Self.importDirectory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(pickedURL.lastPathComponent)
        // A file in iCloud Drive (or another file provider) may not be on the device yet. Reading
        // it through a file coordinator downloads it first; a plain copy fails on it.
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: pickedURL, options: .withoutChanges, error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: destination) } catch { copyError = error }
        }
        if let failure = coordinationError ?? copyError {
            Self.log.error("import copy failed for \(pickedURL.lastPathComponent, privacy: .public): \(String(describing: failure), privacy: .public)")
            throw AudioImportError.unreadable
        }
        return Self.withMatchingExtension(destination)
    }

    private static func readWaveform(asset: AVAsset, track: AVAssetTrack, duration: TimeInterval) throws -> [Float] {
        guard let reader = try? AVAssetReader(asset: asset) else { throw AudioImportError.unreadable }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: analysisSampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        guard reader.canAdd(output) else { throw AudioImportError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw AudioImportError.unreadable }

        let samplesPerBin = max(1, Int(duration * analysisSampleRate) / waveformBins)
        var bins: [Float] = []
        var peak: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for value in data {
                peak = max(peak, abs(value))
                count += 1
                if count == samplesPerBin {
                    bins.append(peak)
                    peak = 0
                    count = 0
                }
            }
        }
        guard reader.status == .completed else { throw AudioImportError.unreadable }
        if count > 0 { bins.append(peak) }
        let loudest = bins.max() ?? 0
        return loudest > 0 ? bins.map { $0 / loudest } : bins
    }
}

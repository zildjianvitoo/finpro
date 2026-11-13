//
//  CompingViewModel.swift
//  finpro
//
//  Runs the export and the Save to Photos action for ExportPreviewView. Owner: Zildjian Vito (ZV-13).
//

import CoreGraphics
import Foundation
import Observation

@Observable
final class CompingViewModel {
    enum ExportState: Equatable {
        case idle
        case exporting(progress: Double)
        case finished(URL)
        case failed(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case denied
        case failed(String)
    }

    /// One take of the cover, with the part of the song it covers.
    struct Clip: Identifiable, Equatable {
        /// The segment index.
        let id: Int
        let start: TimeInterval
        let end: TimeInterval
        /// Sung below the pass threshold: marked "Needs Retake".
        let needsRetake: Bool
    }

    let plan: CompingCompositionPlan
    /// "Artist - Title" of the imported song, when known.
    let songName: String?
    private(set) var exportState: ExportState = .idle
    private(set) var saveState: SaveState = .idle
    /// A frame of each clip, by segment index; filled once the cover is exported.
    private(set) var thumbnails: [Int: CGImage] = [:]
    private(set) var selectedClipID: Int?

    private let useCase: AutoCompingVideoUseCase
    private let videoLibrary: any VideoLibrarySaving
    private let onExported: (URL) -> Void
    /// The cover was saved to Photos (the user's way of finishing it).
    private let onSavedToPhotos: () -> Void
    private let thumbnailProvider: any ClipThumbnailProviding
    private let passThreshold: Float

    init(plan: CompingCompositionPlan, songName: String? = nil, useCase: AutoCompingVideoUseCase,
         videoLibrary: any VideoLibrarySaving,
         thumbnailProvider: any ClipThumbnailProviding = AVClipThumbnailProvider(),
         passThreshold: Float = AppConfiguration().passThreshold,
         onExported: @escaping (URL) -> Void = { _ in },
         onSavedToPhotos: @escaping () -> Void = {}) {
        self.plan = plan
        self.songName = songName
        self.useCase = useCase
        self.videoLibrary = videoLibrary
        self.thumbnailProvider = thumbnailProvider
        self.passThreshold = passThreshold
        self.onExported = onExported
        self.onSavedToPhotos = onSavedToPhotos
        selectedClipID = plan.validTakes.first?.segmentIndex
    }

    var title: String { songName ?? "Your cover" }

    var clips: [Clip] {
        plan.validTakes.compactMap { take in
            plan.segments.first { $0.index == take.segmentIndex }
                .map { Clip(id: $0.index, start: $0.audioStartTime, end: $0.audioEndTime,
                            needsRetake: take.accuracyScore < passThreshold) }
        }
    }

    /// The session ended before the last segment, so recording can go on (Continue Recording).
    var canContinueRecording: Bool { plan.isPartial }

    /// "2:18 • 5 clips"
    var subtitle: String {
        let count = clips.count
        return "\(Self.format(plan.endTime)) • \(count) \(count == 1 ? "clip" : "clips")"
    }

    /// "00:13-00:17"
    func timeRange(of clip: Clip) -> String {
        "\(Self.clock(clip.start))-\(Self.clock(clip.end))"
    }

    func selectClip(_ id: Int) {
        selectedClipID = id
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    /// Minutes and seconds, both with two digits ("01:05").
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var summary: String {
        let passed = plan.validTakes.count, total = plan.segments.count
        return plan.isPartial ? "Partial cover · \(passed) of \(total) segments" : "Full cover · \(total) segments"
    }

    var exportedURL: URL? {
        if case .finished(let url) = exportState { url } else { nil }
    }

    /// False while running on fakes: the fake export returns a URL without writing a file.
    var hasPlayableFile: Bool {
        exportedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func export() async {
        if case .exporting = exportState { return }
        exportState = .exporting(progress: 0)
        saveState = .idle
        do {
            // The view model is MainActor-isolated (so Sendable); holding it until the export ends is fine.
            let url = try await useCase.export(plan) { progress in
                Task { @MainActor in
                    guard case .exporting = self.exportState else { return }
                    self.exportState = .exporting(progress: progress)
                }
            }
            if FileManager.default.fileExists(atPath: url.path) { onExported(url) }
            exportState = .finished(url)
            await loadThumbnails(from: url)
        } catch {
            exportState = .failed(String(describing: error))
        }
    }

    /// A frame from the middle of each clip.
    private func loadThumbnails(from url: URL) async {
        let clips = clips
        let frames = await thumbnailProvider.thumbnails(for: url, at: clips.map { ($0.start + $0.end) / 2 })
        for (clip, frame) in zip(clips, frames) {
            if let frame { thumbnails[clip.id] = frame }
        }
    }

    func saveToPhotos() async {
        guard let url = exportedURL, saveState != .saving else { return }
        saveState = .saving
        do {
            try await videoLibrary.saveVideo(at: url)
            saveState = .saved
            onSavedToPhotos()
        } catch VideoLibraryError.accessDenied {
            saveState = .denied
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}

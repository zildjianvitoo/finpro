//
//  CoverLibrary.swift
//  finpro
//

import Foundation
import Observation

@Observable
final class CoverLibrary {
    private(set) var covers: [SavedCover] = []
    private(set) var error: UserFacingError?
    @ObservationIgnored private let store: CoverLibraryStore
    @ObservationIgnored private var loadFailed = false
    init(store: CoverLibraryStore = CoverLibraryStore()) {
        self.store = store
        do { covers = try store.load() }
        catch { loadFailed = true; self.error = .coverLibraryFailed }
    }
    func url(for cover: SavedCover) -> URL { store.url(for: cover) }
    /// Saves an exported cover. With `replacing`, that cover (an earlier export of the same
    /// cover, before a retake or continue) is swapped for the new file instead of kept twice.
    /// Returns the saved cover's id, or nil when it could not be saved.
    @discardableResult
    func save(_ source: URL, title: String?, duration: TimeInterval, isDraft: Bool, replacing oldID: UUID? = nil) -> UUID? {
        guard !loadFailed else { return nil }
        let old = covers.first { $0.id == oldID }
        let others = covers.filter { $0.id != oldID }
        let id = UUID()
        let cover = SavedCover(id: id, title: old?.title ?? title ?? "Cover \(others.count + 1)", date: Date(),
                               duration: duration, isDraft: isDraft, filename: id.uuidString + ".mp4")
        let records = [cover] + others
        do {
            try store.save(cover, source: source, records: records)
            covers = records
            error = nil
            if let old { store.removeFile(of: old) }
            return id
        } catch {
            self.error = .coverLibraryFailed
            return nil
        }
    }
}

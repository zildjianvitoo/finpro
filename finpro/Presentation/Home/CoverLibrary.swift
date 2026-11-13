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

    /// Marks a saved cover as a draft (the user chose Save to Draft).
    func markDraft(_ id: UUID) {
        guard !loadFailed, let index = covers.firstIndex(where: { $0.id == id }), !covers[index].isDraft else { return }
        let old = covers[index]
        var records = covers
        records[index] = SavedCover(id: old.id, title: old.title, date: old.date, duration: old.duration,
                                    isDraft: true, filename: old.filename)
        do { try store.saveManifest(records); covers = records; error = nil }
        catch { self.error = .coverLibraryFailed }
    }

    /// Removes a saved cover and its video file (the user chose Discard).
    func delete(_ id: UUID) {
        guard !loadFailed, let cover = covers.first(where: { $0.id == id }) else { return }
        let records = covers.filter { $0.id != id }
        do { try store.saveManifest(records); covers = records; store.removeFile(of: cover); error = nil }
        catch { self.error = .coverLibraryFailed }
    }
}

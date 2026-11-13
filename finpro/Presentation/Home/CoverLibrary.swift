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
    func save(_ source: URL, title: String?, duration: TimeInterval, isDraft: Bool) {
        guard !loadFailed else { return }
        let id = UUID()
        let cover = SavedCover(id: id, title: title ?? "Cover \(covers.count + 1)", date: Date(),
                               duration: duration, isDraft: isDraft, filename: id.uuidString + ".mp4")
        let records = [cover] + covers
        do { try store.save(cover, source: source, records: records); covers = records; error = nil }
        catch { self.error = .coverLibraryFailed }
    }
}

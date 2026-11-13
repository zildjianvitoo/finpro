// Standalone integration checks for persistent songs, selection, playback and one recommended key.
import Foundation

nonisolated final class SelectionPreviewSpy: AudioPreviewing {
    var position: TimeInterval?
    var playedURL: URL?
    var currentTime: TimeInterval? { position }
    func play(_ url: URL, from start: TimeInterval) throws { playedURL = url; position = start }
    func play(_ url: URL, excerpt: ClosedRange<TimeInterval>, onCompletion: @escaping @Sendable () -> Void) async throws {
        playedURL = url; position = excerpt.lowerBound
    }
    func stop() { position = nil; playedURL = nil }
}
nonisolated struct SelectionInspector: AudioFileInspecting {
    let audio: ImportedAudio
    func importFile(at url: URL) async throws -> ImportedAudio {
        if url.lastPathComponent == "slow" { try? await Task.sleep(for: .milliseconds(120)) }
        return ImportedAudio(url: audio.url, name: url.lastPathComponent, duration: audio.duration,
                             waveform: audio.waveform, title: audio.title, artist: audio.artist)
    }
}
nonisolated struct SelectionLyrics: LyricsProviding {
    let value: SongLyrics
    func lyrics(title: String, artist: String?, duration: TimeInterval) async throws -> SongLyrics? { value }
}
actor SelectionPipeline: StemSeparationRepository, AudioAnalysisRepository, AudioTranspositionRepository {
    var separated = 0
    var analyzed: [URL] = []
    var renders: [(URL, Int)] = []
    func separateStems(from url: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        separated += 1
        return SeparatedStems(mixURL: URL(fileURLWithPath: "/mix"), vocalGuideURL: URL(fileURLWithPath: "/vocals"),
                              instrumentalURL: URL(fileURLWithPath: "/backing"), method: .coreML)
    }
    func extractVocalGuideNotes(from url: URL) async throws -> [TargetMIDINote] {
        analyzed.append(url)
        return [TargetMIDINote(midiNote: 62, startTime: 1, duration: 1),
                TargetMIDINote(midiNote: 66, startTime: 3, duration: 1)]
    }
    func renderTransposed(_ url: URL, semitones: Int) async throws -> URL {
        renders.append((url, semitones))
        return url.appendingPathExtension("key\(semitones)")
    }
}
@main struct SongSelectionChecks {
    @MainActor static var count = 0
    @MainActor static func check(_ condition: Bool, _ message: String) {
        count += 1
        precondition(condition, message)
    }
    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<5000 { if condition() { return }; await Task.yield() }
        preconditionFailure("Async operation did not settle")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.m4a")
        try Data([1, 2, 3]).write(to: source)
        let audio = ImportedAudio(url: source, name: "Original file", duration: 100,
                                  waveform: [0.2, 0.8, 0.5], title: "Actual song title", artist: "Artist")
        let lines = [LyricLine(id: 0, text: "first line", start: 10, end: 20, words: []),
                     LyricLine(id: 1, text: "second line", start: 20, end: 35, words: [])]
        let lyrics = SongLyrics(lines: lines, chorus: 0..<2, matchedTitle: "Actual song title", matchedArtist: "Artist")
        let store = SongLibraryStore(directory: directory.appendingPathComponent("saved"))
        let library = SongLibrary(store: store)
        let first = try library.save(audio: audio, existingID: nil, start: 10, length: 30, lyrics: lyrics)
        let second = try library.save(audio: audio, existingID: nil, start: 0, length: 15, lyrics: nil)
        check(first.title == "Song 1" && second.title == "Song 2", "Default names increment")
        library.rename(first.id, title: "  My song  ")
        check(library.songs.first { $0.id == first.id }?.title == "My song", "Rename trims whitespace")
        check(library.songs.first { $0.id == first.id }?.sourceTitle == "Actual song title", "Renaming preserves lyric lookup metadata")
        let reloaded = SongLibrary(store: store)
        check(reloaded.songs.count == 2 && reloaded.songs.last?.lyrics == lyrics, "Songs and timed lyrics survive reload")
        check(reloaded.songs.last?.selectionStart == 10, "Selection survives reload")
        let preview = SelectionPreviewSpy()
        let list = SongListViewModel(library: library, previewer: preview)
        list.play(first)
        check(list.expandedID == first.id && list.playingID == first.id,
              "Row tap expands and plays without opening a section sheet")
        preview.position = 8
        list.play(first)
        check(preview.currentTime == 8, "Repeated row tap preserves playback position")
        list.stop()
        list.query = "my SONG"
        check(list.songs.map(\.id) == [first.id], "Search ignores case")
        list.toggleSelectionMode(); list.select(second.id); list.delete(list.selectedIDs)
        check(library.songs.map(\.id) == [first.id], "Bulk delete removes only selected records")
        let third = try library.save(audio: audio, existingID: nil, start: 0, length: 15, lyrics: nil)
        check(third.title == "Song 3", "Deleting does not reuse song numbers")
        check(!FileManager.default.fileExists(atPath: store.url(for: second).path), "Deleting removes the saved media")
        let updated = try library.save(audio: audio, existingID: first.id, start: 20, length: 25, lyrics: lyrics)
        check(updated.title == "My song" && library.songs.count == 2, "Editing a section preserves identity and name")
        let pipeline = SelectionPipeline()
        let useCase = PrepareSongUseCase(separation: pipeline, analysis: pipeline, fallbackAnalysis: nil, transposition: pipeline)
        var handedOff: PrepareSongUseCase.Choices?
        var deliveredName: String?
        var savedCallback = false
        let model = ImportSongViewModel(inspector: SelectionInspector(audio: audio), lyrics: SelectionLyrics(value: lyrics),
            previewer: preview, prepare: useCase, vocalRange: { VocalRange(lowestMIDI: 60, highestMIDI: 76) },
            library: library, initialSong: updated, onSavedToList: { savedCallback = true },
            onPrepared: { choices, _, name in handedOff = choices; deliveredName = name })
        model.openInitialSong()
        check(model.selectionStart == 20 && preview.currentTime == 20 && model.isPlayingSelection, "Opening saved song autoplays its saved part")
        model.selectLyric(lines[0])
        check(model.selectionStart == 10 && preview.currentTime == 10, "Tapping a lyric seeks the selection and preview")
        model.selectLyric(lines[1], extending: true)
        check(model.selectionLength == 25, "Lyrics can set the end of the section")
        preview.position = 35.1
        try await Task.sleep(for: .milliseconds(90))
        check(preview.currentTime == 10 && model.playbackTime == 10, "Preview loops at the actual media-clock boundary")
        model.saveToSongList()
        check(savedCallback && library.songs.count == 2, "Save to list does not duplicate an existing song")
        model.prepareSelection()
        await waitUntil { model.status == .prepared }
        model.continueWithPreparedSong()
        check(handedOff?.options.count == 1, "Only one recommendation is prepared")
        check(deliveredName == "My song", "User's edited title reaches the recording flow")
        let separationCount = await pipeline.separated
        let analyzed = await pipeline.analyzed
        let renders = await pipeline.renders
        check(separationCount == 1 && analyzed == [URL(fileURLWithPath: "/vocals")], "Pitch analysis uses the separated vocal stem")
        check(renders.count == 2 && renders[0].0.path == "/mix" && renders[1].0.path == "/backing", "Only one mix and one backing track are rendered")
        let choices = handedOff!
        check(choices.options[0].song.transposition.semitoneShift == 4, "Best key centers the section's lowest and highest notes")
        var chosen: PreparedSong?
        let keys = KeySelectionViewModel(choices: choices, previewer: preview,
            renderer: RenderSongKeyUseCase(transposition: pipeline), automaticallySelectRecommended: true,
            onChoose: { chosen = $0 })
        check(keys.selectedShift == 4 && keys.selectedSong != nil, "Recommended key starts selected")
        keys.autoplaySelected()
        await waitUntil { preview.playedURL != nil }
        keys.autoplaySelected()
        check(keys.isManualPreviewPlaying, "Repeated screen entry does not stop key autoplay")
        check(preview.playedURL == choices.options[0].song.earphoneMixURL,
              "Key preview includes the transposed reference vocal and backing mix")
        model.suspend(); list.stop()
        check(preview.playedURL == choices.options[0].song.earphoneMixURL,
              "Leaving a silent old screen cannot stop the new screen's preview")
        keys.chooseShift(0); keys.chooseShift(-3)
        try await Task.sleep(for: .milliseconds(280))
        check(keys.selectedShift == -3 && keys.selectedSong?.transposition.semitoneShift == -3, "Latest slider choice wins")
        check(!keys.fitsRange, "Manual keys beyond the tested range are identified")
        keys.confirm()
        check(chosen?.transposition.semitoneShift == -3, "Confirmed key reaches the next step unchanged")
        let stale = ImportSongViewModel(inspector: SelectionInspector(audio: audio), lyrics: SelectionLyrics(value: lyrics),
            previewer: preview, prepare: useCase, vocalRange: { nil }, onPrepared: { _, _, _ in })
        stale.picked(.success(URL(fileURLWithPath: "/slow")))
        await Task.yield()
        stale.picked(.success(URL(fileURLWithPath: "/latest")))
        try await Task.sleep(for: .milliseconds(170))
        check(stale.audio?.name == "latest", "An older import cannot overwrite the latest choice")
        stale.suspend(); model.suspend(); keys.stop(); list.stop()
        try FileManager.default.removeItem(at: source)
        check(FileManager.default.fileExists(atPath: library.audio(for: updated).url.path), "Saved media survives temporary import deletion")
        let latest = SongLibrary(store: store)
        check(latest.songs.count == 2 && latest.songs.last?.title == "My song", "Persisted edits survive a fresh library instance")
        let coverSource = directory.appendingPathComponent("export.mp4")
        try Data([4, 5, 6]).write(to: coverSource)
        let coverStore = CoverLibraryStore(directory: directory.appendingPathComponent("covers"))
        let covers = CoverLibrary(store: coverStore)
        covers.save(coverSource, title: "My cover", duration: 25, isDraft: false)
        covers.save(coverSource, title: "Partial cover", duration: 15, isDraft: true)
        try FileManager.default.removeItem(at: coverSource)
        let restoredCovers = CoverLibrary(store: coverStore)
        check(restoredCovers.covers.count == 2 && restoredCovers.covers.first?.isDraft == true,
              "Finished and partial covers survive reload")
        check(restoredCovers.covers.allSatisfy { FileManager.default.fileExists(atPath: restoredCovers.url(for: $0).path) },
              "Cover files survive session cleanup")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (offset, label) in [(-1, "Yesterday"), (0, "Today"), (1, "Tomorrow")] {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            check(RelativeSongDate.text(for: date, relativeTo: now, calendar: calendar) == label,
                  "Relative song dates use calendar days")
        }
        for offset in [-2, 2, -365] {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            let expected = DateFormatter()
            expected.locale = Locale(identifier: "en_US")
            expected.calendar = calendar
            expected.timeZone = calendar.timeZone
            expected.dateStyle = .medium
            check(RelativeSongDate.text(for: date, relativeTo: now, calendar: calendar,
                                       locale: expected.locale) == expected.string(from: date),
                  "Dates outside yesterday/today/tomorrow use a calendar date")
        }
        check(model.waveformInterval.lowerBound <= model.selectionStart
              && model.waveformInterval.upperBound >= model.selectionStart + model.selectionLength,
              "Waveform viewport contains the entire chosen section")
        print("PASS SongSelectionChecks (\(count) checks)")
    }
}

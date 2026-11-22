//
//  SongSectionLyrics.swift
//  finpro
//

import SwiftUI

struct SongSectionLyrics: View {
    static let lineHeight: CGFloat = 24
    @Bindable var viewModel: ImportSongViewModel
    /// Lyric colour: plum with the surrounding lines at half strength (design 4.4).
    var tint: Color = .primaryBrand
    var dimmedOpacity = 0.5
    /// Scroll position of the lyrics; one line is `lineHeight` tall, so line `i` is in the middle
    /// at offset `i × lineHeight` (the content has one line of space above the first line).
    @State private var position = ScrollPosition(idType: Int.self)
    /// Index of the line in the middle of the lyrics.
    @State private var centeredIndex: Int?
    /// A finger is scrolling the lyrics (not the lyrics following the song).
    @State private var userScrolling = false
    var body: some View {
        Group {
            switch viewModel.lyrics {
            case .found(let song):
                lyricsList(song)
            case .loading:
                // Searching can take a few seconds (a busy lyrics service is retried).
                VStack(spacing: AppSpacing.small) {
                    LoadingMascotView(size: AppLayout.loadingMascotCompact)
                    LoadingTextView(title: viewModel.isIdentifyingSong ? "Identifying song…" : "Finding lyrics…", font: .appSubheadline, shadowed: false)
                }
                .foregroundStyle(Color.plumInk.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            case .idle: Color.clear
            case .notFound: search(.lyricsNotFound)
            case .failed(let error): search(error)
            }
        }
        .frame(maxWidth: .infinity).frame(height: Self.lineHeight * 3)
    }

    private func lyricsList(_ song: SongLyrics) -> some View {
        let activeID = highlightedLineID(in: song.lines)
        return ScrollView {
            // Lines sit close together and three show at once (design 4.3).
            LazyVStack(spacing: 0) {
                ForEach(song.lines) { line in
                    lyricRow(line, isHighlighted: line.id == activeID)
                }
            }
            .padding(.vertical, Self.lineHeight)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Int.self) { geometry in
            Int(((geometry.contentOffset.y + geometry.contentInsets.top) / Self.lineHeight).rounded())
        } action: { _, index in centeredIndex = index }
        .onScrollPhaseChange { _, phase in handleScrollPhase(phase, lines: song.lines) }
        // A light picker tick for each lyric line that passes the center while scrolling.
        .sensoryFeedback(.selection, trigger: clampedCenteredIndex(in: song.lines)) { old, new in
            userScrolling && old != nil && new != nil
        }
        // While the user scrolls, the line in the middle starts the selection (the
        // waveform follows live).
        .onChange(of: centeredIndex) { _, index in
            guard userScrolling, let index, !song.lines.isEmpty else { return }
            let line = song.lines[min(max(index, 0), song.lines.count - 1)]
            viewModel.selectionStart = min(line.start, viewModel.maximumStart)
        }
        // Otherwise the lyrics follow the song: the line being played, or the selection's
        // first line after the waveform moved.
        .onChange(of: viewModel.activeLineID) { _, id in follow(id, in: song.lines) }
        .onChange(of: viewModel.firstSelectedLineID) { _, id in
            if viewModel.activeLineID == nil { follow(id, in: song.lines) }
        }
        .onAppear { follow(viewModel.firstSelectedLineID, in: song.lines, animated: false) }
    }

    private func lyricRow(_ line: LyricLine, isHighlighted: Bool) -> some View {
        Button { viewModel.selectLyric(line) } label: {
            Text(text(line, isHighlighted: isHighlighted))
                .font(.appHeadline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: Self.lineHeight)
        }
        .buttonStyle(.plain)
        .id(line.id)
        .contextMenu {
            Button("Start selection here") { viewModel.selectLyric(line) }
            Button("End selection here") { viewModel.selectLyric(line, extending: true) }
        }
    }

    private func handleScrollPhase(_ phase: ScrollPhase, lines: [LyricLine]) {
        if phase == .interacting, !userScrolling {
            userScrolling = true
            viewModel.beginSelectionEditing()
        } else if phase == .idle, userScrolling {
            userScrolling = false
            // Settle on the line in the middle, like Instagram's lyric picker, then
            // play the preview from it. (Not `.viewAligned`: its snapping put
            // programmatic scrolls a line off.)
            if !lines.isEmpty, let centeredIndex {
                let clamped = min(max(centeredIndex, 0), lines.count - 1)
                let line = lines[clamped]
                viewModel.selectionStart = min(line.start, viewModel.maximumStart)
                withAnimation(.easeOut(duration: 0.2)) {
                    position.scrollTo(y: CGFloat(clamped) * Self.lineHeight)
                }
            }
            viewModel.endSelectionEditing()
        }
    }

    /// Scrolls so the line is in the middle, unless a finger is on the lyrics.
    private func follow(_ id: Int?, in lines: [LyricLine], animated: Bool = true) {
        guard let id, !userScrolling, let index = lines.firstIndex(where: { $0.id == id }),
              index != centeredIndex else { return }
        withAnimation(animated ? .easeInOut(duration: 0.25) : nil) {
            position.scrollTo(y: CGFloat(index) * Self.lineHeight)
        }
    }

    private func clampedCenteredIndex(in lines: [LyricLine]) -> Int? {
        guard !lines.isEmpty, let centeredIndex else { return nil }
        return min(max(centeredIndex, 0), lines.count - 1)
    }

    private func highlightedLineID(in lines: [LyricLine]) -> Int? {
        if userScrolling, let index = clampedCenteredIndex(in: lines) {
            return lines[index].id
        }
        return viewModel.activeLineID ?? viewModel.firstSelectedLineID
    }

    private func text(_ line: LyricLine, isHighlighted: Bool) -> AttributedString {
        var text = AttributedString(line.text)
        text.foregroundColor = isHighlighted ? tint : tint.opacity(dimmedOpacity)
        return text
    }
    /// Fits the three-line lyrics area, so the sheet keeps its height when no lyrics are found.
    private func search(_ error: UserFacingError) -> some View {
        VStack(spacing: AppSpacing.tiny) {
            Text("\(error.title). Search by title, or pick a part on the waveform.")
                .font(.appCaption2).foregroundStyle(Color.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: AppSpacing.small) {
                TextField("Song title", text: $viewModel.lyricsTitle)
                    .font(.appSubheadline).submitLabel(.search)
                    .onSubmit { viewModel.searchLyrics() }
                    .padding(.horizontal, AppSpacing.medium).frame(height: 36)
                    .background(Color.searchField.opacity(0.8), in: Capsule())
                Button { viewModel.searchLyrics() } label: { Image(systemName: "magnifyingglass") }
                    .foregroundStyle(Color.primaryBrand)
                    .accessibilityLabel("Search lyrics")
            }
        }
    }
}

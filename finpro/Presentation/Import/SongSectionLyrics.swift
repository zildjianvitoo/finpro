//
//  SongSectionLyrics.swift
//  finpro
//

import SwiftUI

struct SongSectionLyrics: View {
    private static let viewportHeight: CGFloat = 215
    private static let rowPadding = AppSpacing.small
    private static let scrollSpace = "song-section-lyrics"

    private nonisolated struct RowCenters: PreferenceKey {
        static let defaultValue: [Int: CGFloat] = [:]

        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { _, next in next })
        }
    }

    @Bindable var viewModel: ImportSongViewModel
    /// Lyric colour: plum with the surrounding lines at half strength (design 4.4).
    var tint: Color = .primaryBrand
    var dimmedOpacity = 0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var userScrolling = false

    @State private var centeredID: Int?

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
        .frame(maxWidth: .infinity, minHeight: Self.viewportHeight, maxHeight: Self.viewportHeight)
    }

    private func lyricsList(_ song: SongLyrics) -> some View {
        let activeID = userScrolling ? centeredID : viewModel.activeLineID ?? viewModel.firstSelectedLineID
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(song.lines) { line in
                    lyricRow(line, isHighlighted: line.id == activeID)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Self.viewportHeight / 2 - Self.rowPadding)
        }
        .scrollIndicators(.hidden)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
            }
        }
        .scrollPosition($position, anchor: .center)
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(RowCenters.self) { centers in
            let midpoint = Self.viewportHeight / 2
            centeredID = centers.min {
                abs($0.value - midpoint) < abs($1.value - midpoint)
            }?.key
        }
        .onScrollPhaseChange { _, phase in handleScrollPhase(phase, lines: song.lines) }
        .sensoryFeedback(.selection, trigger: centeredID) { old, new in
            userScrolling && old != nil && new != nil
        }
        .onChange(of: centeredID) { _, id in
            guard userScrolling, let line = song.lines.first(where: { $0.id == id }) else { return }
            viewModel.selectionStart = min(line.start, viewModel.maximumStart)
        }
        .onChange(of: viewModel.activeLineID) { _, id in follow(id) }
        .onChange(of: viewModel.firstSelectedLineID) { _, id in
            if viewModel.activeLineID == nil { follow(id) }
        }
        .onAppear { follow(viewModel.firstSelectedLineID, animated: false) }
    }

    private func lyricRow(_ line: LyricLine, isHighlighted: Bool) -> some View {
        Button { viewModel.selectLyric(line) } label: {
            Text(text(line, isHighlighted: isHighlighted))
                .font(.appTitle2.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, Self.rowPadding)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: RowCenters.self, value: [
                    line.id: proxy.frame(in: .named(Self.scrollSpace)).midY
                ])
            }
        }
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
            if let id = centeredID, let line = lines.first(where: { $0.id == id }) {
                viewModel.selectionStart = min(line.start, viewModel.maximumStart)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    position.scrollTo(id: id, anchor: .center)
                }
            }
            viewModel.endSelectionEditing()
        }
    }

    private func follow(_ id: Int?, animated: Bool = true) {
        guard let id, !userScrolling, id != centeredID else { return }
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.25) : nil) {
            position.scrollTo(id: id, anchor: .center)
        }
    }

    private func text(_ line: LyricLine, isHighlighted: Bool) -> AttributedString {
        var text = AttributedString(line.text)
        text.foregroundColor = isHighlighted ? tint : tint.opacity(dimmedOpacity)
        return text
    }
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

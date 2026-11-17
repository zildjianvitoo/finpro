//
//  SongSectionLyrics.swift
//  finpro
//

import SwiftUI

struct SongSectionLyrics: View {
    static let lineHeight: CGFloat = 24
    @Bindable var viewModel: ImportSongViewModel
    var body: some View {
        Group {
            switch viewModel.lyrics {
            case .found(let song):
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lines sit close together and three show at once (design 4.3).
                        LazyVStack(spacing: 0) {
                            ForEach(song.lines) { line in
                                Button { viewModel.selectLyric(line) } label: {
                                    Text(text(line)).font(.appHeadline)
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                        .frame(maxWidth: .infinity, minHeight: Self.lineHeight)
                                }
                                .buttonStyle(.plain).id(line.id)
                                .contextMenu {
                                    Button("Start selection here") { viewModel.selectLyric(line) }
                                    Button("End selection here") { viewModel.selectLyric(line, extending: true) }
                                }
                            }
                        }
                        .padding(.vertical, Self.lineHeight)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: viewModel.activeLineID) { _, id in
                        if let id { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                    .onAppear { if let id = viewModel.firstSelectedLineID { proxy.scrollTo(id, anchor: .center) } }
                }
            case .loading:
                // Searching can take a few seconds (a busy lyrics service is retried).
                HStack(spacing: AppSpacing.small) {
                    ProgressView()
                    Text(viewModel.isIdentifyingSong ? "Identifying song…" : "Finding lyrics…").font(.appSubheadline)
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

    private func text(_ line: LyricLine) -> AttributedString {
        var text = AttributedString(line.text)
        text.foregroundColor = line.id == (viewModel.activeLineID ?? viewModel.firstSelectedLineID)
            ? .plumInk : .plumInk.opacity(0.28)
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
                    .background(.white.opacity(0.8), in: Capsule())
                Button { viewModel.searchLyrics() } label: { Image(systemName: "magnifyingglass") }
                    .foregroundStyle(Color.primaryBrand)
                    .accessibilityLabel("Search lyrics")
            }
        }
    }
}

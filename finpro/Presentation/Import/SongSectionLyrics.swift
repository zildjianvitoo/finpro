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
                    Text("Finding lyrics…").font(.appSubheadline)
                }
                .foregroundStyle(Color.plumInk.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            case .idle: Color.clear
            case .notFound: search(.lyricsNotFound)
            case .failed(let error): search(error)
            }
        }
        .frame(maxWidth: .infinity).frame(height: showsSearch ? 120 : Self.lineHeight * 3)
    }

    private var showsSearch: Bool {
        switch viewModel.lyrics {
        case .notFound, .failed: true
        default: false
        }
    }

    private func text(_ line: LyricLine) -> AttributedString {
        var text = AttributedString(line.text)
        text.foregroundColor = line.id == (viewModel.activeLineID ?? viewModel.firstSelectedLineID)
            ? .plumInk : .plumInk.opacity(0.28)
        return text
    }
    private func search(_ error: UserFacingError) -> some View {
        VStack(spacing: 6) {
            Text(error.title).font(.appCaption).foregroundStyle(Color.secondaryText)
            HStack {
                TextField("Song title", text: $viewModel.lyricsTitle)
                    .textFieldStyle(.roundedBorder).submitLabel(.search)
                    .onSubmit { viewModel.searchLyrics() }
                Button { viewModel.searchLyrics() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search lyrics")
            }
            Text("You can still choose a part with the waveform.")
                .font(.appCaption2).foregroundStyle(Color.secondaryText)
        }
    }
}

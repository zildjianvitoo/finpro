//
//  SongSectionLyrics.swift
//  finpro
//

import SwiftUI

struct SongSectionLyrics: View {
    @Bindable var viewModel: ImportSongViewModel
    var body: some View {
        Group {
            switch viewModel.lyrics {
            case .found(let song):
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(song.lines) { line in
                                Button { viewModel.selectLyric(line) } label: {
                                    Text(text(line)).font(.appHeadline)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain).id(line.id)
                                .contextMenu {
                                    Button("Start selection here") { viewModel.selectLyric(line) }
                                    Button("End selection here") { viewModel.selectLyric(line, extending: true) }
                                }
                            }
                        }
                        .padding(.vertical, 32)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: viewModel.activeLineID) { _, id in
                        if let id { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                    .onAppear { if let id = viewModel.firstSelectedLineID { proxy.scrollTo(id, anchor: .center) } }
                }
            case .loading: Color.clear
            case .idle: Color.clear
            case .notFound: search(.lyricsNotFound)
            case .failed(let error): search(error)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 120)
    }

    private func text(_ line: LyricLine) -> AttributedString {
        var text = AttributedString(line.text)
        text.foregroundColor = line.id == (viewModel.activeLineID ?? viewModel.firstSelectedLineID)
            ? .primaryBrand : .secondaryText.opacity(0.65)
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

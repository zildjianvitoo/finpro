//
//  SongListView.swift
//  finpro
//

import SwiftUI

struct SongListView: View {
    @State var viewModel: SongListViewModel
    let onBack: () -> Void
    let onAdd: () -> Void
    let onOpen: (SavedSong) -> Void
    @State private var renaming: SavedSong?
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.tinted)).accessibilityLabel("Back")
                Spacer()
                Button(viewModel.selecting ? "Cancel" : "Select", action: viewModel.toggleSelectionMode)
                    .buttonStyle(AppChipButtonStyle(selected: viewModel.selecting))
                    .disabled(viewModel.library.songs.isEmpty)
                Button(action: onAdd) { Image(systemName: "plus") }
                    .buttonStyle(.appIcon(.primary)).accessibilityLabel("Add a song")
            }
            .padding(.horizontal, 16)
            Text("Song List").font(.appTitle1).foregroundStyle(Color.primaryDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            if viewModel.songs.isEmpty {
                ContentUnavailableView(viewModel.query.isEmpty ? "No songs yet" : "No matching songs",
                                       systemImage: "music.note.list",
                                       description: Text(viewModel.query.isEmpty ? "Tap + to add your first song." : "Try a different song name."))
            } else {
                List {
                    ForEach(viewModel.songs) { song in
                        row(song)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 3, leading: 24, bottom: 3, trailing: 24))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", role: .destructive) { viewModel.delete([song.id]) }
                            }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            if let error = viewModel.library.error ?? viewModel.error {
                Text(error.title).font(.appCaption).foregroundStyle(Color.primaryBrand).padding(12)
            }
            if viewModel.selecting {
                HStack {
                    Spacer()
                    Button(role: .destructive) { viewModel.delete(viewModel.selectedIDs) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.appIcon(.tinted)).disabled(viewModel.selectedIDs.isEmpty)
                    .accessibilityLabel("Delete selected songs")
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search", text: $viewModel.query).autocorrectionDisabled()
                    if !viewModel.query.isEmpty {
                        Button { viewModel.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search")
                    }
                }
                .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                .padding(12).background(.white.opacity(0.8), in: Capsule())
                .padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewModel.stop() } }
        .onChange(of: nameFocused) { _, focused in
            if !focused { finishRename() }
        }
    }

    private func beginRename(_ song: SavedSong) {
        renaming = song
        name = song.title
        nameFocused = true
    }
    private func finishRename() {
        if let song = renaming { viewModel.library.rename(song.id, title: name) }
        renaming = nil
    }

    private func row(_ song: SavedSong) -> some View {
        let expanded = viewModel.expandedID == song.id && !viewModel.selecting
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                if viewModel.selecting {
                    Image(systemName: viewModel.selectedIDs.contains(song.id) ? "circle.fill" : "circle")
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: AppSpacing.tiny) {
                        if renaming?.id == song.id {
                            TextField("Song name", text: $name).font(.appSubheadline)
                                .focused($nameFocused).submitLabel(.done)
                                .onSubmit { finishRename(); nameFocused = false }
                        } else { Text(song.title).font(.appSubheadline).lineLimit(1)
                            .layoutPriority(1) }
                        if expanded {
                            Button { beginRename(song) } label: { Image(systemName: "pencil.line") }
                                .accessibilityLabel("Rename \(song.title)")
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(RelativeSongDate.text(for: song.createdAt))
                        Spacer()
                        Text(Duration.seconds(song.duration), format: .time(pattern: .minuteSecond))
                    }
                    .font(.appCaption2).foregroundStyle(Color.secondaryText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.selecting { viewModel.select(song.id) }
                else { viewModel.play(song) }
            }
            if expanded {
                ProgressView(value: viewModel.playingID == song.id ? viewModel.playbackTime / max(1, song.duration) : 0)
                    .tint(Color.primaryBrand)
                HStack {
                    Spacer()
                    Button { viewModel.togglePlayback(song) } label: {
                        Image(systemName: viewModel.playingID == song.id ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(viewModel.playingID == song.id ? "Pause song" : "Play song")
                    Spacer()
                    Button { viewModel.stop(); onOpen(song) } label: { Image(systemName: "waveform") }
                        .accessibilityLabel("Choose song section")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primaryBrand)
        .padding(12)
        .background(expanded ? Color.secBrand : Color.secondaryButton, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Select") { viewModel.beginSelecting(song.id) }
            Button("Rename") { beginRename(song) }
            Button("Choose song section") { viewModel.stop(); onOpen(song) }
            Button("Play") { viewModel.togglePlayback(song) }
            Button("Delete", role: .destructive) { viewModel.delete([song.id]) }
        }
    }
}

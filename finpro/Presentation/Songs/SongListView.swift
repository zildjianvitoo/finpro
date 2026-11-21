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
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                Spacer()
                Button(viewModel.selecting ? "Cancel" : "Select") { withRowAnimation(viewModel.toggleSelectionMode) }
                    .font(.appBody.weight(.medium)).foregroundStyle(Color.primaryBrand)
                    .glassPillButtonStyle(height: AppLayout.headerPillHeight, horizontalPadding: 17)
                    .disabled(viewModel.library.songs.isEmpty)
                if viewModel.selecting {
                    Button(role: .destructive) { viewModel.delete(viewModel.selectedIDs) } label: {
                        Image(systemName: "trash.fill").foregroundStyle(Color.primaryBrand)
                    }
                    .buttonStyle(.appIcon(.glass)).disabled(viewModel.selectedIDs.isEmpty)
                    .accessibilityLabel("Delete selected songs")
                } else {
                    Button(action: onAdd) { Image(systemName: "plus") }
                        .buttonStyle(.appIcon(.primary)).accessibilityLabel("Add a song")
                }
            }
            .padding(.horizontal, 16)
            // Header buttons at y 70 like the other screens (design 3.2a).
            .padding(.top, AppSpacing.small)
            Text("Song List").font(.appLargeTitle).foregroundStyle(Color.plumNight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            if viewModel.songs.isEmpty {
                ContentUnavailableView(viewModel.query.isEmpty ? "No songs yet" : "No matching songs",
                                       systemImage: "music.note.list",
                                       description: Text(viewModel.query.isEmpty ? "Tap + to add your first song." : "Try a different song name."))
            } else {
                // A scroll view, not a List: a List cross-fades a row while it grows, so opening a
                // row could not animate smoothly. Delete stays in Select mode and the context menu.
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.songs) { song in
                            row(song)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
            }
            if let error = viewModel.library.error ?? viewModel.error {
                Text(error.title).font(.appCaption).foregroundStyle(Color.primaryBrand).padding(12)
            }
            if !viewModel.selecting {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.appTitle3)
                    TextField("Search", text: $viewModel.query,
                              prompt: Text("Search").foregroundStyle(Color.secondary))
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                    if !viewModel.query.isEmpty {
                        Button { viewModel.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search")
                    } else {
                        // Design 3.2a: a mic like the system search bar. It opens the keyboard,
                        // whose dictation key speaks the song name (SwiftUI cannot start dictation).
                        Button { searchFocused = true } label: { Image(systemName: "mic").font(.appTitle3) }
                            .accessibilityLabel("Search by voice")
                            .accessibilityHint("Opens the keyboard; use its dictation key")
                    }
                }
                .font(.appBody).foregroundStyle(Color.secondary)
                .padding(.horizontal, 16).frame(height: 52)
                // A glass search bar like the system one (design 3.2a).
                .glassCardBackground(cornerRadius: 26)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewModel.stop() } }
        .onChange(of: nameFocused) { _, focused in
            if !focused { finishRename() }
        }
    }

    /// Opening or closing a row grows it and fades its player in, instead of jumping.
    private func withRowAnimation(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), change)
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
                    Image(systemName: viewModel.selectedIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                        .font(.appTitle2.weight(.regular))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: AppSpacing.tiny) {
                        if renaming?.id == song.id {
                            TextField("Song name", text: $name).font(.appSubheadline)
                                .focused($nameFocused).submitLabel(.done)
                                .onSubmit { finishRename(); nameFocused = false }
                        } else { Text(song.title).font(.appBody.weight(.semibold)).lineLimit(1)
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
                    .font(.appSubheadline).foregroundStyle(expanded ? Color.primary400.lightResolved : Color.primary400)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.selecting { viewModel.select(song.id) }
                else { withRowAnimation { viewModel.play(song) } }
            }
            if expanded {
                let progress = viewModel.playingID == song.id ? viewModel.playbackTime / max(1, song.duration) : 0
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary800.opacity(0.55))
                        Capsule().fill(Color.primary500)
                            .frame(width: max(8, proxy.size.width * min(1, max(0, progress))))
                    }
                }
                .frame(height: 8)
                .padding(.vertical, AppSpacing.tiny)
                .transition(.opacity)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue(Text(min(1, max(0, progress)), format: .percent.precision(.fractionLength(0))))
                HStack {
                    Spacer()
                    Button { viewModel.togglePlayback(song) } label: {
                        Image(systemName: viewModel.playingID == song.id ? "pause.fill" : "play.fill")
                            .font(.appTitle2)
                    }
                    .accessibilityLabel(viewModel.playingID == song.id ? "Pause song" : "Play song")
                    Spacer()
                    Button { viewModel.stop(); onOpen(song) } label: { Image(systemName: "waveform").font(.appTitle2) }
                        .accessibilityLabel("Choose song section")
                }
                .transition(.opacity)
            }
        }
        .buttonStyle(.plain)
        // Text on the lime row stays deep plum in dark mode too.
        .foregroundStyle(expanded ? Color.primary500 : Color.primaryBrand)
        .padding(12)
        .background(expanded ? Color.secondary200 : Color.secondaryButton, in: RoundedRectangle(cornerRadius: 12))
        // Keeps the player inside the row while it grows or shrinks.
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityAddTraits(viewModel.selecting && viewModel.selectedIDs.contains(song.id) ? .isSelected : [])
        .contextMenu {
            Button("Select") { viewModel.beginSelecting(song.id) }
            Button("Rename") { beginRename(song) }
            Button("Choose song section") { viewModel.stop(); onOpen(song) }
            Button("Play") { viewModel.togglePlayback(song) }
            Button("Delete", role: .destructive) { viewModel.delete([song.id]) }
        }
    }
}

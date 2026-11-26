//
//  HomeView.swift
//  finpro
//

import SwiftUI
import TipKit
import QuickLook

struct HomeView: View {
    @State var viewModel: HomeViewModel
    var isActive: Bool = true
    var vocalRangeCompletionCount: Int = 0
    @State private var showsCovers = false
    /// The saved vocal range's result screen, pushed from the vocal range pill.
    @State private var showsVocalRange = false
    @State private var coversRevealProgress: CGFloat = 0
    @State private var vocalRangeRevealProgress: CGFloat = 0
    @State private var previewURL: URL?
    private let createTip = CreateCoverTip()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Covers").font(.appLargeTitle).foregroundStyle(Color.plumNight)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button {
                        // Show the saved result; before any test, start the test.
                        if viewModel.vocalRange != nil { showsVocalRange = true } else { viewModel.vocalRangeTapped() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text(viewModel.vocalRangeText).lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "chevron.right")
                        }
                        .font(.appTitle3.weight(.semibold))
                        .foregroundStyle(Color.primaryBrand)
                        .padding(.horizontal, 10).frame(height: 44)
                        .background(Color.primary100, in: Capsule())
                    }
                    .accessibilityLabel("Your vocal range, \(viewModel.vocalRangeText)")
                    Button {
                        createTip.invalidate(reason: .actionPerformed)
                        viewModel.createCoverTapped()
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.appIcon(.primary)).accessibilityLabel("Add a song")
                        .modifier(AddSongPopoverTip(tip: viewModel.songLibrary.songs.isEmpty ? createTip : nil))
                        .tipViewStyle(CreateCoverTipStyle())
                }
                .padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 6) {
                    sectionButton("Songs", action: viewModel.songsTapped)
                    if viewModel.songLibrary.songs.isEmpty {
                        Text("Tap + to add a song and\nstart creating your cover.")
                            .font(.appBody).foregroundStyle(Color.primary300)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 116)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(viewModel.songLibrary.songs.prefix(8)) { song in
                                    Button { viewModel.openSong(song) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Image(systemName: "play.fill").font(.appTitle1)
                                                .foregroundStyle(Color.tertiaryText)
                                                .frame(width: 87, height: 87)
                                                .background(Color.primary100, in: RoundedRectangle(cornerRadius: 8))
                                                .padding(.bottom, 4)
                                            Text(song.title).font(.appSubheadline.weight(.semibold)).lineLimit(1)
                                                .foregroundStyle(Color.primary)
                                            Text(Duration.seconds(song.duration), format: .time(pattern: .minuteSecond))
                                                .font(.appCaption2).foregroundStyle(Color.primary300)
                                        }
                                        .frame(width: 87, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, -16)
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, 16)
                // Empty Home (design 3.1a) sits Songs closer to the header than 3.1b.
                .padding(.top, viewModel.songLibrary.songs.isEmpty ? 1 : 22)
                VStack(alignment: .leading, spacing: 6) {
                    sectionButton("Your covers") { showsCovers = true }
                    if viewModel.recentCovers.isEmpty {
                        Text("Your cover projects will appear here.")
                            .font(.appBody).foregroundStyle(Color.primary300)
                            .frame(maxWidth: .infinity).padding(.top, 42)
                    } else { CoverGridView(covers: viewModel.recentCovers, onTap: open) }
                }
                .padding(.horizontal, 16)
                // Empty Home (design 3.1a): more room under the songs hint.
                .padding(.top, viewModel.songLibrary.songs.isEmpty ? 56 : 24)
                .frame(maxWidth: .infinity, alignment: .top)
                if let error = viewModel.songLibrary.error ?? viewModel.coverLibrary?.error {
                    Text(error.title).font(.appCaption).foregroundStyle(Color.primaryBrand)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 10)
            .accessibilityHidden(showsCovers || showsVocalRange)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .hierarchicalUnderlay(
            isCovered: showsCovers || showsVocalRange,
            revealProgress: showsVocalRange ? vocalRangeRevealProgress : (showsCovers ? coversRevealProgress : 0)
        )
        .quickLookPreview($previewURL)
        .overlay {
            if showsCovers {
                CoverListView(viewModel: viewModel, onBack: {
                    coversRevealProgress = 0
                    showsCovers = false
                }, onOpen: open, isSwipeBackEnabled: isActive && !showsVocalRange, onSwipeProgress: { coversRevealProgress = $0 })
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay {
            if showsVocalRange, let range = viewModel.vocalRange {
                VocalRangeResultView(range: range, isFemale: false, onDone: {
                    vocalRangeRevealProgress = 0
                    showsVocalRange = false
                    viewModel.createCoverTapped()
                }, onRetake: viewModel.vocalRangeTapped, onBack: {
                    vocalRangeRevealProgress = 0
                    showsVocalRange = false
                }, backAccessibilityLabel: "Back to Covers", isSwipeBackEnabled: isActive, onSwipeProgress: { vocalRangeRevealProgress = $0 })
                .transition(.move(edge: .trailing))
            }
        }
        .onChange(of: vocalRangeCompletionCount) { _, _ in
            vocalRangeRevealProgress = 0
            showsVocalRange = false
        }
        .animation(.easeInOut(duration: 0.3), value: showsCovers)
        .animation(.easeInOut(duration: 0.3), value: showsVocalRange)
    }

    private func open(_ cover: HomeViewModel.RecentCoverItem) {
        if viewModel.openCover(cover) {
            showsCovers = false
        } else {
            previewURL = cover.videoURL
        }
    }

    private func sectionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.appTitle3.weight(.bold))
                Image(systemName: "chevron.right").font(.appSubheadline.weight(.semibold))
            }
            .foregroundStyle(Color.plumNight)
        }
        .buttonStyle(.plain)
    }
}

private struct AddSongPopoverTip: ViewModifier {
    let tip: CreateCoverTip?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Below the button, the arrow pointing up at it (design 3.1a).
            content.popoverTip(tip, attachmentAnchor: .rect(.bounds), arrowEdges: .top)
        } else {
            content.popoverTip(tip, arrowEdge: .top)
        }
    }
}

//
//  HomeView.swift
//  finpro
//

import SwiftUI
import TipKit
import QuickLook

struct HomeView: View {
    @State var viewModel: HomeViewModel
    @State private var showsCovers = false
    @State private var previewURL: URL?
    private let createTip = CreateCoverTip()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Covers").font(.appLargeTitle).foregroundStyle(Color.primaryBrand)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button(action: viewModel.vocalRangeTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text(viewModel.vocalRangeText).lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "chevron.right")
                        }
                        .font(.appSubheadline.weight(.semibold))
                        .foregroundStyle(Color.primaryDark)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.secBrand, in: Capsule())
                    }
                    .accessibilityLabel("Your vocal range, \(viewModel.vocalRangeText). Retake test")
                    Button {
                        createTip.invalidate(reason: .actionPerformed)
                        viewModel.createCoverTapped()
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.appIcon(.primary)).accessibilityLabel("Add a song")
                        .popoverTip(viewModel.songLibrary.songs.isEmpty ? createTip : nil, arrowEdge: .top)
                        .tipViewStyle(CreateCoverTipStyle())
                }
                .padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 12) {
                    sectionButton("Songs", action: viewModel.songsTapped)
                    if viewModel.songLibrary.songs.isEmpty {
                        Text("Tap + to add a song and\nstart creating your cover.")
                            .font(.appSubheadline).foregroundStyle(Color.secondaryText)
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
                                                .frame(width: 86, height: 86)
                                                .background(Color.secondaryButton, in: RoundedRectangle(cornerRadius: 8))
                                                .padding(.bottom, 4)
                                            Text(song.title).font(.appSubheadline.weight(.semibold)).lineLimit(1)
                                            Text(Duration.seconds(song.duration), format: .time(pattern: .minuteSecond))
                                                .font(.appCaption2).foregroundStyle(Color.secondaryText)
                                        }
                                        .foregroundStyle(Color.primaryBrand).frame(width: 86, alignment: .leading)
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
                .padding(16)
                .background(sectionPanel)
                VStack(alignment: .leading, spacing: 12) {
                    sectionButton("Your covers") { showsCovers = true }
                    if viewModel.recentCovers.isEmpty {
                        Text("Your cover projects will appear here.")
                            .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                            .frame(maxWidth: .infinity).padding(.top, 24)
                    } else { CoverGridView(covers: viewModel.recentCovers, onTap: open) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 600, alignment: .top)
                .background(sectionPanel)
                .padding(.top, -12)
                if let error = viewModel.songLibrary.error ?? viewModel.coverLibrary?.error {
                    Text(error.title).font(.appCaption).foregroundStyle(Color.primaryBrand)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 16)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .quickLookPreview($previewURL)
        .overlay {
            if showsCovers {
                CoverListView(viewModel: viewModel, onBack: { showsCovers = false }, onOpen: open)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showsCovers)
    }

    private func open(_ cover: HomeViewModel.RecentCoverItem) {
        if viewModel.openCover(cover) {
            showsCovers = false
        } else {
            previewURL = cover.videoURL
        }
    }

    /// Lime panel behind a home section, fading into the screen background (design "Rectangle 3").
    private var sectionPanel: some View {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
            .fill(LinearGradient(stops: [.init(color: .secBrand, location: 0),
                                         .init(color: .screenBackground, location: 0.62)],
                                 startPoint: .top, endPoint: .bottom))
    }

    private func sectionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.appTitle3.weight(.bold))
                Image(systemName: "chevron.right").font(.appSubheadline.weight(.semibold))
            }
            .foregroundStyle(Color.primaryBrand)
        }
        .buttonStyle(.plain)
    }
}

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
    @State private var filter = "All"
    @State private var previewURL: URL?
    @State private var galleryPreviewURL: URL?
    private let createTip = CreateCoverTip()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
                VStack(alignment: .leading, spacing: 16) {
                    sectionButton("Songs", action: viewModel.songsTapped)
                    if viewModel.songLibrary.songs.isEmpty {
                        Text("Tap + to add a song and\nstart creating your cover.")
                            .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 116)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(viewModel.songLibrary.songs.prefix(8)) { song in
                                    Button { viewModel.openSong(song) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Image(systemName: "play.fill").font(.appTitle2)
                                                .foregroundStyle(Color.tertiaryText)
                                                .frame(width: 82, height: 82)
                                                .background(Color.secondaryButton, in: RoundedRectangle(cornerRadius: 10))
                                            Text(song.title).font(.appCaption).lineLimit(1)
                                            Text(Duration.seconds(song.duration), format: .time(pattern: .minuteSecond))
                                                .font(.appCaption2).foregroundStyle(Color.secondaryText)
                                        }
                                        .foregroundStyle(Color.primaryBrand).frame(width: 82, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    sectionButton("Your covers") { showsCovers = true }
                    if viewModel.recentCovers.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "mic.fill").font(.system(size: 40))
                                .foregroundStyle(.white).frame(width: 88, height: 88)
                                .background(Color.primary200.opacity(0.7), in: Circle())
                            Text("Your cover projects will appear here.")
                                .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 4)
                    } else { coverGrid(columns: 3, covers: viewModel.recentCovers) }
                }
                if let error = viewModel.songLibrary.error ?? viewModel.coverLibrary?.error {
                    Text(error.title).font(.appCaption).foregroundStyle(Color.primaryBrand)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showsCovers) {
            NavigationStack {
                ScrollView {
                    Picker("Filter", selection: $filter) {
                        ForEach(["All", "Finished", "Draft"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented).padding(.bottom, 16)
                    coverGrid(columns: 2, covers: viewModel.recentCovers.filter {
                        filter == "All" || ($0.status == .finished ? filter == "Finished" : filter == "Draft")
                    }, onOpen: { galleryPreviewURL = $0 })
                }
                .padding(16).background(Color.screenBackground)
                .navigationTitle("Your covers").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsCovers = false } } }
            }
            .quickLookPreview($galleryPreviewURL)
        }
    }
    private func sectionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.appHeadline)
                Image(systemName: "chevron.right").font(.appCaption)
            }
            .foregroundStyle(Color.primaryBrand)
        }
        .buttonStyle(.plain)
    }
    private func coverGrid(columns: Int, covers: [HomeViewModel.RecentCoverItem], onOpen: ((URL?) -> Void)? = nil) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 20) {
            ForEach(covers) { cover in
                Button {
                    if let onOpen { onOpen(cover.videoURL) } else { previewURL = cover.videoURL }
                } label: {
                VStack(alignment: .leading, spacing: 6) {
                    CoverThumbnailView(viewModel: CoverThumbnailViewModel(url: cover.videoURL, duration: cover.duration))
                        .aspectRatio(0.56, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                        .overlay(alignment: .bottomLeading) {
                            if cover.status == .draft {
                                Text("Draft").font(.appCaption2).foregroundStyle(.white)
                                    .padding(4).background(Color.primaryBrand, in: Capsule()).padding(6)
                            }
                        }
                    Text(cover.title).font(.appCaption).lineLimit(1)
                    Text(Duration.seconds(cover.duration), format: .time(pattern: .minuteSecond))
                        .font(.appCaption2).foregroundStyle(Color.secondaryText)
                }
                .foregroundStyle(Color.primaryBrand)
                }
                .buttonStyle(.plain).disabled(cover.videoURL == nil)
            }
        }
    }
}

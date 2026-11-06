//
//  HomeView.swift
//  finpro
//
//  Home / dashboard screen ("Ready to make your next cover?").
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                createCoverButton
                    .padding(.bottom, 32)

                recentCoversSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
    }

    // MARK: - Header & Vocal Range Pill

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to make\nyour next cover?")
                .font(.system(size: 32, weight: .bold))
                .lineSpacing(2)
                .foregroundStyle(.primary)

            vocalRangePill
        }
    }

    private var vocalRangePill: some View {
        Button(action: viewModel.vocalRangeTapped) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your vocal range")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(viewModel.vocalRangeText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.vocalRangePill)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary Action Button

    private var createCoverButton: some View {
        Button(action: viewModel.createCoverTapped) {
            HStack(spacing: 8) {
                Text("Create New Cover")
                    .font(.system(size: 17, weight: .bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.09))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule()
                    .fill(Color.surfaceButton)
            )
        }
    }

    // MARK: - Recent Covers Section

    private var recentCoversSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent covers")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: viewModel.seeAllTapped) {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                // TODO(logic): connect to saved recent covers library / photo album
                ForEach(viewModel.recentCovers) { _ in
                    coverCard
                }
            }
        }
    }

    private var coverCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.surfaceCard)
            .aspectRatio(0.72, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.36, blue: 0.42))
                    .padding(10)
            }
    }
}

#if DEBUG
#Preview {
    HomeView(viewModel: HomeViewModel(
        vocalRangeRepository: FakeVocalRangeRepository(initial: VocalRange(lowestMIDI: 48, highestMIDI: 81)),
        onCreateCover: {},
        onRetestVocalRange: {}
    ))
}
#endif

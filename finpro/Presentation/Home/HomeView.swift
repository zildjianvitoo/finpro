//
//  HomeView.swift
//  finpro
//
//  Home / dashboard screen ("Ready to make your next cover?").
//

import SwiftUI
import TipKit

struct HomeView: View {
    @State private var viewModel: HomeViewModel

    private let createCoverTip = CreateCoverTip()

    /// Inset of the content from the screen edge per the design.
    private let contentInset: CGFloat = 44
    private let coverSpacing: CGFloat = 11
    private let coverRowSpacing: CGFloat = 20
    /// Cover thumbnail width / height per the design.
    private let coverAspectRatio: CGFloat = 100.0 / 148.0
    private let cornerRadius: CGFloat = 18
    private let fabDiameter: CGFloat = 80
    /// Keeps the vocal range pill as wide as drawn, so short ranges do not shrink it.
    private let pillMinWidth: CGFloat = 190

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ready to make\nyour next cover?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.plumInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 42)

                vocalRangePill
                    .padding(.top, 18)

                recentCoversHeader
                    .padding(.top, 20)

                Group {
                    if viewModel.recentCovers.isEmpty {
                        emptyState
                    } else {
                        coverGrid
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, contentInset)
            // Room for the floating create button.
            .padding(.bottom, fabDiameter + 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.onboardingBackground.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) { createCoverButton }
    }

    // MARK: - Vocal Range Pill

    private var vocalRangePill: some View {
        Button(action: viewModel.vocalRangeTapped) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(Color.plumInk)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Your vocal range")
                        .font(.caption2)
                        .foregroundStyle(Color.plumInk)
                    Text(viewModel.vocalRangeText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.plumInk)
                }

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.plumInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minWidth: pillMinWidth, minHeight: 48)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(Color.surfaceLavender))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your vocal range, \(viewModel.vocalRangeText)")
        .accessibilityHint("Retakes the vocal range test")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Recent Covers

    private var recentCoversHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent covers")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.plumInk)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if !viewModel.recentCovers.isEmpty {
                Button(action: viewModel.seeAllTapped) {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.plumInkSecondary)
                    // 44pt tap target without making the header row taller than drawn.
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                    .padding(.vertical, -14)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 25)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "mic")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 80, height: 70)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.tileMauve))
                .accessibilityHidden(true)

            Text("Your first cover starts here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.plumInk)
                .padding(.top, 16)

            Text("Add a song and start creating your cover.")
                .font(.footnote)
                .foregroundStyle(Color.plumInkSecondary)
                .padding(.top, 12)

            Text("Your recorded covers will appear here.")
                .font(.caption)
                .foregroundStyle(Color.plumInkSecondary)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.surfaceLavender))
        .accessibilityElement(children: .combine)
    }

    private var coverGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: coverSpacing, alignment: .top), count: 3),
            spacing: coverRowSpacing
        ) {
            // TODO(logic): open the cover when tapped
            ForEach(viewModel.recentCovers) { cover in
                coverCard(cover)
            }
        }
    }

    private func coverCard(_ cover: HomeViewModel.RecentCoverItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.surfaceCard)
                .aspectRatio(coverAspectRatio, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Color.plumNight)
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(cover.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.plumInk)
                    .lineLimit(1)

                Text("\(Self.dayText(for: cover.date)) • \(Duration.seconds(cover.duration).formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption2)
                    .foregroundStyle(Color.plumInkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(cover.status == .finished ? "Finished" : "Draft")
                    .font(.caption2)
                    .foregroundStyle(Color.plumInk)
            }
            .padding(.top, 12)
            .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "Today", "Yesterday", or a short numeric date in the user's locale.
    private static func dayText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
    }

    // MARK: - Create Button

    private var createCoverButton: some View {
        Button {
            createCoverTip.invalidate(reason: .actionPerformed)
            viewModel.createCoverTapped()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: fabDiameter, height: fabDiameter)
                .background(Circle().fill(Color.plumNight))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create new cover")
        .popoverTip(viewModel.recentCovers.isEmpty ? createCoverTip : nil, arrowEdge: .bottom) { _ in
            createCoverTip.invalidate(reason: .tipClosed)
        }
        .tipViewStyle(CreateCoverTipStyle())
        .padding(.trailing, 32)
        .padding(.bottom, 4)
    }
}

#if DEBUG
#Preview("Covers") {
    HomeView(viewModel: HomeViewModel(
        vocalRangeRepository: FakeVocalRangeRepository(initial: VocalRange(lowestMIDI: 48, highestMIDI: 81)),
        recentCovers: HomeViewModel.RecentCoverItem.samples,
        onCreateCover: {},
        onRetestVocalRange: {}
    ))
}

#Preview("Empty") {
    HomeView(viewModel: HomeViewModel(
        vocalRangeRepository: FakeVocalRangeRepository(initial: VocalRange(lowestMIDI: 48, highestMIDI: 81)),
        onCreateCover: {},
        onRetestVocalRange: {}
    ))
}
#endif

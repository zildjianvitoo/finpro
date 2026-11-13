//
//  CoverGridView.swift
//  finpro
//
//  Two-column grid of saved covers (Home "Your covers" and the All Covers screen, Sketch
//  "TestFlight UT" 3.1b / 3.3a-c). While selecting, each cover shows a check circle.
//

import SwiftUI

struct CoverGridView: View {
    let covers: [HomeViewModel.RecentCoverItem]
    var selecting = false
    var selectedIDs: Set<UUID> = []
    let onTap: (HomeViewModel.RecentCoverItem) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 2), spacing: 16) {
            ForEach(covers) { cover in
                Button { onTap(cover) } label: { cell(cover) }
                    .buttonStyle(.plain)
                    .disabled(!selecting && cover.videoURL == nil)
                    .accessibilityAddTraits(selectedIDs.contains(cover.id) ? .isSelected : [])
            }
        }
    }

    private func cell(_ cover: HomeViewModel.RecentCoverItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverThumbnailView(viewModel: CoverThumbnailViewModel(url: cover.videoURL, duration: cover.duration))
                .aspectRatio(0.56, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
                .overlay(alignment: .bottomLeading) {
                    if cover.status == .draft && !selecting {
                        Text("Draft").font(.appCaption).foregroundStyle(.white)
                            .padding(.vertical, 2).padding(.horizontal, 6)
                            .background(Color.primary400, in: Capsule()).padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if selecting {
                        Image(systemName: selectedIDs.contains(cover.id) ? "checkmark.circle.fill" : "circle")
                            .font(.appTitle2.weight(.regular))
                            .foregroundStyle(Color.primaryBrand)
                            .background(Circle().fill(.white.opacity(selectedIDs.contains(cover.id) ? 1 : 0)).padding(3))
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.bottom, 2)
            Text(cover.title).font(.appSubheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 8) {
                Text(Self.age(of: cover.date))
                Text("●").font(.system(size: 5)).accessibilityHidden(true)
                Text(Duration.seconds(cover.duration), format: .time(pattern: .minuteSecond))
            }
            .font(.appCaption2).foregroundStyle(Color.tertiaryText)
        }
        .foregroundStyle(Color.primaryBrand)
        .contentShape(Rectangle())
    }

    /// "Today", "Yesterday", "5d", "2w", then the date.
    static func age(of date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days)d"
        case 7..<35: return "\(days / 7)w"
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}

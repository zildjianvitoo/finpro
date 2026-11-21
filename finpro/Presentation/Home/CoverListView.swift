//
//  CoverListView.swift
//  finpro
//
//  All covers (Sketch "TestFlight UT" 3.3a-c): All / Finished / Draft filter chips, a two-column
//  grid, and Select to delete several covers at once.
//

import SwiftUI

struct CoverListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", finished = "Finished", draft = "Draft"
        var id: Self { self }
    }

    let viewModel: HomeViewModel
    let onBack: () -> Void
    let onOpen: (HomeViewModel.RecentCoverItem) -> Void
    @State private var filter = Filter.all
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmsDelete = false
    @Namespace private var filterThumb

    private var covers: [HomeViewModel.RecentCoverItem] {
        viewModel.recentCovers.filter {
            switch filter {
            case .all: true
            case .finished: $0.status == .finished
            case .draft: $0.status == .draft
            }
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                Spacer()
                Button(selecting ? "Cancel" : "Select") {
                    selecting.toggle()
                    selectedIDs = []
                }
                .font(.appBody.weight(.medium)).foregroundStyle(Color.primaryBrand)
                .glassPillButtonStyle(height: AppLayout.headerPillHeight, horizontalPadding: 17)
                .disabled(viewModel.recentCovers.isEmpty)
                if selecting {
                    Button(role: .destructive) { confirmsDelete = true } label: {
                        Image(systemName: "trash.fill").foregroundStyle(Color.primaryBrand)
                    }
                        .buttonStyle(.appIcon(.glass))
                        .disabled(selectedIDs.isEmpty)
                        .accessibilityLabel("Delete selected covers")
                } else {
                    Button(action: viewModel.createCoverTapped) { Image(systemName: "plus") }
                        .buttonStyle(.appIcon(.primary)).accessibilityLabel("Add a song")
                }
            }
            .padding(.horizontal, AppSpacing.regular)
            // Header buttons at y 70 like the other screens (design 3.3a).
            .padding(.top, AppSpacing.small)
            // Segmented control (design "Segmented Controls/Dark/3 Segments"): plum thumb on a grey track.
            HStack(spacing: 0) {
                ForEach(Filter.allCases) { item in
                    Button { filter = item } label: {
                        Text(item.rawValue)
                            .font(.appFootnote.weight(filter == item ? .semibold : .regular))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if filter == item {
                                    Capsule().fill(Color.primaryButton).matchedGeometryEffect(id: "thumb", in: filterThumb)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            .buttonStyle(.plain)
            .padding(2)
            .frame(height: 32)
            .background(Color.segmentTrack, in: Capsule())
            .padding(.horizontal, AppSpacing.regular)
            .padding(.top, AppSpacing.tiny + 2)
            ScrollView {
                if covers.isEmpty {
                    Text(filter == .all ? "Your cover projects will appear here." : "No \(filter.rawValue.lowercased()) covers yet.")
                        .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity).padding(.top, AppSpacing.spacious)
                } else {
                    CoverGridView(covers: covers, selecting: selecting, selectedIDs: selectedIDs) { cover in
                        if selecting {
                            if selectedIDs.remove(cover.id) == nil { selectedIDs.insert(cover.id) }
                        } else {
                            onOpen(cover)
                        }
                    }
                    .padding(.horizontal, AppSpacing.regular).padding(.top, AppSpacing.medium).padding(.bottom, AppSpacing.small)
                }
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: selecting)
        .animation(.easeInOut(duration: 0.2), value: filter)
        .confirmationDialog(selectedIDs.count == 1 ? "Delete this cover?" : "Delete \(selectedIDs.count) covers?",
                            isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                viewModel.deleteCovers(selectedIDs)
                selectedIDs = []
                selecting = false
            }
        } message: {
            Text("The videos are removed from the app. Copies saved to Photos stay there.")
        }
    }
}

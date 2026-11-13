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
            HStack(spacing: AppSpacing.small) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                Spacer()
                Button(selecting ? "Cancel" : "Select") {
                    selecting.toggle()
                    selectedIDs = []
                }
                .buttonStyle(AppChipButtonStyle(selected: selecting))
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
            HStack(spacing: AppSpacing.small) {
                ForEach(Filter.allCases) { item in
                    Button(item.rawValue) { filter = item }
                        .font(.appBody)
                        .foregroundStyle(filter == item ? Color.primaryBrand : Color.secBrand)
                        .frame(width: 102, height: 42)
                        .background(filter == item ? Color.secBrand : Color.primaryBrand, in: Capsule())
                        .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            .buttonStyle(.plain)
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
                    .padding(.horizontal, AppSpacing.regular).padding(.vertical, AppSpacing.small)
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

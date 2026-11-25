//
//  KeySelectionView.swift
//  finpro
//

import SwiftUI

struct KeySelectionView: View {
    @State var viewModel: KeySelectionViewModel
    let routeMonitor: any AudioRouteMonitor
    let onChooseAnother: () -> Void
    let onRetest: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: ScrollPosition
    @State private var visibleShift: Int?
    @State private var isScrollingKeys = false
    private static let rowHeight: CGFloat = 68

    private nonisolated struct KeyScrollSnap: ScrollTargetBehavior {
        let rowHeight: CGFloat

        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            let maximumOffset = max(0, context.contentSize.height - context.containerSize.height)
            let rowOffset = (target.rect.minY / rowHeight).rounded() * rowHeight
            target.rect.origin.y = min(maximumOffset, max(0, rowOffset))
        }
    }

    init(viewModel: KeySelectionViewModel, routeMonitor: any AudioRouteMonitor,
         onChooseAnother: @escaping () -> Void, onRetest: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        _position = State(initialValue: ScrollPosition(y: Self.offset(for: viewModel.selectedShift ?? 0)))
        self.routeMonitor = routeMonitor
        self.onChooseAnother = onChooseAnother
        self.onRetest = onRetest
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { viewModel.stop(); onChooseAnother() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back to song section")
                Spacer()
            }
            .padding(.horizontal, 16)
            if viewModel.choices.options.isEmpty {
                ContentUnavailableView("No key fits this range", systemImage: "music.note.list",
                    description: Text("Try a shorter section or test your comfortable vocal range again."))
                Button("Re-test vocal range", action: onRetest).buttonStyle(.appPrimary)
            } else {
                ViewThatFits(in: .vertical) {
                    keyPicker
                    ScrollView { keyPicker }
                }
                Spacer(minLength: 0)
                if let error = viewModel.error {
                    ErrorStateView(error: error)
                        .padding(.horizontal, AppSpacing.regular).padding(.bottom, AppSpacing.small)
                }
                Button("Use Selected Key", action: viewModel.confirm).buttonStyle(.appPrimary)
                    .disabled(isScrollingKeys || viewModel.isRendering || viewModel.selectedSong == nil)
                    .padding(.horizontal, 25).padding(.bottom, 16)
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .edgeSwipeBack { viewModel.stop(); onChooseAnother() }
        .onAppear { viewModel.autoplaySelected() }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewModel.stop() } }
        .task { for await _ in routeMonitor.interruptions() { viewModel.stop() } }
        .task {
            var previous: AudioOutputRoute?
            for await route in routeMonitor.routeChanges() {
                if let previous, route != previous { viewModel.stop() }
                previous = route
            }
        }
    }

    private var keyPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Find Your Key").font(.appLargeTitle).foregroundStyle(Color.primaryBrand)
                .accessibilityAddTraits(.isHeader)
            Text("Listen to each version and choose what feels comfortable to sing.")
                .font(.appSubheadline)
                .padding(.top, AppSpacing.small)
            dial
                .padding(.top, 56)
                .padding(.horizontal, 17)
            if viewModel.isRendering {
                HStack(spacing: AppSpacing.small) {
                    LoadingMascotView(size: AppLayout.loadingMascotInline)
                    LoadingTextView(title: "Preparing key…", font: .appSubheadline, shadowed: false)
                }
                .foregroundStyle(Color.primaryBrand)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 15)
        .padding(.horizontal, AppSpacing.regular)
    }

    private var dial: some View {
        let centered = visibleShift ?? viewModel.selectedShift ?? 0
        return ZStack {
            Capsule()
                .fill(Color.primary100)
                .frame(height: 34)
                .shadow(color: .black.opacity(0.24), radius: 4, y: 4)
                .overlay {
                    HStack(spacing: 0) {
                        Text("recommended")
                            .font(.appCaption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Color.primaryBrand, in: RoundedRectangle(cornerRadius: 4))
                            .opacity(centered == viewModel.recommendedShift ? 1 : 0)
                            .frame(maxWidth: .infinity)
                        Color.clear.frame(width: 32)
                        Text("semitones").font(.appSubheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)
                }
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(TranspositionPlan.semitoneRange.reversed()), id: \.self) { shift in
                        Button {
                            if shift == viewModel.selectedShift { viewModel.previewSelected() }
                            else { select(shift) }
                        } label: {
                            Text(label(shift))
                                .font(.appBody.weight(shift == centered ? .bold : .regular))
                                .foregroundStyle(shift == centered ? Color.primaryBrand : Color.primary300)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Give the first and last key room to align with the fixed middle row.
                .padding(.vertical, Self.rowHeight * 2)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(KeyScrollSnap(rowHeight: Self.rowHeight))
            .scrollPosition($position)
            .onScrollGeometryChange(for: Int.self) { middleShift(in: $0) } action: { _, shift in
                visibleShift = shift
            }
            .onScrollPhaseChange { old, new, context in
                isScrollingKeys = new != .idle
                guard new == .idle, old == .interacting || old == .decelerating else { return }
                let shift = middleShift(in: context.geometry)
                if shift != viewModel.selectedShift { viewModel.chooseShift(shift) }
            }
        }
        .frame(height: Self.rowHeight * 5)
        .sensoryFeedback(.selection, trigger: centered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Selected key")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Adjust to change key, or tap to preview")
        .accessibilityAction { viewModel.previewSelected() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select((viewModel.selectedShift ?? 0) + 1)
            case .decrement: select((viewModel.selectedShift ?? 0) - 1)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        let shift = viewModel.selectedShift ?? 0
        return "\(label(shift)) semitones" + (shift == viewModel.recommendedShift ? ", recommended" : "")
    }

    private func middleShift(in geometry: ScrollGeometry) -> Int {
        let range = TranspositionPlan.semitoneRange
        let row = Int((geometry.contentOffset.y / Self.rowHeight).rounded())
        return max(range.lowerBound, min(range.upperBound, range.upperBound - row))
    }

    private func select(_ shift: Int) {
        guard TranspositionPlan.semitoneRange.contains(shift), shift != viewModel.selectedShift else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.27)) {
            position.scrollTo(y: Self.offset(for: shift))
        }
        viewModel.chooseShift(shift)
    }

    private static func offset(for shift: Int) -> CGFloat {
        CGFloat(TranspositionPlan.semitoneRange.upperBound - shift) * rowHeight
    }

    private func label(_ shift: Int) -> String { "\(shift > 0 ? "+" : "")\(shift)" }
}

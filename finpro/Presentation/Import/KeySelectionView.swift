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
    @GestureState private var dragTranslation: CGFloat = 0
    private let rowHeight: CGFloat = 68

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
                    .disabled(viewModel.isRendering || viewModel.selectedSong == nil)
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
        let centered = Int(dialValue.rounded())
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

            ForEach(TranspositionPlan.semitoneRange, id: \.self) { shift in
                let offset = (dialValue - Double(shift)) * rowHeight
                Button {
                    if shift == viewModel.selectedShift { viewModel.previewSelected() }
                    else { select(shift) }
                } label: {
                    Text(label(shift))
                        .font(.appBody.weight(shift == centered ? .bold : .regular))
                        .foregroundStyle(shift == centered ? Color.primaryBrand : Color.primary300)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: offset)
            }
        }
        .frame(height: rowHeight * 5)
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 6)
            .updating($dragTranslation) { value, translation, _ in translation = value.translation.height }
            .onEnded { value in
                let target = Int(clamped(Double(viewModel.selectedShift ?? 0) + value.translation.height / rowHeight).rounded())
                select(target)
            })
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

    private var dialValue: Double { clamped(Double(viewModel.selectedShift ?? 0) + dragTranslation / rowHeight) }

    private func select(_ shift: Int) {
        guard TranspositionPlan.semitoneRange.contains(shift), shift != viewModel.selectedShift else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { viewModel.chooseShift(shift) }
    }

    private func clamped(_ shift: Double) -> Double {
        min(Double(TranspositionPlan.semitoneRange.upperBound), max(Double(TranspositionPlan.semitoneRange.lowerBound), shift))
    }

    private func label(_ shift: Int) -> String { "\(shift > 0 ? "+" : "")\(shift)" }
}

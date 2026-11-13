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
    @State private var dragOrigin: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { viewModel.stop(); onChooseAnother() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back to song section")
                Spacer()
            }
            .padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Find Your Key").font(.appLargeTitle).foregroundStyle(Color.primaryBrand)
                    Text("Listen to each version and choose what feels comfortable to sing.")
                        .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                    if viewModel.choices.options.isEmpty {
                        ContentUnavailableView("No key fits this range", systemImage: "music.note.list",
                            description: Text("Try a shorter section or test your comfortable vocal range again."))
                        Button("Re-test vocal range", action: onRetest).buttonStyle(.appPrimary)
                    } else {
                        dial.padding(.top, 68)
                        if viewModel.isRendering { ProgressView("Preparing key…").frame(maxWidth: .infinity) }
                        if let notes = viewModel.selectedNotes {
                            Button(action: viewModel.previewSelected) {
                                Text("Vocal notes: \(PitchMath.noteName(midi: notes.low)) – \(PitchMath.noteName(midi: notes.high))")
                                    .font(.appSubheadline).foregroundStyle(Color.secondaryText)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain).padding(.top, AppSpacing.section)
                            .accessibilityLabel("Preview this key with vocals, \(PitchMath.noteName(midi: notes.low)) to \(PitchMath.noteName(midi: notes.high))")
                            .accessibilityHint("Tap to play or pause the selected key")
                            if !viewModel.fitsRange {
                                Text("This key reaches beyond your tested range.")
                                    .font(.appCaption).foregroundStyle(Color.primaryBrand)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    if let error = viewModel.error { ErrorStateView(error: error) }
                }
                .padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 24)
            }
            if !viewModel.choices.options.isEmpty {
                Button("Use selected key", action: viewModel.confirm).buttonStyle(.appPrimary)
                    .disabled(viewModel.isRendering || viewModel.selectedSong == nil)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .onAppear { viewModel.autoplaySelected() }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewModel.stop() } }
        .task { for await _ in routeMonitor.interruptions() { viewModel.stop() } }
        .task {
            var previous = routeMonitor.currentRoute
            for await route in routeMonitor.routeChanges() {
                if route != previous { viewModel.stop() }
                previous = route
            }
        }
    }
    private var dial: some View {
        VStack(spacing: AppSpacing.large) {
            if let recommendation = viewModel.recommendedShift {
                Button { viewModel.chooseShift(recommendation) } label: {
                    Text("Recommended").font(.appCaption2).foregroundStyle(Color.primary800)
                        .padding(.horizontal, AppSpacing.small).padding(.vertical, AppSpacing.tiny)
                        .background(Color.secBrand, in: Capsule())
                }
                .accessibilityLabel("Use recommended key \(recommendation)")
            }
            GeometryReader { proxy in
                CurvedPitchDial(value: Double(viewModel.selectedShift ?? 0), center: Double(viewModel.selectedShift ?? 0),
                                label: { label(Int($0.rounded())) })
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: viewModel.selectedShift)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            let initial = dragOrigin ?? viewModel.selectedShift ?? 0
                            dragOrigin = initial
                            let delta = Int((-Double(value.translation.width / max(1, proxy.size.width)) * 4).rounded())
                            let shift = min(TranspositionPlan.semitoneRange.upperBound,
                                            max(TranspositionPlan.semitoneRange.lowerBound, initial + delta))
                            if shift != viewModel.selectedShift { viewModel.chooseShift(shift) }
                        }
                        .onEnded { _ in dragOrigin = nil })
                    .onTapGesture { viewModel.previewSelected() }
            }
            .frame(height: AppLayout.dialHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Selected key")
            .accessibilityValue(label(viewModel.selectedShift ?? 0))
            .accessibilityHint("Adjust to change key, or tap to preview with vocals")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : -1
                viewModel.chooseShift(min(6, max(-6, (viewModel.selectedShift ?? 0) + step)))
            }
        }
    }
    private func label(_ shift: Int) -> String { "[\(shift > 0 ? "+" : "")\(shift)]" }
}

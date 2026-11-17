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
    /// The dial position while a finger is on it, in semitones (fractional, follows the finger).
    /// The key is only chosen (and the preview restarted) when the finger lifts.
    @State private var dragValue: Double?

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
                        .font(.appSubheadline).foregroundStyle(Color.primary300)
                        .padding(.top, -AppSpacing.medium)
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
                                    .font(.appSubheadline).foregroundStyle(Color.primary300)
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
                }
                .padding(.horizontal, AppSpacing.regular).padding(.top, 32).padding(.bottom, 24)
            }
            // Outside the scroll view: an error appearing must not push the title out of view.
            if let error = viewModel.error {
                ErrorStateView(error: error)
                    .padding(.horizontal, AppSpacing.regular).padding(.bottom, AppSpacing.small)
                    .transition(.opacity)
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
            // The badge sits above the recommended key and moves with the dial, so it marks one key
            // instead of whichever key is in the middle.
            GeometryReader { proxy in
                if let recommendation = viewModel.recommendedShift {
                    let spacing = proxy.size.width * CurvedPitchDial.noteSpacingRatio
                    let x = proxy.size.width / 2 + CGFloat(Double(recommendation) - dialValue) * spacing
                    let fraction = abs(x - proxy.size.width / 2) / max(1, proxy.size.width / 2)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { viewModel.chooseShift(recommendation) }
                    } label: {
                        Text("Recommended").font(.appCaption2.weight(.bold)).foregroundStyle(Color.primaryBrand)
                            .padding(.horizontal, AppSpacing.small).padding(.vertical, AppSpacing.tiny)
                            .background(Color.secBrand, in: Capsule())
                            .fixedSize()
                    }
                    // Follows the curve of the key labels below and fades out near the edges.
                    .position(x: x, y: proxy.size.height / 2 + fraction * 16)
                    .opacity(max(0, 1 - Double(max(0, fraction - 0.6)) / 0.3))
                    .allowsHitTesting(fraction < 0.9)
                    .accessibilityLabel("Use recommended key \(recommendation)")
                }
            }
            .frame(height: 24)
            GeometryReader { proxy in
                CurvedPitchDial(value: dialValue, center: dialValue, label: { label(Int($0.rounded())) })
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            let initial = dragOrigin ?? viewModel.selectedShift ?? 0
                            dragOrigin = initial
                            // Same spacing as the dial's notes, so the ticks stay under the finger.
                            let spacing = max(1, proxy.size.width * CurvedPitchDial.noteSpacingRatio)
                            dragValue = clamped(Double(initial) - Double(value.translation.width / spacing))
                        }
                        .onEnded { value in
                            let initial = dragOrigin ?? viewModel.selectedShift ?? 0
                            let spacing = max(1, proxy.size.width * CurvedPitchDial.noteSpacingRatio)
                            // A flick carries on a little, like a picker wheel.
                            let target = Int(clamped(Double(initial) - Double(value.predictedEndTranslation.width / spacing)).rounded())
                            dragOrigin = nil
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
                                dragValue = nil
                                if target != viewModel.selectedShift { viewModel.chooseShift(target) }
                            }
                        })
                    .onTapGesture { viewModel.previewSelected() }
            }
            .sensoryFeedback(.selection, trigger: Int(dialValue.rounded()))
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
    private var dialValue: Double { dragValue ?? Double(viewModel.selectedShift ?? 0) }
    private func clamped(_ shift: Double) -> Double {
        min(Double(TranspositionPlan.semitoneRange.upperBound), max(Double(TranspositionPlan.semitoneRange.lowerBound), shift))
    }
    private func label(_ shift: Int) -> String { "[\(shift > 0 ? "+" : "")\(shift)]" }
}

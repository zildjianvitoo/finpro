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
                        dial.padding(.top, AppLayout.keyDialTop).padding(.horizontal, -AppSpacing.regular)
                        if viewModel.isRendering {
                            HStack(spacing: AppSpacing.small) {
                                LoadingMascotView(size: AppLayout.loadingMascotInline)
                                LoadingTextView(title: "Preparing key…", font: .appSubheadline, shadowed: false).foregroundStyle(Color.primary300)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                        // No "Vocal notes" line (user decision 2026-11-21); tapping the dial plays the key.
                        if viewModel.selectedNotes != nil, !viewModel.fitsRange {
                            keyInsightCard
                                .padding(.horizontal, AppSpacing.regular)
                                .padding(.top, -AppSpacing.spacious)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.regular).padding(.top, 15).padding(.bottom, 24)
            }
            // The dial's backdrop circle runs on behind the button to the bottom of the screen.
            .scrollClipDisabled()
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
    private var dial: some View {
        GeometryReader { proxy in
            CurvedPitchDial(value: dialValue, center: dialValue, label: { label(Int($0.rounded())) })
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let initial = dragOrigin ?? viewModel.selectedShift ?? 0
                        dragOrigin = initial
                        // Same spacing as the dial's keys along the arc, so the ticks stay under the finger.
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Selected key")
                .accessibilityValue(label(viewModel.selectedShift ?? 0))
                .accessibilityHint("Adjust to change key, or tap to preview with vocals")
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 1 : -1
                    viewModel.chooseShift(min(6, max(-6, (viewModel.selectedShift ?? 0) + step)))
                }
                .overlay(alignment: .topLeading) { recommendedBadge(width: proxy.size.width) }
        }
        .sensoryFeedback(.selection, trigger: Int(dialValue.rounded()))
        .frame(height: CurvedPitchDial.height)
        // The large light circle behind the dial and the lower half of the screen (design 4.5).
        .background(alignment: .top) {
            GeometryReader { proxy in
                let diameter = proxy.size.width * AppLayout.keyDialBackdropScale
                Circle().fill(Color.primary100)
                    .frame(width: diameter, height: diameter)
                    .position(x: proxy.size.width / 2, y: AppLayout.keyDialBackdropTop + diameter / 2)
            }
            .allowsHitTesting(false)
        }
    }

    /// Sits above the recommended key's label and moves with the arc, so it marks one key instead
    /// of whichever key is in the middle.
    @ViewBuilder private func recommendedBadge(width: CGFloat) -> some View {
        if let recommendation = viewModel.recommendedShift {
            let anchor = CurvedPitchDial.labelAnchor(offset: Double(recommendation) - dialValue, width: width, outset: 30)
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { viewModel.chooseShift(recommendation) }
            } label: {
                Text("Recommended").font(.appCaption2.weight(.bold)).foregroundStyle(Color.primary500)
                    .padding(.horizontal, AppSpacing.small).padding(.vertical, AppSpacing.tiny)
                    .background(Color.secBrand, in: Capsule())
                    .fixedSize()
            }
            .rotationEffect(anchor.angle)
            .position(anchor.point)
            .opacity(anchor.opacity)
            .allowsHitTesting(anchor.opacity > 0.5)
            .accessibilityLabel("Use recommended key \(recommendation)")
        }
    }
    private var keyInsightCard: some View {
        let badgeDiameter: CGFloat = 64
        let cardCornerRadius: CGFloat = AppRadius.large
        return ZStack(alignment: .top) {
            Text("Key Insight: Some notes in this key may be difficult to reach.")
                .font(.appCaption)
                .foregroundStyle(Color.primary300)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.large)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.medium + AppSpacing.small)
                .frame(maxWidth: .infinity, minHeight: 82)
                .background(Color.screenBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .padding(.top, badgeDiameter / 2)

            Circle()
                .fill(Color.screenBackground)
                .frame(width: badgeDiameter, height: badgeDiameter)
                .overlay {
                    Image(systemName: "lightbulb.max")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(Color.primaryBrand)
                        .offset(y: -4)
                        .accessibilityHidden(true)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var dialValue: Double { dragValue ?? Double(viewModel.selectedShift ?? 0) }
    private func clamped(_ shift: Double) -> Double {
        min(Double(TranspositionPlan.semitoneRange.upperBound), max(Double(TranspositionPlan.semitoneRange.lowerBound), shift))
    }
    private func label(_ shift: Int) -> String { "[\(shift > 0 ? "+" : "")\(shift)]" }
}

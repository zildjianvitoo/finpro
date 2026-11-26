//
//  KeySelectionView.swift
//  finpro
//

import SwiftUI
import UIKit

struct KeySelectionView: View {
    @State var viewModel: KeySelectionViewModel
    @State private var keyFeedback = UIImpactFeedbackGenerator(style: .light)
    let routeMonitor: any AudioRouteMonitor
    let onChooseAnother: () -> Void
    let onRetest: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    private let wheelWidth: CGFloat = 297
    private let wheelHeight: CGFloat = 216

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: goBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass))
                    .accessibilityLabel("Back to song section")
                Spacer()
            }
            .padding(.horizontal, AppSpacing.regular)

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
        .edgeSwipeBack(action: goBack)
        .accessibilityAction(.escape, goBack)
        .onAppear {
            keyFeedback.prepare()
            viewModel.autoplaySelected()
        }
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
            Text("Find Your Key").font(.appLargeTitle).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text("Listen to each version and choose what feels comfortable to sing.")
                .font(.appSubheadline)
                .padding(.top, AppSpacing.small)
            wheel
                .padding(.top, 122)
                .frame(maxWidth: .infinity)
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

    private var wheel: some View {
        let shift = viewModel.selectedShift ?? 0
        let isRecommended = shift == viewModel.recommendedShift
        return Picker("Selected key", selection: Binding(
            get: { viewModel.selectedShift ?? 0 },
            set: selectKeyFromWheel
        )) {
            ForEach(Array(TranspositionPlan.semitoneRange.reversed()), id: \.self) { value in
                Text(label(value))
                    .font(.appTitle2.weight(value == shift ? .bold : .regular))
                    .foregroundStyle(value == shift ? Color.primaryBrand : Color.primary300)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: wheelWidth + 18)
        .frame(height: wheelHeight)
        .clipped()
        .background {
            Capsule().fill(Color.primary100).frame(width: wheelWidth, height: 33)
        }
        .overlay {
            HStack(spacing: 0) {
                Text("recommended")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.plumNight.lightResolved)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(Color.secBrand, in: RoundedRectangle(cornerRadius: 4))
                    .opacity(isRecommended ? 1 : 0)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 32)
                Text("semitones").font(.appSubheadline)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: wheelWidth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityValue("\(label(shift)) semitones" + (isRecommended ? ", recommended" : ""))
        .accessibilityAction(named: Text("Preview key")) { viewModel.previewSelected() }
    }

    private func selectKeyFromWheel(_ shift: Int) {
        guard shift != viewModel.selectedShift else { return }
        keyFeedback.impactOccurred()
        keyFeedback.prepare()
        viewModel.chooseShift(shift)
    }

    private func goBack() {
        viewModel.stop()
        onChooseAnother()
    }

    private func label(_ shift: Int) -> String { "\(shift > 0 ? "+" : "")\(shift)" }
}

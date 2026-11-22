//
//  RecordingSettingsSheet.swift
//  finpro
//
//  Bottom sheet opened from the recording screen's settings button: Original Vocal, Lyrics, and
//  the Pitch Guide size slider. Values are the per-user preferences in RecordingDisplaySettings.
//

import SwiftUI

struct RecordingSettingsSheet: View {
    let viewModel: RecordingViewModel
    var canResetGuideFrame = false
    var onResetGuideFrame: () -> Void = {}
    /// Reports the sheet's height, so the recording screen can lift the pitch guide above it.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    /// The sheet is as tall as its content.
    @State private var contentHeight: CGFloat = 320

    @AppStorage(RecordingDisplaySettings.showsLyricsKey) private var showsLyrics = true
    @AppStorage(RecordingDisplaySettings.pitchGuideScaleKey) private var pitchGuideScale = RecordingDisplaySettings.defaultPitchGuideScale

    private let horizontalInset: CGFloat = 24
    private let rowHeight: CGFloat = 50
    private let rowSpacing: CGFloat = 12
    private let cardCornerRadius: CGFloat = 30
    private let unavailableOpacity = 0.5
    /// Rows are dark glass over the light sheet.
    private let rowFill = Color.black.opacity(0.41)

    var body: some View {
        VStack(spacing: rowSpacing) {
            Text("Settings")
                .font(.appHeadline)
                .foregroundStyle(Color.black)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            // Songs without a separated vocal cannot switch it, so the row stays but is dimmed.
            switchRow("Original Vocal", isOn: Binding(
                get: { viewModel.referenceVocalEnabled && viewModel.supportsReferenceVocal },
                set: { viewModel.setReferenceVocalEnabled($0) }))
                .opacity(viewModel.supportsReferenceVocal ? 1 : unavailableOpacity)
                .disabled(!viewModel.supportsReferenceVocal)
            switchRow("Lyrics", isOn: $showsLyrics)
            pitchGuideCard
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            contentHeight = $0
            onHeightChange($0)
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.appBody)
                .foregroundStyle(.white)
            Spacer()
            AppSwitch(isOn: isOn)
        }
        .padding(.leading, 19)
        .padding(.trailing, 8)
        .frame(height: rowHeight)
        .background(Capsule().fill(rowFill))
        .accessibilityElement(children: .combine)
    }

    private var pitchGuideCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pitch Guide")
                .font(.appBody)
                .foregroundStyle(.white)
            // Small and large "A" at the ends, dots under the track (design 5.2b).
            HStack(spacing: 12) {
                Text("A").font(.appFootnote.weight(.semibold)).accessibilityHidden(true)
                Slider(value: $pitchGuideScale, in: 0...1) {
                    Text("Pitch Guide size")
                }
                .tint(.blue)
                .overlay(alignment: .bottom) { sliderDots.offset(y: 10) }
                Text("A").font(.appTitle3.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.top, 8)
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1).padding(.top, 22)
            // Shown once the user moved or resized the panel on the recording screen.
            if canResetGuideFrame {
                Button("Reset position and size", action: onResetGuideFrame)
                    .font(.appFootnote.weight(.semibold))
                    .foregroundStyle(Color.secBrand)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous).fill(rowFill))
    }

    private var sliderDots: some View {
        HStack {
            ForEach(0..<Self.sliderDotCount, id: \.self) { index in
                Circle().frame(width: 3, height: 3)
                if index < Self.sliderDotCount - 1 { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 14)
        .accessibilityHidden(true)
    }
    private static let sliderDotCount = 8
}

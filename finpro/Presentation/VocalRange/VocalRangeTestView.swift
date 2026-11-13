//
//  VocalRangeTestView.swift
//  finpro
//

import SwiftUI

struct VocalRangeTestView: View {
    enum Stage: Equatable { case intro, warmup, hummingGuide, lowest, highest, result }
    @State private var viewModel: VocalRangeViewModel
    @State private var stage: Stage = .intro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDismiss: (() -> Void)?

    init(viewModel: VocalRangeViewModel, onDismiss: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        Group {
            if stage == .intro {
                VocalRangeIntroView(onBack: onDismiss) {
                    stage = .warmup
                }
            } else if stage == .result, case .finished(let range) = viewModel.status {
                VocalRangeResultView(range: range, isFemale: false, onDone: viewModel.save) {
                    viewModel.restart()
                    stage = .intro
                }
            } else {
                testStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
        .onDisappear { viewModel.stopListening() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, viewModel.status == .listening {
                viewModel.resetCapture()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    private var isWarmup: Bool { stage == .warmup }
    private var isHumming: Bool { stage == .hummingGuide }
    private var isLowest: Bool { stage == .lowest }
    private var foreground: Color { isWarmup ? .secBrand : .primaryBrand }
    private var displayMIDI: Float? {
        if case .captured(let note) = viewModel.status { return note }
        return viewModel.liveMIDI
    }
    private var title: String {
        switch stage {
        case .warmup: "Let's warm up"
        case .hummingGuide: "Humming"
        case .lowest: "Find your lowest\nnote"
        default: "Now, find your\nhighest note"
        }
    }
    private var subtitle: String {
        switch stage {
        case .warmup: "Read the sentences below in your everyday voice"
        case .hummingGuide: "Start from a low tone and slowly guide up"
        case .lowest: "Say “Do” as low as you can and hold it."
        default: "Say “Do” as high as you can and hold it."
        }
    }

    private var testStep: some View {
        GeometryReader { proxy in
            let diameter = min(AppLayout.microphoneDiameter, max(120, proxy.size.height * 0.224))
            let micCenter = proxy.size.height * 0.76
            let headerHeight = proxy.size.height * ((isWarmup || isHumming) ? 0.28 : 0.25)
            let contentHeight = max(40, micCenter - diameter / 2 - headerHeight - AppSpacing.regular)
            ZStack(alignment: .topLeading) {
                header(height: headerHeight)
                ScrollView {
                    stepContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: max(1, proxy.size.width - AppSpacing.textInset * 2), height: contentHeight)
                .position(x: proxy.size.width / 2, y: headerHeight + contentHeight / 2)

                microphone(diameter: diameter)
                    .position(x: proxy.size.width / 2, y: micCenter)

                VStack {
                    Spacer(minLength: 0)
                    action.buttonStyle(.appPrimary)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.bottom, AppSpacing.medium)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func header(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) { Image(systemName: "chevron.left") }
                .buttonStyle(.appIcon(.tinted)).accessibilityLabel("Back")
                .padding(.horizontal, AppSpacing.regular)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title).font(.appLargeTitle).foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.appSubheadline)
                    .foregroundStyle(isWarmup ? Color.secBrand : Color.primaryBrand)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.textInset).padding(.top, AppSpacing.large)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: height)
        .background {
            if isWarmup || isHumming {
                SpeechBubbleShape().fill(isWarmup ? Color.primaryBrand : Color.secBrand)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if isWarmup {
                Text(passage).font(.appTitle2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(viewModel.instructions)
                    .padding(.top, AppSpacing.large)
            } else if isHumming {
                Text("Hummmmmm").font(.appHeadline).foregroundStyle(Color.primaryBrand)
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.large)
                    .background(Color.secondaryButton, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                    .padding(.top, AppSpacing.section)
                Text("Tip: Keep your voice steady. Stop before your voice feels strained or turns into vocal fry.")
                    .font(.appCaption).foregroundStyle(Color.secondaryText)
            } else {
                VocalPitchRuler(midi: displayMIDI, referenceMIDI: viewModel.baselineMIDI ?? 57)
                    .id(viewModel.prompt)
                    .padding(.top, AppSpacing.regular)
            }
            if case .failed(let error) = viewModel.status { ErrorStateView(error: error) }
        }
    }

    private func microphone(diameter: CGFloat) -> some View {
        Button { viewModel.toggleMicrophone(practice: isHumming) } label: {
            VocalRangeRing(progress: viewModel.holdProgress,
                           isListening: viewModel.status == .listening,
                           hearsVoice: viewModel.liveMIDI != nil, label: "Microphone",
                           showsMicrophoneIcon: !viewModel.hasStartedListening,
                           levels: viewModel.waveformLevels, diameter: diameter)
        }
        .buttonStyle(.plain).contentShape(Circle())
        .accessibilityLabel(viewModel.status == .listening ? "Stop microphone" : "Start microphone")
        .accessibilityHint(isWarmup ? "Tap and read the paragraph aloud" : "Tap and hold a comfortable note for 1 second")
        .accessibilityValue(Text(viewModel.holdProgress, format: .percent.precision(.fractionLength(0))))
    }

    private var passage: AttributedString {
        var text = AttributedString(viewModel.instructions)
        text.foregroundColor = Color.secondaryText.opacity(0.65)
        // Highlight only complete words. Time advances only while the microphone hears speech.
        let words = viewModel.instructions.split(whereSeparator: \.isWhitespace)
        let count = Int(Double(words.count) * viewModel.holdProgress)
        let readCount = words.prefix(count).last.map {
            viewModel.instructions.distance(from: viewModel.instructions.startIndex, to: $0.endIndex)
        } ?? 0
        let end = text.index(text.startIndex, offsetByCharacters: readCount)
        text[text.startIndex..<end].foregroundColor = .primaryBrand
        return text
    }

    @ViewBuilder private var action: some View {
        if case .failed = viewModel.status {
            Button("Try again") { viewModel.resetCapture() }
        } else {
            Button("Continue") {
                if isWarmup {
                    viewModel.next()
                    stage = .hummingGuide
                } else if isHumming {
                    viewModel.resetCapture()
                    stage = .lowest
                } else if case .finished = viewModel.status {
                    stage = .result
                } else if isLowest {
                    viewModel.next()
                    stage = .highest
                }
            }
            .disabled(!canContinue)
        }
    }

    private var canContinue: Bool {
        if isHumming { return viewModel.hasPracticedHumming }
        if case .captured = viewModel.status { return true }
        if case .finished = viewModel.status { return true }
        return false
    }

    private func back() {
        viewModel.stopListening()
        switch stage {
        case .warmup: viewModel.restart(); stage = .intro
        case .hummingGuide:
            viewModel.restart(); stage = .warmup
        case .lowest: viewModel.resetCapture(); stage = .hummingGuide
        case .highest:
            viewModel.previous(); stage = .lowest
        default: stage = .intro
        }
    }
}

#Preview {
    VocalRangeTestView(viewModel: VocalRangeViewModel(
        source: FakeLivePitchSource(notes: [57, 57, 48, 67]),
        repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {}))
}

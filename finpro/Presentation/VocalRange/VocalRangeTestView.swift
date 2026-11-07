//
//  VocalRangeTestView.swift
//  finpro
//
//  Complete vocal range onboarding flow:
//  Intro -> Voice description -> Warm up -> Humming -> Lowest note -> Highest note -> Result screen.
//

import SwiftUI

struct VocalRangeTestView: View {
    enum Stage {
        case intro
        case voiceProfile
        case warmup
        case hummingGuide
        case test
        case result(VocalRange)
    }

    @State private var viewModel: VocalRangeViewModel
    @State private var stage: Stage = .intro
    @State private var showsHelp = false
    @State private var voiceType: VocalRangeVoiceProfileView.VoiceType? = .female

    let onDismiss: (() -> Void)?

    init(viewModel: VocalRangeViewModel, onDismiss: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        Group {
            switch stage {
            case .intro:
                VocalRangeIntroView(onBack: onDismiss) {
                    stage = .voiceProfile
                }
                .transition(.opacity)

            case .voiceProfile:
                VocalRangeVoiceProfileView(
                    onBack: { stage = .intro },
                    onContinue: { type in
                        voiceType = type
                        stage = .warmup
                        viewModel.listen()
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .warmup:
                warmupScreen
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .hummingGuide:
                hummingGuideScreen
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .test:
                testScreen
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .result(let range):
                VocalRangeResultView(
                    range: range,
                    isFemale: voiceType == .female,
                    onDone: {
                        viewModel.save()
                    },
                    onRetake: {
                        viewModel.restart()
                        stage = .intro
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.default, value: isResultStage)
        .onDisappear { viewModel.stopListening() }
        .sheet(isPresented: $showsHelp) { help }
        .onChange(of: viewModel.status) { _, newStatus in
            if case .finished(let range) = newStatus {
                withAnimation {
                    stage = .result(range)
                }
            }
        }
    }

    private var isResultStage: Bool {
        if case .result = stage { true } else { false }
    }

    private var isCaptured: Bool {
        if case .captured = viewModel.status { true } else { false }
    }

    // MARK: - Layout

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Leading inset of the text and ring area, and both insets of the tip card, per the design.
    private let contentInset: CGFloat = 52
    /// Trailing inset of the text and ring area per the design (narrower than the leading one).
    private let contentTrailingInset: CGFloat = 40
    /// Keeps the title in place under the large glass back button.
    private let topBarHeight: CGFloat = 48
    /// Gap between the tip card and the main button per the design.
    private let tipToButtonSpacing: CGFloat = 56
    /// Pushes the humming ring below the centre of the free space, as drawn in the design.
    private let hummingRingDrop: CGFloat = 40
    /// Same for the lowest and highest note ring, meter and note group.
    private let noteRingDrop: CGFloat = 16
    private let meterWidth: CGFloat = 257
    private let meterHeight: CGFloat = 24
    /// Smallest visible fill of the meter so the lime end cap is always shown.
    private let meterMinimumFraction: Double = 0.2

    private static let warmupPassage = "The sky looks so beautiful this morning, with soft clouds floating across the blue sky. A gentle breeze comes through the trees, and the air feels cool and refreshing."

    /// Shared frame of the test steps: back button, title, subtitle, a scrollable body whose
    /// spacers center the ring, then an optional tip card and the main button.
    private func stepLayout<Content: View, Action: View>(
        title: String,
        subtitle: String,
        tip: String? = nil,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let content = content()
        let action = action()

        return VStack(spacing: 0) {
            topBar(onBack: onBack)

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title)
                                .font(.largeTitle.bold())
                                .foregroundStyle(Color.plumInk)
                                .accessibilityAddTraits(.isHeader)

                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(Color.plumInkSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)

                        content
                    }
                    .padding(.leading, contentInset)
                    .padding(.trailing, contentTrailingInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: tipToButtonSpacing) {
                if let tip {
                    TipCard(message: tip)
                        .padding(.horizontal, contentInset)
                }
                action
                    .buttonStyle(.primaryDeep)
                    .padding(.horizontal, buttonInset)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color.onboardingBackground.ignoresSafeArea())
    }

    /// - Parameter isDemo: Animates the waveform as a guide even though no pitch is captured
    ///   on this step (humming is practice only).
    private func ringGroup(caption: String, showsMicrophoneIcon: Bool = false, isDemo: Bool = false) -> some View {
        VStack(spacing: 8) {
            VocalRangeRing(
                progress: viewModel.holdProgress,
                isListening: isDemo || viewModel.status == .listening,
                hearsVoice: isDemo || viewModel.liveMIDI != nil,
                label: caption,
                showsMicrophoneIcon: showsMicrophoneIcon
            )

            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color.plumInkSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Warm Up Screen

    private var warmupScreen: some View {
        stepLayout(
            title: "Let’s warm up",
            subtitle: "Read the sentences below in your everyday voice",
            onBack: {
                viewModel.restart()
                stage = .voiceProfile
            },
            content: {
                Text(warmupPassageText)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 38)
                    .accessibilityLabel(Self.warmupPassage)

                Spacer(minLength: 24)
                ringGroup(caption: "Listening...", showsMicrophoneIcon: true)
                Spacer(minLength: 24)
            },
            action: {
                Button("Continue") {
                    viewModel.next()
                    stage = .hummingGuide
                }
            }
        )
    }

    /// The passage with the part already read (by elapsed speaking time) in full color
    /// and the rest dimmed, so the user can follow along at a natural pace.
    private var warmupPassageText: AttributedString {
        var text = AttributedString(Self.warmupPassage)
        let progress = viewModel.prompt == .speaking ? viewModel.holdProgress : 1
        let readCount = Int((Double(Self.warmupPassage.count) * progress).rounded())
        let split = text.index(text.startIndex, offsetByCharacters: readCount)
        text[text.startIndex..<split].foregroundColor = .primary
        text[split...].foregroundColor = Color(.tertiaryLabel)
        return text
    }

    // MARK: - Humming Guide Screen

    private var hummingGuideScreen: some View {
        stepLayout(
            title: "Humming",
            subtitle: "Start from a low tone and slowly guide up",
            tip: "Keep your voice steady. Stop before your voice feels strained or turns into vocal fry.",
            onBack: {
                viewModel.restart()
                stage = .warmup
                viewModel.listen()
            },
            content: {
                Spacer(minLength: 24)
                ringGroup(caption: "Hhmm...", isDemo: true)
                    .padding(.top, hummingRingDrop)
                Spacer(minLength: 24)
            },
            action: {
                Button("Continue") {
                    stage = .test
                    viewModel.listen()
                }
            }
        )
    }

    // MARK: - Lowest & Highest Test Screen

    private var testScreen: some View {
        let isLowest = viewModel.prompt != .highest

        return stepLayout(
            title: isLowest ? "Find your\nlowest note" : "Now, find your\nhighest note",
            subtitle: isLowest ? "Say “Do” as low as you can and hold it." : "Say “Do” as high as you can and hold it.",
            tip: isLowest
                ? "Hold at the lowest note you can make comfortably, without vocal fry or strain."
                : "Hold at the highest note that stays clear and comfortable. Falsetto is okay.",
            onBack: {
                if !isLowest { viewModel.restart() }
                stage = .hummingGuide
            },
            content: {
                Spacer(minLength: 24)

                VStack(spacing: 0) {
                    ringGroup(caption: "Listening...")

                    meterBar(isLowest: isLowest)
                        .padding(.top, 36)

                    noteLabel
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, noteRingDrop)

                Spacer(minLength: 24)
            },
            action: { actions(isLowest: isLowest) }
        )
    }

    /// Hold meter: lime fills from the left for the lowest note and from the right for the highest.
    private func meterBar(isLowest: Bool) -> some View {
        let fraction = max(meterMinimumFraction, viewModel.holdProgress)

        return ZStack(alignment: isLowest ? .leading : .trailing) {
            Capsule()
                .fill(Color.plumNight)

            Capsule()
                .fill(Color.micIconHighlight)
                .overlay(Capsule().strokeBorder(Color.plumNight, lineWidth: 2))
                .frame(width: meterWidth * fraction)
        }
        .frame(width: meterWidth, height: meterHeight)
        .animation(.easeOut(duration: 0.15), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Hold progress")
        .accessibilityValue(Text(viewModel.holdProgress, format: .percent.precision(.fractionLength(0))))
    }

    /// The heard note and its frequency, or a dash until a voice is heard.
    private var noteLabel: some View {
        VStack(spacing: 2) {
            Text(currentDisplayMIDI.map { PitchMath.noteName(midi: Int($0.rounded())) } ?? "–")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(currentDisplayMIDI.map { "(\(Int(PitchMath.frequency(fromMIDI: Double($0)).rounded())) Hz)" } ?? " ")
                .font(.subheadline)
                .foregroundStyle(Color.plumInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var currentDisplayMIDI: Float? {
        switch viewModel.status {
        case .captured(let note): note
        case .listening: viewModel.liveMIDI
        default: nil
        }
    }

    @ViewBuilder
    private func actions(isLowest: Bool) -> some View {
        switch viewModel.status {
        case .idle, .listening, .captured:
            Button(isLowest ? "Continue" : "Check Result") {
                viewModel.next()
                if isLowest {
                    viewModel.listen()
                } else if case .finished(let range) = viewModel.status {
                    stage = .result(range)
                } else {
                    stage = .result(VocalRange(lowestMIDI: 45, highestMIDI: 76))
                }
            }

        case .finished(let range):
            Button("Check Result") {
                stage = .result(range)
            }

        case .failed:
            Button("Retry") { viewModel.listen() }
        }
    }

    private func topBar(onBack: @escaping () -> Void) -> some View {
        HStack {
            LiquidGlassGroup {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .glassCircleButtonStyle()
                .accessibilityLabel("Back")
            }
            Spacer()
        }
        .frame(minHeight: topBarHeight)
        .padding(.horizontal, buttonInset)
    }

    // MARK: - Help Sheet

    private var help: some View {
        NavigationStack {
            List {
                Section("Steps") {
                    Label("Warm up: read aloud in your normal speaking voice.", systemImage: "1.circle")
                    Label("Humming: start low and guide upward.", systemImage: "2.circle")
                    Label("Find your lowest and highest comfortable notes.", systemImage: "3.circle")
                }
                Section {
                    Label("Connect a headset with a microphone for best accuracy.", systemImage: "headphones")
                    Label("Hold steady until the meter fills.", systemImage: "circle.dashed")
                }
            }
            .navigationTitle("How the test works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsHelp = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
#Preview {
    VocalRangeTestView(
        viewModel: VocalRangeViewModel(
            source: FakeLivePitchSource(notes: [57, 48, 67]),
            repository: FakeVocalRangeRepository(),
            configuration: .default,
            onSaved: {}
        )
    )
}
#endif

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

    // MARK: - Warm Up Screen (Screen 5 from previous sheet)

    private var warmupScreen: some View {
        VStack(spacing: 0) {
            topBar(onBack: {
                viewModel.restart()
                stage = .voiceProfile
            })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Let's warm up")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.brandPlum)

                        Text("Read the sentences below in your everyday voice")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("The sky looks so beautiful this morning, with soft clouds floating across the blue sky. A gentle breeze comes through the trees, and the air feels cool and refreshing.")
                        .font(.system(size: 16, weight: .regular))
                        .lineSpacing(4)
                        .foregroundStyle(.primary)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    VStack(spacing: 8) {
                        VocalRangeRing(
                            progress: viewModel.holdProgress,
                            isListening: viewModel.status == .listening,
                            hearsVoice: viewModel.liveMIDI != nil,
                            label: "Listening...",
                            showsMicrophoneIcon: true
                        )

                        Text("Listening...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Button("Continue") {
                        viewModel.next()
                        stage = .hummingGuide
                    }
                    .buttonStyle(.primary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color(.systemBackground))
            }
        }
    }

    // MARK: - Humming Guide Screen (Screen 1 from latest sheet)

    private var hummingGuideScreen: some View {
        VStack(spacing: 0) {
            topBar(onBack: {
                viewModel.restart()
                stage = .warmup
                viewModel.listen()
            })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Humming")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.brandPlum)

                        Text("Start from a low tone and slowly guide up")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 24)

                    VStack(spacing: 8) {
                        VocalRangeRing(
                            progress: 0.35,
                            isListening: true,
                            hearsVoice: true,
                            label: "Hmm..."
                        )

                        Text("Hhmm...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 16) {
                    TipCard(
                        message: "Keep your voice steady. Stop before your voice feels strained or turns into vocal fry.",
                        systemImage: "lightbulb"
                    )

                    Button("Continue") {
                        stage = .test
                        viewModel.listen()
                    }
                    .buttonStyle(.primary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color(.systemBackground))
            }
        }
    }

    // MARK: - Lowest & Highest Test Screen (Screens 2 & 3)

    private var testScreen: some View {
        let isLowest = viewModel.prompt != .highest

        return VStack(spacing: 0) {
            topBar(onBack: {
                if isLowest {
                    stage = .hummingGuide
                } else {
                    viewModel.restart()
                    stage = .hummingGuide
                }
            })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isLowest ? "Find your\nlowest note" : "Now, find your\nhighest note")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.brandPlum)

                        Text("Say \"Do\" as low as you can and hold it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 16)

                    VStack(spacing: 12) {
                        VocalRangeRing(
                            progress: viewModel.holdProgress,
                            isListening: viewModel.status == .listening,
                            hearsVoice: viewModel.liveMIDI != nil,
                            label: "Listening..."
                        )

                        Text("Listening...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Meter bar pill (lime on left for lowest, right for highest)
                        meterBar(isLowest: isLowest)
                            .padding(.top, 8)

                        // Note and frequency
                        noteLabel(isLowest: isLowest)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 16) {
                    TipCard(
                        message: isLowest ?
                            "Hold at the lowest note you can make comfortably, without vocal fry or strain." :
                            "Hold at the highest note that stays clear and comfortable. Falsetto is okay.",
                        systemImage: "lightbulb"
                    )

                    actions(isLowest: isLowest)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color(.systemBackground))
            }
        }
    }

    private func meterBar(isLowest: Bool) -> some View {
        ZStack(alignment: isLowest ? .leading : .trailing) {
            Capsule()
                .fill(Color(red: 0.20, green: 0.10, blue: 0.18))
                .frame(width: 220, height: 16)

            Capsule()
                .fill(Color.micIconHighlight)
                .frame(width: max(24, 220 * max(0.2, viewModel.holdProgress)), height: 16)
        }
        .frame(width: 220, height: 16)
    }

    private func noteLabel(isLowest: Bool) -> some View {
        VStack(spacing: 2) {
            let noteName = currentDisplayNoteName(isLowest: isLowest)
            Text(noteName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            if let midi = currentDisplayMIDI {
                let freq = Int(PitchMath.frequency(fromMIDI: Double(midi)).rounded())
                Text("(\(freq) Hz)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                Text(isLowest ? "(65 Hz)" : "(880 Hz)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func currentDisplayNoteName(isLowest: Bool) -> String {
        switch viewModel.status {
        case .captured(let note):
            PitchMath.noteName(midi: Int(note.rounded()))
        case .listening:
            viewModel.liveNoteName ?? (isLowest ? "C2" : "A5")
        default:
            isLowest ? "C2" : "A5"
        }
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
        case .idle, .listening:
            Button(isLowest ? "Continue" : "Check Result") {
                if isLowest {
                    viewModel.next()
                    viewModel.listen()
                } else {
                    viewModel.next()
                    if case .finished(let range) = viewModel.status {
                        stage = .result(range)
                    } else {
                        stage = .result(VocalRange(lowestMIDI: 45, highestMIDI: 76))
                    }
                }
            }
            .buttonStyle(.primary)

        case .captured:
            Button(isLowest ? "Continue" : "Check Result") {
                if isLowest {
                    viewModel.next()
                    viewModel.listen()
                } else {
                    viewModel.next()
                    if case .finished(let range) = viewModel.status {
                        stage = .result(range)
                    } else {
                        stage = .result(VocalRange(lowestMIDI: 45, highestMIDI: 76))
                    }
                }
            }
            .buttonStyle(.primary)

        case .finished(let range):
            Button("Check Result") {
                stage = .result(range)
            }
            .buttonStyle(.primary)

        case .failed:
            Button("Retry") { viewModel.listen() }
                .buttonStyle(.primary)
        }
    }

    private func topBar(onBack: @escaping () -> Void) -> some View {
        HStack {
            LiquidGlassGroup {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .liquidGlassCircle()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
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

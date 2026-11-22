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
    /// Where audio goes now; nil until known. Earphones plugged in or out update it.
    let routeMonitor: (any AudioRouteMonitor)?
    @State private var outputRoute: AudioOutputRoute?
    /// A failed listen (e.g. no headset microphone), shown as a system alert.
    @State private var showsFailure = false
    /// "Get your setup ready" (a system alert), offered once per visit to the warm-up when sound
    /// still plays through the speaker; it closes on its own once earphones are connected.
    @State private var showsEarphoneSetup = false
    @State private var offeredEarphoneSetup = false

    init(viewModel: VocalRangeViewModel, routeMonitor: (any AudioRouteMonitor)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.routeMonitor = routeMonitor
        self.onDismiss = onDismiss
    }

    var body: some View {
        Group {
            if stage == .intro {
                VocalRangeIntroView(onBack: onDismiss) {
                    stage = .warmup
                }
                .edgeSwipeBack(isEnabled: onDismiss != nil) { onDismiss?() }
            } else if stage == .result, case .finished(let range) = viewModel.status {
                VocalRangeResultView(range: range, isFemale: false, onDone: viewModel.save, onRetake: {
                    viewModel.restart()
                    stage = .intro
                }, onBack: {
                    viewModel.redoHighest()
                    if viewModel.lowestMIDI == nil {
                        stage = .intro
                    } else {
                        stage = .highest
                        viewModel.listen()
                    }
                })
            } else {
                testStep
                    .edgeSwipeBack(isEnabled: !showsFailure && !showsEarphoneSetup, interactiveSlide: false, action: back)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
        .onDisappear { viewModel.stopListening() }
        .alert(failure?.title ?? "", isPresented: $showsFailure, presenting: failure) { _ in
            Button("Try Again") {
                viewModel.resetCapture()
                viewModel.toggleMicrophone(practice: isHumming)
            }
            Button("OK", role: .cancel) { viewModel.resetCapture() }
        } message: { error in
            Text(error.message)
        }
        .onChange(of: failure) { _, error in showsFailure = error != nil }
        .alert("Get your setup ready", isPresented: $showsEarphoneSetup) {
            Button("Got It", role: .cancel) {}
        } message: {
            Text("Use wired earphones or headphones for more synchronized audio. Bluetooth may cause recording delays.")
        }
        .onChange(of: stage) { _, stage in
            if stage == .intro { offeredEarphoneSetup = false }
            offerEarphoneSetupIfNeeded()
        }
        .onChange(of: outputRoute) { _, _ in
            if !showsEarphoneHint { showsEarphoneSetup = false }
            offerEarphoneSetupIfNeeded()
        }
        .task {
            guard let routeMonitor else { return }
            outputRoute = routeMonitor.currentRoute
            for await route in routeMonitor.routeChanges() { outputRoute = route }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, viewModel.status == .listening {
                viewModel.resetCapture()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    private func offerEarphoneSetupIfNeeded() {
        guard isWarmup, showsEarphoneHint, !offeredEarphoneSetup else { return }
        offeredEarphoneSetup = true
        showsEarphoneSetup = true
    }

    private var failure: UserFacingError? {
        if case .failed(let error) = viewModel.status { error } else { nil }
    }

    /// Sound goes to the phone's speaker, so no earphones (and no headset microphone) are connected.
    private var showsEarphoneHint: Bool {
        outputRoute == .speaker && !DebugOptions.allowsSpeakerRecording
    }

    /// The small "Connect earphones" pill: not on the warm-up, where the setup alert says it.
    private var showsEarphonePill: Bool { showsEarphoneHint && !isWarmup }

    private var isWarmup: Bool { stage == .warmup }
    private var isHumming: Bool { stage == .hummingGuide }
    private var isLowest: Bool { stage == .lowest }
    private var isCaptured: Bool {
        if case .captured = viewModel.status { return true }
        return false
    }
    private var displayMIDI: Float? {
        if case .captured(let note) = viewModel.status { return note }
        return viewModel.liveMIDI
    }
    private var title: String {
        switch stage {
        case .warmup: "Let’s warm up"
        case .hummingGuide: "Humming"
        case .lowest: "Find your lowest\nnote"
        default: "Now, find your\nhighest note"
        }
    }
    /// Width of the subtitle's text box in the design, so its lines break where the design's do.
    private var subtitleWidth: CGFloat {
        switch stage {
        case .warmup: 294
        case .hummingGuide: 273
        case .lowest: 295
        default: 303
        }
    }
    private var subtitle: String {
        switch stage {
        case .warmup: "Read the sentences below in your everyday speaking voice."
        case .hummingGuide: "Start from a low tone and slowly glide up."
        case .lowest: "Sing “Do” as low as comfortably possible and hold it."
        default: "Sing “Do” as high as feels comfortable and hold it."
        }
    }

    private var testStep: some View {
        GeometryReader { proxy in
            let diameter = min(AppLayout.microphoneDiameter, max(120, proxy.size.height * 0.224))
            // Mic centre at y 633 of the 874 pt design frames (2.2–2.5).
            let micCenter = proxy.size.height * 0.734
            let headerHeight = proxy.size.height * (isWarmup ? 0.31 : 0.25)
            let hintHeight: CGFloat = showsEarphonePill ? 32 : 0
            let contentHeight = max(40, micCenter - diameter / 2 - headerHeight - AppSpacing.regular - hintHeight)
            ZStack(alignment: .topLeading) {
                header(height: headerHeight)
                ScrollView {
                    stepContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: max(1, proxy.size.width - AppSpacing.textInset * 2), height: contentHeight)
                .position(x: proxy.size.width / 2, y: headerHeight + contentHeight / 2)

                if showsEarphonePill {
                    earphoneHint
                        .position(x: proxy.size.width / 2, y: micCenter - diameter / 2 - AppSpacing.regular)
                        .transition(.opacity)
                }

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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsEarphonePill)
        }
    }

    private var earphoneHint: some View {
        Label("Connect earphones with a mic", systemImage: "headphones")
            .font(.appFootnote.weight(.semibold))
            .foregroundStyle(Color.primaryBrand)
            .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.tiny)
            .background(Color.primary100, in: Capsule())
    }

    private func header(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) { Image(systemName: "chevron.left") }
                .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                .padding(.horizontal, AppSpacing.regular)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title).font(.appLargeTitle).foregroundStyle(Color.primaryBrand)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.appBody)
                    .foregroundStyle(Color.primary300)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: subtitleWidth, alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.textInset).padding(.top, AppSpacing.large)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: height)
        .background {
            if isWarmup {
                SpeechBubbleShape().fill(Color.primary100)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if isWarmup {
                Text(passage).font(.appTitle2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 294, alignment: .leading)
                    .accessibilityLabel(viewModel.instructions)
                    .padding(.top, AppSpacing.medium)
            } else if isHumming {
                VStack(spacing: AppSpacing.small) {
                    Text("“Hummmmmm…”").font(.appDisplay(size: 24)).foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(Color.primary100, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                    Text("Tip: Keep your voice steady. Stop before your voice feels strained or turns into vocal fry.")
                        .font(.appFootnote).foregroundStyle(Color.primary300)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 289)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.spacious + AppSpacing.section)
            } else {
                VocalPitchMeter(midi: displayMIDI, referenceMIDI: viewModel.baselineMIDI ?? 57,
                                direction: isLowest ? .lowest : .highest,
                                holdProgress: viewModel.holdProgress, isCaptured: isCaptured)
                    .id(viewModel.prompt)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppSpacing.spacious + AppSpacing.tiny)
            }
        }
        // Full width and leading, so the text lines up with the title (a scroll view centres
        // content narrower than itself).
        .frame(maxWidth: .infinity, alignment: .leading)
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
        text.foregroundColor = Color.passageUnread
        // Highlight only complete words. Time advances while the microphone hears speech (short pauses included).
        let words = viewModel.instructions.split(whereSeparator: \.isWhitespace)
        let count = Int(Double(words.count) * viewModel.holdProgress)
        let readCount = words.prefix(count).last.map {
            viewModel.instructions.distance(from: viewModel.instructions.startIndex, to: $0.endIndex)
        } ?? 0
        let end = text.index(text.startIndex, offsetByCharacters: readCount)
        text[text.startIndex..<end].foregroundColor = .primary
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
                    viewModel.listen(practice: true)
                } else if isHumming {
                    viewModel.resetCapture()
                    stage = .lowest
                    viewModel.listen()
                } else if case .finished = viewModel.status {
                    stage = .result
                } else if isLowest {
                    viewModel.next()
                    stage = .highest
                    viewModel.listen()
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
        case .lowest:
            viewModel.resetCapture()
            stage = .hummingGuide
            viewModel.listen(practice: true)
        case .highest:
            viewModel.previous()
            stage = .lowest
            viewModel.listen()
        default: stage = .intro
        }
    }
}

#if DEBUG
#Preview {
    VocalRangeTestView(viewModel: VocalRangeViewModel(
        source: FakeLivePitchSource(notes: [57, 57, 48, 67]),
        repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {}))
}
#endif

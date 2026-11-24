//
//  VocalRangeTestView.swift
//  finpro
//

import SwiftUI

struct VocalRangeTestView: View {
    enum Stage: Int, Equatable, Comparable, CaseIterable, Identifiable {
        case intro = 0, warmup, hummingGuide, lowest, highest, result
        var id: Int { rawValue }
        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    @State private var viewModel: VocalRangeViewModel
    @State private var stage: Stage = .intro
    @State private var stageDragProgress: CGFloat = 0
    /// Snapshot of the finished range so `VocalRangeResultView` keeps rendering while sliding out.
    @State private var completedRange: VocalRange?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDismiss: (() -> Void)?
    let onDismissRevealProgress: ((CGFloat) -> Void)?
    /// Where audio goes now; nil until known. Earphones plugged in or out update it.
    let routeMonitor: (any AudioRouteMonitor)?
    @State private var outputRoute: AudioOutputRoute?
    /// A failed listen (e.g. no headset microphone), shown as a system alert.
    @State private var showsFailure = false
    /// "Get your setup ready" (a system alert), offered once per visit to the warm-up when sound
    /// still plays through the speaker; it closes on its own once earphones are connected.
    @State private var showsEarphoneSetup = false
    @State private var offeredEarphoneSetup = false

    init(viewModel: VocalRangeViewModel, routeMonitor: (any AudioRouteMonitor)? = nil,
         onDismiss: (() -> Void)? = nil, onDismissRevealProgress: ((CGFloat) -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.routeMonitor = routeMonitor
        self.onDismiss = onDismiss
        self.onDismissRevealProgress = onDismissRevealProgress
    }

    private var stageTransitionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var activeResultRange: VocalRange? {
        if case .finished(let range) = viewModel.status { return range }
        return completedRange
    }

    var body: some View {
        ZStack {
            ForEach(Stage.allCases.filter { $0 <= stage }) { layerStage in
                let isTop = layerStage == stage
                let isImmediateUnderlay = layerStage.rawValue == stage.rawValue - 1
                let isVisible = isTop || isImmediateUnderlay
                stageLayer(for: layerStage, isTop: isTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .hierarchicalUnderlay(isCovered: !isTop, revealProgress: isImmediateUnderlay ? stageDragProgress : 0)
                    .opacity(isVisible ? 1 : 0)
                    .zIndex(Double(layerStage.rawValue))
                    .transition(layerStage == .intro ? .identity : .move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(stageTransitionAnimation, value: stage)
        .onDisappear { viewModel.stopListening() }
        .alert(failure?.title ?? "", isPresented: $showsFailure, presenting: failure) { _ in
            Button("Try Again") {
                viewModel.resetCapture()
                viewModel.toggleMicrophone(practice: stage == .hummingGuide)
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

    @ViewBuilder
    private func stageLayer(for layerStage: Stage, isTop: Bool) -> some View {
        switch layerStage {
        case .intro:
            VocalRangeIntroView(isActive: isTop, onBack: onDismiss) {
                transition(to: .warmup)
            }
            .edgeSwipeBack(isEnabled: isTop && onDismiss != nil, onProgress: onDismissRevealProgress) {
                onDismiss?()
            }
        case .result:
            if let range = activeResultRange {
                VocalRangeResultView(
                    range: range, isFemale: false, onDone: viewModel.save,
                    onRetake: {
                        viewModel.restart()
                        completedRange = nil
                        transition(to: .intro)
                    },
                    onBack: backFromResult,
                    isSwipeBackEnabled: isTop,
                    onSwipeProgress: { stageDragProgress = $0 }
                )
            }
        case .warmup, .hummingGuide, .lowest, .highest:
            testStep(for: layerStage, isActive: isTop)
                .background(Color.screenBackground.ignoresSafeArea())
                .edgeSwipeBack(isEnabled: isTop && !showsFailure && !showsEarphoneSetup,
                               interactiveSlide: true,
                               onProgress: { stageDragProgress = $0 },
                               action: back)
        }
    }

    private func transition(to target: Stage) {
        withAnimation(stageTransitionAnimation) {
            stageDragProgress = 0
            stage = target
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    private func offerEarphoneSetupIfNeeded() {
        guard stage == .warmup, showsEarphoneHint, !offeredEarphoneSetup else { return }
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
    private func showsEarphonePill(for stepStage: Stage) -> Bool {
        showsEarphoneHint && stepStage != .warmup
    }

    private func isCaptured(for stepStage: Stage, isActive: Bool) -> Bool {
        guard isActive else { return true }
        if case .captured = viewModel.status { return true }
        if case .finished = viewModel.status { return true }
        return false
    }

    private func displayMIDI(for stepStage: Stage, isActive: Bool) -> Float? {
        if !isActive {
            return stepStage == .lowest ? viewModel.lowestMIDI : viewModel.highestMIDI
        }
        if case .captured(let note) = viewModel.status { return note }
        if case .finished(let range) = viewModel.status { return range.highestMIDI }
        return viewModel.liveMIDI
    }

    private func title(for stepStage: Stage) -> String {
        switch stepStage {
        case .warmup: "Let’s warm up"
        case .hummingGuide: "Humming"
        case .lowest: "Find your lowest\nnote"
        default: "Now, find your\nhighest note"
        }
    }

    /// Width of the subtitle's text box in the design, so its lines break where the design's do.
    private func subtitleWidth(for stepStage: Stage) -> CGFloat {
        switch stepStage {
        case .warmup: 294
        case .hummingGuide: 273
        case .lowest: 295
        default: 303
        }
    }

    private func subtitle(for stepStage: Stage) -> String {
        switch stepStage {
        case .warmup: "Read the sentences below in your everyday speaking voice."
        case .hummingGuide: "Start from a low tone and slowly glide up."
        case .lowest: "Sing “Do” as low as comfortably possible and hold it."
        default: "Sing “Do” as high as feels comfortable and hold it."
        }
    }

    private func testStep(for stepStage: Stage, isActive: Bool) -> some View {
        let isWarmup = stepStage == .warmup
        let showsPill = showsEarphonePill(for: stepStage)
        return GeometryReader { proxy in
            let diameter = min(AppLayout.microphoneDiameter, max(120, proxy.size.height * 0.224))
            // Mic centre at y 633 of the 874 pt design frames (2.2–2.5).
            let micCenter = proxy.size.height * 0.734
            let headerHeight = proxy.size.height * (isWarmup ? 0.31 : 0.25)
            let hintHeight: CGFloat = showsPill ? 32 : 0
            let contentHeight = max(40, micCenter - diameter / 2 - headerHeight - AppSpacing.regular - hintHeight)
            ZStack(alignment: .topLeading) {
                header(for: stepStage, height: headerHeight)
                ScrollView {
                    stepContent(for: stepStage, isActive: isActive)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: max(1, proxy.size.width - AppSpacing.textInset * 2), height: contentHeight)
                .position(x: proxy.size.width / 2, y: headerHeight + contentHeight / 2)

                if showsPill {
                    earphoneHint
                        .position(x: proxy.size.width / 2, y: micCenter - diameter / 2 - AppSpacing.regular)
                        .transition(.opacity)
                }

                microphone(for: stepStage, isActive: isActive, diameter: diameter)
                    .position(x: proxy.size.width / 2, y: micCenter)

                VStack {
                    Spacer(minLength: 0)
                    action(for: stepStage, isActive: isActive).buttonStyle(.appPrimary)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.bottom, AppSpacing.medium)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsPill)
        }
    }

    private var earphoneHint: some View {
        Label("Connect earphones with a mic", systemImage: "headphones")
            .font(.appFootnote.weight(.semibold))
            .foregroundStyle(Color.primaryBrand)
            .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.tiny)
            .background(Color.primary100, in: Capsule())
    }

    private func header(for stepStage: Stage, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) { Image(systemName: "chevron.left") }
                .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                .padding(.horizontal, AppSpacing.regular)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title(for: stepStage)).font(.appLargeTitle).foregroundStyle(Color.primaryBrand)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle(for: stepStage)).font(.appBody)
                    .foregroundStyle(Color.primary300)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: subtitleWidth(for: stepStage), alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.textInset).padding(.top, AppSpacing.large)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: height)
        .background {
            if stepStage == .warmup {
                SpeechBubbleShape().fill(Color.primary100)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    @ViewBuilder private func stepContent(for stepStage: Stage, isActive: Bool) -> some View {
        let progress = isActive ? viewModel.holdProgress : 1.0
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if stepStage == .warmup {
                Text(passage(progress: progress)).font(.appTitle2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 294, alignment: .leading)
                    .accessibilityLabel(VocalRangeViewModel.speakingPassage)
                    .padding(.top, AppSpacing.medium)
            } else if stepStage == .hummingGuide {
                Text("“Hummmmmm…”").font(.appDisplay(size: 24)).foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.primary100, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                    .padding(.top, AppSpacing.spacious + AppSpacing.section)
            } else {
                VocalPitchMeter(midi: displayMIDI(for: stepStage, isActive: isActive),
                                referenceMIDI: viewModel.baselineMIDI ?? 57,
                                direction: stepStage == .lowest ? .lowest : .highest,
                                holdProgress: progress,
                                isCaptured: isCaptured(for: stepStage, isActive: isActive))
                    .id(stepStage)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppSpacing.spacious + AppSpacing.tiny)
            }
        }
        // Full width and leading, so the text lines up with the title (a scroll view centres
        // content narrower than itself).
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func microphone(for stepStage: Stage, isActive: Bool, diameter: CGFloat) -> some View {
        let isWarmup = stepStage == .warmup
        let isHumming = stepStage == .hummingGuide
        let progress = isActive ? viewModel.holdProgress : 1.0
        let listening = isActive && viewModel.status == .listening
        let hearsVoice = isActive && viewModel.liveMIDI != nil
        let showsMicIcon = isActive ? !viewModel.hasStartedListening : false
        let levels = isActive ? viewModel.waveformLevels : []
        return Button { viewModel.toggleMicrophone(practice: isHumming) } label: {
            VocalRangeRing(progress: progress,
                           isListening: listening,
                           hearsVoice: hearsVoice, label: "Microphone",
                           showsMicrophoneIcon: showsMicIcon,
                           levels: levels, diameter: diameter)
        }
        .buttonStyle(.plain).contentShape(Circle())
        .accessibilityLabel(listening ? "Stop microphone" : "Start microphone")
        .accessibilityHint(isWarmup ? "Tap and read the paragraph aloud" : "Tap and hold a comfortable note for 1 second")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private func passage(progress: Double) -> AttributedString {
        let source = VocalRangeViewModel.speakingPassage
        var text = AttributedString(source)
        text.foregroundColor = Color.passageUnread
        // Highlight only complete words. Time advances while the microphone hears speech (short pauses included).
        let words = source.split(whereSeparator: \.isWhitespace)
        let count = Int(Double(words.count) * progress)
        let readCount = words.prefix(count).last.map {
            source.distance(from: source.startIndex, to: $0.endIndex)
        } ?? 0
        let end = text.index(text.startIndex, offsetByCharacters: readCount)
        text[text.startIndex..<end].foregroundColor = .primary
        return text
    }

    @ViewBuilder private func action(for stepStage: Stage, isActive: Bool) -> some View {
        if isActive, case .failed = viewModel.status {
            Button("Try again") { viewModel.resetCapture() }
        } else {
            Button("Continue") {
                if stepStage == .warmup {
                    viewModel.next()
                    transition(to: .hummingGuide)
                    viewModel.listen(practice: true)
                } else if stepStage == .hummingGuide {
                    viewModel.resetCapture()
                    transition(to: .lowest)
                    viewModel.listen()
                } else if case .finished(let range) = viewModel.status {
                    completedRange = range
                    transition(to: .result)
                } else if stepStage == .lowest {
                    viewModel.next()
                    transition(to: .highest)
                    viewModel.listen()
                }
            }
            .disabled(!canContinue(for: stepStage, isActive: isActive))
        }
    }

    private func canContinue(for stepStage: Stage, isActive: Bool) -> Bool {
        guard isActive else { return true }
        if stepStage == .hummingGuide { return viewModel.hasPracticedHumming }
        if case .captured = viewModel.status { return true }
        if case .finished = viewModel.status { return true }
        return false
    }

    private func back() {
        viewModel.stopListening()
        switch stage {
        case .warmup:
            viewModel.restart()
            transition(to: .intro)
        case .hummingGuide:
            viewModel.restart()
            transition(to: .warmup)
        case .lowest:
            viewModel.resetCapture()
            transition(to: .hummingGuide)
            viewModel.listen(practice: true)
        case .highest:
            viewModel.previous()
            transition(to: .lowest)
            viewModel.listen()
        default:
            transition(to: .intro)
        }
    }

    private func backFromResult() {
        viewModel.redoHighest()
        if viewModel.lowestMIDI == nil {
            transition(to: .intro)
        } else {
            transition(to: .highest)
            viewModel.listen()
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

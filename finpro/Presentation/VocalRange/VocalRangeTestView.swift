//
//  VocalRangeTestView.swift
//  finpro
//

import SwiftUI

struct VocalRangeTestView: View {
    enum Stage: Int, Equatable, Comparable, CaseIterable, Identifiable {
        case intro = 0, warmup, lowest, highest, result
        var id: Int { rawValue }
        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    @State private var viewModel: VocalRangeViewModel
    @State private var stage: Stage = .intro
    @State private var stageDragProgress: CGFloat = 0
    @State private var hidesPreviousDuringPush = false
    /// Snapshot of the finished range so `VocalRangeResultView` keeps rendering while sliding out.
    @State private var completedRange: VocalRange?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let authorizeMicrophone: () async -> Bool
    let onWarmupAudioReady: () -> Void
    @State private var notifiedWarmupAudioReady = false
    @State private var isAuthorizingMicrophone = false
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
         onDismiss: (() -> Void)? = nil, onDismissRevealProgress: ((CGFloat) -> Void)? = nil,
         authorizeMicrophone: @escaping () async -> Bool = { true },
         onWarmupAudioReady: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.routeMonitor = routeMonitor
        self.authorizeMicrophone = authorizeMicrophone
        self.onWarmupAudioReady = onWarmupAudioReady
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
                let isVisible = isTop || (isImmediateUnderlay && (!hidesPreviousDuringPush || stageDragProgress > 0))
                stageLayer(for: layerStage, isTop: isTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .hierarchicalUnderlay(isCovered: !isTop, revealProgress: isImmediateUnderlay ? stageDragProgress : 0)
                    .opacity(isVisible ? 1 : 0)
                    .animation(nil, value: isVisible)
                    .zIndex(Double(layerStage.rawValue))
                    .transition(layerStage == .intro ? .identity : .move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground.ignoresSafeArea())
        .animation(stageTransitionAnimation, value: stage)
        .onDisappear { viewModel.stopListening() }
        .alert(failure?.title ?? "", isPresented: $showsFailure, presenting: failure) { _ in
            Button("Try Again") {
                viewModel.resetCapture()
                microphoneTapped(for: stage)
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
            if stage == .lowest || stage == .highest { startMicrophone(for: stage) }
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
            if phase == .background, viewModel.status == .listening {
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
                    onRetake: restartFromResult,
                    onBack: backFromResult,
                    isSwipeBackEnabled: isTop,
                    onSwipeProgress: { stageDragProgress = $0 }
                )
            }
        case .warmup:
            VocalWarmupView(isActive: isTop, onBack: back,
                            authorizeMicrophone: authorizeMicrophone,
                            monitorVoice: { duration, update in
                                try await viewModel.monitorWarmup(duration: duration, onFirstSample: {
                                    guard !notifiedWarmupAudioReady, stage == .warmup, scenePhase == .active else { return }
                                    notifiedWarmupAudioReady = true
                                    onWarmupAudioReady()
                                }, onProgress: update)
                            },
                            stopVoice: viewModel.stopListening,
                            voiceLevels: { viewModel.waveformLevels }) {
                viewModel.resetCapture()
                transition(to: .lowest)
            }
            .edgeSwipeBack(isEnabled: isTop && !showsEarphoneSetup, interactiveSlide: true,
                           onProgress: { stageDragProgress = $0 }, action: back)
        case .lowest, .highest:
            testStep(for: layerStage, isActive: isTop)
                .background(Color.screenBackground.ignoresSafeArea())
                .edgeSwipeBack(isEnabled: isTop && !isAuthorizingMicrophone && !showsFailure && !showsEarphoneSetup,
                               interactiveSlide: true,
                               onProgress: { stageDragProgress = $0 },
                               action: back)
        }
    }

    private func restartFromResult() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.restart()
            completedRange = nil
            hidesPreviousDuringPush = false
            stageDragProgress = 0
            stage = .intro
        }
    }

    private func transition(to target: Stage) {
        withAnimation(stageTransitionAnimation) {
            hidesPreviousDuringPush = target > stage
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

    private func testStep(for stepStage: Stage, isActive: Bool) -> some View {
        let isLowest = stepStage == .lowest
        let holdSeconds = Int(viewModel.holdDuration)
        let progress = isActive ? viewModel.holdProgress : 1.0
        return GeometryReader { proxy in
            let diameter = min(140, max(100, proxy.size.height * 0.19))
            let micCenter = proxy.size.height * 0.734
            let showsPill = showsEarphonePill(for: stepStage)
            let headerHeight = proxy.size.height * 0.304
            let contentHeight = max(40, micCenter - diameter / 2 - headerHeight - (showsPill ? 32 : 0))
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    VocalTestProgressHeader(step: isLowest ? 2 : 3, onBack: back)
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(isLowest ? "Let’s find your\nlowest note" : "Now, find your\nhighest note")
                            .font(.appLargeTitle)
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(isLowest
                             ? "Sing \"Do\" as low as comfortably possible and hold it for \(holdSeconds) seconds."
                             : "Sing \"Do\" as high as feels comfortable and hold it for \(holdSeconds) seconds.")
                            .font(.appBody)
                            .foregroundStyle(Color.plumNight)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 35)
                    .padding(.top, AppSpacing.large)
                }
                ScrollView {
                    VocalPitchMeter(midi: displayMIDI(for: stepStage, isActive: isActive),
                                    referenceMIDI: viewModel.lowestMIDI ?? 57,
                                    direction: isLowest ? .lowest : .highest,
                                    holdProgress: progress,
                                    isCaptured: isCaptured(for: stepStage, isActive: isActive))
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: proxy.size.width, height: contentHeight)
                .position(x: proxy.size.width / 2, y: headerHeight + contentHeight / 2)

                if showsPill {
                    earphoneHint
                        .position(x: proxy.size.width / 2, y: micCenter - diameter / 2 - AppSpacing.regular)
                }
                microphone(for: stepStage, isActive: isActive, diameter: diameter)
                    .position(x: proxy.size.width / 2, y: micCenter)

                VStack {
                    Spacer(minLength: 0)
                    action(for: stepStage, isActive: isActive).buttonStyle(.appPrimary)
                        .padding(.horizontal, 25)
                        .padding(.bottom, 20)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var earphoneHint: some View {
        Label("Connect earphones with a mic", systemImage: "headphones")
            .font(.appFootnote.weight(.semibold))
            .foregroundStyle(Color.primaryBrand)
            .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.tiny)
            .background(Color.primary100, in: Capsule())
    }

    private func microphone(for stepStage: Stage, isActive: Bool, diameter: CGFloat) -> some View {
        let progress = isActive ? viewModel.holdProgress : 1.0
        let listening = isActive && viewModel.status == .listening
        let hearsVoice = isActive && viewModel.liveMIDI != nil
        let showsMicIcon = isActive ? !viewModel.hasStartedListening : false
        let levels = isActive ? viewModel.waveformLevels : []
        return Button { microphoneTapped(for: stepStage) } label: {
            VocalRangeRing(progress: progress,
                           isListening: listening,
                           hearsVoice: hearsVoice, label: "Microphone",
                           showsMicrophoneIcon: showsMicIcon,
                           levels: levels, diameter: diameter)
        }
        .buttonStyle(.plain).contentShape(Circle())
        .disabled(isAuthorizingMicrophone)
        .accessibilityLabel(listening ? "Stop microphone" : "Start microphone")
        .accessibilityHint(listening ? "Hold a comfortable note for 1 second" : "Start listening again")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private func microphoneTapped(for stepStage: Stage) {
        guard !isAuthorizingMicrophone else { return }
        if viewModel.status == .listening {
            viewModel.resetCapture()
            return
        }
        startMicrophone(for: stepStage)
    }

    private func startMicrophone(for stepStage: Stage) {
        guard !isAuthorizingMicrophone else { return }
        isAuthorizingMicrophone = true
        Task {
            defer { isAuthorizingMicrophone = false }
            guard await authorizeMicrophone(), stage == stepStage, scenePhase != .background else { return }
            viewModel.listen()
        }
    }

    @ViewBuilder private func action(for stepStage: Stage, isActive: Bool) -> some View {
        if isActive, case .failed = viewModel.status {
            Button("Try again") { viewModel.resetCapture() }
        } else {
            Button("Continue") {
                if case .finished(let range) = viewModel.status {
                    completedRange = range
                    transition(to: .result)
                } else if stepStage == .lowest {
                    viewModel.next()
                    transition(to: .highest)
                }
            }
            .disabled(!canContinue(for: stepStage, isActive: isActive))
        }
    }

    private func canContinue(for stepStage: Stage, isActive: Bool) -> Bool {
        guard isActive else { return true }
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
        case .lowest:
            viewModel.restart()
            transition(to: .warmup)
        case .highest:
            viewModel.restart()
            transition(to: .lowest)
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
        }
    }
}

#if DEBUG
#Preview {
    VocalRangeTestView(viewModel: VocalRangeViewModel(
        source: FakeLivePitchSource(),
        repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {}))
}
#endif

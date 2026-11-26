//
//  VocalWarmupView.swift
//  finpro
//

import SwiftUI

struct VocalWarmupView: View {
    private enum Phase: Equatable { case idle, hum, rest, complete }
    private static let rounds = 5
    private static let phaseSeconds = 5
    private static let totalSeconds = (rounds * 2 - 1) * phaseSeconds

    let isActive: Bool
    let onBack: () -> Void
    let authorizeMicrophone: () async -> Bool
    let monitorVoice: (TimeInterval, (TimeInterval) -> Void) async throws -> Void
    let stopVoice: () -> Void
    let voiceLevels: () -> [Float]
    let onContinue: () -> Void

    @State private var phase: Phase = .idle
    @State private var round = 1
    @State private var seconds = phaseSeconds
    @State private var phaseStartedAt: ContinuousClock.Instant?
    @State private var humSeconds: TimeInterval = 0
    @State private var inputError: UserFacingError?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            VocalTestProgressHeader(step: 1, onBack: onBack)
            ViewThatFits(in: .vertical) {
                instructions
                ScrollView { instructions }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, AppSpacing.regular)
            Button("Continue", action: onContinue)
                .buttonStyle(.appPrimary)
                .disabled(phase != .complete)
                .padding(.horizontal, 25)
                .padding(.bottom, 16)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .onChange(of: isActive) { _, active in if !active { interrupt() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { interrupt() } }
        .onDisappear { interrupt() }
        .alert(inputError?.title ?? "", isPresented: Binding(
            get: { inputError != nil }, set: { if !$0 { inputError = nil } }
        ), presenting: inputError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var instructions: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 27) {
                Image("BrandMascot").resizable().scaledToFit()
                    .frame(width: 60, height: 60)
                    .background(Color.primaryButton, in: Circle())
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text("Let's warm up your voice first! Hum a gentle \"mmm\" for 5 seconds, then rest for 5 seconds. Just follow the 5 rounds below!")
                    .font(.appBody.weight(.semibold))
                    .foregroundStyle(phase == .complete ? Color.plumNight : Color.primary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.regularMaterial)
                                .frame(width: 18, height: 18)
                                .rotationEffect(.degrees(45))
                                .offset(x: -10, y: 25)
                            RoundedRectangle(cornerRadius: AppRadius.medium)
                                .fill(.regularMaterial)
                        }
                    }
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 3)
            }
            .padding(.leading, 16)
            .padding(.trailing, 46)
            Text("Round")
                .font(.appHeadline)
                .foregroundStyle(Color.plumNight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 44)
                .padding(.bottom, 8)
                .padding(.horizontal, 34)
            GeometryReader { proxy in
                let size = min(60, proxy.size.width / CGFloat(Self.rounds) - 4)
                HStack(spacing: 0) {
                    ForEach(1...Self.rounds, id: \.self) { number in
                        roundIndicator(number, size: size)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 31)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Round \(round) of \(Self.rounds)")
            .accessibilityValue("\(totalSecondsRemaining) seconds remaining")

            VStack(spacing: AppSpacing.tiny) {
                Text(phaseTitle).font(.appLargeTitle)
                    .foregroundStyle(.primary)
                    .opacity(phase == .idle ? 0 : 1)
                    .accessibilityHidden(phase == .idle)
                Text(phaseInstruction).font(.appBody)
                    .foregroundStyle(phase == .idle ? Color.plumNight : Color.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 80)
            .padding(.horizontal, AppSpacing.regular)

            Group {
                if phase == .idle {
                    Button(action: start) { microphoneIndicator }
                        .buttonStyle(.plain)
                        .disabled(session != nil)
                        .accessibilityLabel("Start warm-up microphone")
                } else {
                    microphoneIndicator.accessibilityHidden(true)
                }
            }
            .padding(.top, 26)
        }
        .foregroundStyle(Color.primaryBrand)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var microphoneIndicator: some View {
        ZStack {
            Circle().fill(Color.ringHalo)
            Circle().fill(phase == .complete ? Color.secBrand : Color.primaryButton).padding(13)
            Circle().strokeBorder(Color.ringStroke, lineWidth: 5).padding(13)
            if phase == .hum {
                progressArc(humProgress).padding(16)
            } else if phase == .rest {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { _ in
                    progressArc(restProgress).padding(16)
                }
            }
            if phase == .hum {
                ListeningWaveform(isActive: true, hearsVoice: true,
                                  barColor: .white, levels: voiceLevels())
                    .scaleEffect(0.9)
            } else {
                Image(systemName: phase == .rest ? "pause.fill" : phase == .complete ? "checkmark" : "mic.fill")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(phase == .complete ? Color.primary500 : .white)
            }
        }
        .frame(width: 140, height: 140)
    }

    private func roundIndicator(_ number: Int, size: CGFloat) -> some View {
        let complete = number < round || phase == .complete
        let active = number == round && (phase == .hum || phase == .rest)
        return TimelineView(.animation(minimumInterval: 1 / 24, paused: phase != .rest || !active || reduceMotion)) { _ in
            let phasesInRound = number == Self.rounds ? 1.0 : 2.0
            let progress = phase == .rest ? (1 + restProgress) / phasesInRound : humProgress / phasesInRound
            let scale = complete ? 1 : active ? 0.6 + 0.4 * progress : 0
            let innerSize = size * CGFloat(scale)
            ZStack {
                Circle().fill(Color.ringHalo.opacity(0.4))
                Circle().fill(Color.primary300).frame(width: innerSize, height: innerSize)
                Text("\(number)")
                    .font(.appHeadline)
                    .foregroundStyle(complete || active ? .white : Color.primaryBrand)
            }
            .frame(width: size, height: size)
        }
    }

    private var humProgress: Double { min(1, humSeconds / Double(Self.phaseSeconds)) }

    private var restProgress: Double {
        guard let phaseStartedAt else { return 0 }
        let elapsed = reduceMotion ? Double(Self.phaseSeconds - seconds) : phaseStartedAt.duration(to: .now) / .seconds(1)
        return min(1, max(0, elapsed / Double(Self.phaseSeconds)))
    }

    private func progressArc(_ progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(Color.secBrand, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var totalSecondsRemaining: Int {
        switch phase {
        case .idle: return Self.totalSeconds
        case .complete: return 0
        case .hum, .rest:
            let completedPhases = (round - 1) * 2 + (phase == .rest ? 1 : 0)
            let phaseRemaining = phase == .hum ? Self.phaseSeconds - Int(humSeconds) : seconds
            return Self.totalSeconds - (completedPhases + 1) * Self.phaseSeconds + phaseRemaining
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .idle: "HUM"
        case .hum: "“Hummm…”"
        case .rest: "Rest"
        case .complete: "Warm-up complete!"
        }
    }

    private var phaseInstruction: String {
        switch phase {
        case .idle: "Get ready to make a gentle 'mmm' sound."
        case .hum: "Hum a comfortable 'mmm' until the ring fills."
        case .rest: "Relax your voice before the next round."
        case .complete: "Great job! Your voice is ready for the next step."
        }
    }

    private func start() {
        guard phase == .idle, session == nil else { return }
        session = Task {
            defer { session = nil }
            guard await authorizeMicrophone(), !Task.isCancelled else { return }
            do {
                let clock = ContinuousClock()
                for number in 1...Self.rounds {
                    round = number
                    humSeconds = 0
                    phase = .hum
                    try await monitorVoice(Double(Self.phaseSeconds)) { humSeconds = $0 }
                    try Task.checkCancellation()
                    if number < Self.rounds {
                        seconds = Self.phaseSeconds
                        let restStart = clock.now
                        phaseStartedAt = restStart
                        phase = .rest
                        for elapsed in 1...Self.phaseSeconds {
                            try await clock.sleep(until: restStart + .seconds(elapsed))
                            seconds = Self.phaseSeconds - elapsed
                        }
                    }
                }
                phase = .complete
            } catch is CancellationError {
                // Navigation or backgrounding ended this exercise.
            } catch {
                interrupt()
                inputError = (error as? any UserFacingConvertible)?.userFacingError ?? .vocalRangeCaptureFailed
            }
        }
    }

    private func interrupt() {
        session?.cancel()
        if phase == .hum { stopVoice() }
        guard phase != .complete else { return }
        humSeconds = 0
        phaseStartedAt = nil
        phase = .idle
        round = 1
        seconds = Self.phaseSeconds
    }
}

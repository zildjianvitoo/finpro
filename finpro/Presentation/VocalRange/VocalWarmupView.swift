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
    let monitorVoice: () -> Void
    let stopVoice: () -> Void
    let voiceLevels: () -> [Float]
    let onContinue: () -> Void

    @State private var phase: Phase = .idle
    @State private var round = 1
    @State private var seconds = phaseSeconds
    @State private var phaseStartedAt: ContinuousClock.Instant?
    @State private var warmupStartedAt: ContinuousClock.Instant?
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
            .padding(.top, AppSpacing.medium)
            .padding(.horizontal, 24)
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
    }

    private var instructions: some View {
        VStack(spacing: AppSpacing.small) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                Image("BrandMascot").resizable().scaledToFit()
                    .frame(width: 60, height: 60)
                    .background(Color.primaryButton, in: Circle())
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text("Before we check your vocal range, let's give your voice a little warm-up! Hum a steady ‘mmm’ for 5 seconds, then rest before the next round. We'll do five rounds.")
                    .font(.appBody.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 3)
            }
            Text("\(totalSecondsRemaining)s")
                .font(.appHeadline)
                .monospacedDigit()
                .frame(width: 60, height: 60)
                .foregroundStyle(Color.plumNight)
                .background {
                    Circle().strokeBorder(Color.primary300, lineWidth: 1)
                    progressArc(start: warmupStartedAt, duration: Self.totalSeconds,
                                color: .primary500, lineWidth: 2, finished: phase == .complete)
                        .padding(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, AppSpacing.regular)
                .accessibilityLabel("Warm-up time remaining")
                .accessibilityValue("\(totalSecondsRemaining) seconds")
            Text("Round")
                .font(.appHeadline)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(1...Self.rounds, id: \.self) { number in
                    Text("\(number)")
                        .font(.appHeadline)
                        .frame(width: 45, height: 45)
                        .background {
                            if phase != .idle && number <= round { Circle().fill(Color.primary300) }
                        }
                        .foregroundStyle(phase != .idle && number <= round ? .white : Color.primaryBrand)
                        .frame(width: 60, height: 60)
                        .background(Color.ringHalo.opacity(0.4), in: Circle())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Round \(round) of \(Self.rounds)")

            VStack(spacing: AppSpacing.tiny) {
                Text(phaseTitle).font(.appLargeTitle)
                    .opacity(phase == .idle ? 0 : 1)
                    .accessibilityHidden(phase == .idle)
                Text(phaseInstruction).font(.appBody)
                    .foregroundStyle(Color.plumNight)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18)

            Button(action: start) {
                ZStack {
                    Circle().fill(Color.ringHalo)
                    Circle().fill(Color.primaryButton).padding(13)
                    Circle().strokeBorder(Color.ringStroke, lineWidth: 5).padding(13)
                    if phase == .hum {
                        progressArc(start: phaseStartedAt, duration: Self.phaseSeconds,
                                    color: .secBrand, lineWidth: 5)
                            .padding(16)
                        ListeningWaveform(isActive: true, hearsVoice: true,
                                          barColor: .white, levels: voiceLevels())
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: phase == .rest ? "pause.fill" : phase == .complete ? "checkmark" : "mic.fill")
                            .font(.system(size: 31, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 140, height: 140)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(phase == .idle && session == nil)
            .accessibilityHidden(phase != .idle)
            .accessibilityLabel("Start warm-up microphone")
            .padding(.top, 16)

            Text("\(seconds)s")
                .monospacedDigit()
                .foregroundStyle(Color.plumNight)
                .opacity(phase == .hum || phase == .rest ? 1 : 0)
                .accessibilityHidden(phase == .idle || phase == .complete)
        }
        .foregroundStyle(Color.primaryBrand)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func progressArc(start: ContinuousClock.Instant?, duration: Int,
                             color: Color, lineWidth: CGFloat, finished: Bool = false) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: start == nil || finished || reduceMotion)) { _ in
            let progress = start.map {
                min(1, max(0, ($0.duration(to: .now) / .seconds(duration))))
            } ?? 0
            Circle()
                .trim(from: 0, to: finished ? 1 : progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var totalSecondsRemaining: Int {
        switch phase {
        case .idle: return Self.totalSeconds
        case .complete: return 0
        case .hum, .rest:
            let completedPhases = (round - 1) * 2 + (phase == .rest ? 1 : 0)
            return Self.totalSeconds - (completedPhases + 1) * Self.phaseSeconds + seconds
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .idle, .hum: "HUM"
        case .rest: "REST"
        case .complete: "Warm-up complete!"
        }
    }

    private var phaseInstruction: String {
        switch phase {
        case .idle: "Follow the rhythm and keep your hum gentle."
        case .hum: "Hold a steady, comfortable ‘mmm’."
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
                var nextTick = clock.now
                warmupStartedAt = nextTick
                for number in 1...Self.rounds {
                    round = number
                    for nextPhase in number == Self.rounds ? [Phase.hum] : [.hum, .rest] {
                        phaseStartedAt = nextTick
                        phase = nextPhase
                        if nextPhase == .hum { monitorVoice() } else { stopVoice() }
                        for remaining in stride(from: Self.phaseSeconds, through: 1, by: -1) {
                            seconds = remaining
                            nextTick += .seconds(1)
                            try await clock.sleep(until: nextTick)
                            try Task.checkCancellation()
                        }
                    }
                }
                stopVoice()
                phase = .complete
            } catch {
                // Leaving or backgrounding the screen cancels this timed exercise.
            }
        }
    }

    private func interrupt() {
        session?.cancel()
        if phase == .hum { stopVoice() }
        guard phase != .complete else { return }
        warmupStartedAt = nil
        phaseStartedAt = nil
        phase = .idle
        round = 1
        seconds = Self.phaseSeconds
    }
}

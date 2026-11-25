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
    @State private var roundStartedAt: ContinuousClock.Instant?
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
                    .foregroundStyle(Color.plumNight)
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
                    .opacity(phase == .idle ? 0 : 1)
                    .accessibilityHidden(phase == .idle)
                Text(phaseInstruction).font(.appBody)
                    .foregroundStyle(Color.plumNight)
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
            if phase == .hum || phase == .rest {
                progressArc(start: phaseStartedAt, duration: Self.phaseSeconds,
                            color: .secBrand, lineWidth: 5)
                    .padding(16)
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
        return TimelineView(.animation(minimumInterval: 1 / 24, paused: !active || reduceMotion)) { _ in
            let duration = number == Self.rounds ? Self.phaseSeconds : Self.phaseSeconds * 2
            let progress = roundStartedAt.map {
                min(1, max(0, $0.duration(to: .now) / .seconds(duration)))
            } ?? 0
            let scale = complete ? 1 : active ? 0.6 + 0.4 * (reduceMotion ? 0.5 : progress) : 0
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

    private func progressArc(start: ContinuousClock.Instant?, duration: Int,
                             color: Color, lineWidth: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: start == nil || reduceMotion)) { _ in
            let progress = start.map {
                min(1, max(0, ($0.duration(to: .now) / .seconds(duration))))
            } ?? 0
            Circle()
                .trim(from: 0, to: progress)
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
        case .idle: "HUM"
        case .hum: "“Hummm…”"
        case .rest: "Rest"
        case .complete: "Warm-up complete!"
        }
    }

    private var phaseInstruction: String {
        switch phase {
        case .idle: "Get ready to make a gentle 'mmm' sound."
        case .hum: "Hold a steady, comfortable 'mmm'."
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
                for number in 1...Self.rounds {
                    round = number
                    roundStartedAt = nextTick
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
        roundStartedAt = nil
        phaseStartedAt = nil
        phase = .idle
        round = 1
        seconds = Self.phaseSeconds
    }
}

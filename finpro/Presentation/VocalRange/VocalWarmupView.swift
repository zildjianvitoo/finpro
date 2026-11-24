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
    let onContinue: () -> Void

    @State private var phase: Phase = .idle
    @State private var round = 1
    @State private var seconds = phaseSeconds
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
                .padding(.bottom, 20)
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
            Text("\(Self.totalSeconds)s")
                .font(.appHeadline)
                .frame(width: 60, height: 60)
                .background { Circle().strokeBorder(Color.primary300, lineWidth: 1) }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, AppSpacing.regular)
            Text("Round")
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                ForEach(1...Self.rounds, id: \.self) { number in
                    Text("\(number)")
                        .font(.appHeadline)
                        .frame(width: 54, height: 54)
                        .background(phase != .idle && number <= round ? Color.primaryButton : Color.primary100, in: Circle())
                        .foregroundStyle(phase != .idle && number <= round ? .white : Color.primaryBrand)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Round \(round) of \(Self.rounds)")

            VStack(spacing: AppSpacing.tiny) {
                Text(phaseTitle).font(.appLargeTitle)
                    .opacity(phase == .idle ? 0 : 1)
                    .accessibilityHidden(phase == .idle)
                Text(phaseInstruction).font(.appSubheadline)
                    .multilineTextAlignment(.center)
            }

            Button(action: start) {
                VocalRangeRing(progress: phase == .complete ? 1 : 1 - Double(seconds) / Double(Self.phaseSeconds),
                               isListening: phase == .hum, hearsVoice: false, label: "Microphone",
                               showsMicrophoneIcon: phase == .idle, levels: [], diameter: 140)
                    .overlay {
                        if phase == .rest { Image(systemName: "pause.fill").font(.appLargeTitle) }
                        if phase == .complete { Image(systemName: "checkmark").font(.appLargeTitle) }
                    }
            }
            .buttonStyle(.plain)
            .disabled(phase != .idle || session != nil)
            .accessibilityLabel("Start warm-up microphone")

            Text("\(seconds)s")
                .monospacedDigit()
                .opacity(phase == .hum || phase == .rest ? 1 : 0)
                .accessibilityHidden(phase == .idle || phase == .complete)
        }
        .foregroundStyle(Color.primaryBrand)
        .fixedSize(horizontal: false, vertical: true)
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
                for number in 1...Self.rounds {
                    round = number
                    for nextPhase in number == Self.rounds ? [Phase.hum] : [.hum, .rest] {
                        phase = nextPhase
                        for remaining in stride(from: Self.phaseSeconds, through: 1, by: -1) {
                            seconds = remaining
                            nextTick += .seconds(1)
                            try await clock.sleep(until: nextTick)
                            try Task.checkCancellation()
                        }
                    }
                }
                phase = .complete
            } catch {
                // Leaving or backgrounding the screen cancels this timed exercise.
            }
        }
    }

    private func interrupt() {
        session?.cancel()
        guard phase != .complete else { return }
        phase = .idle
        round = 1
        seconds = Self.phaseSeconds
    }
}

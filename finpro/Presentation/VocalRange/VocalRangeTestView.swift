//
//  VocalRangeTestView.swift
//  finpro
//
//  Speaking baseline and two comfortable limits, each confirmed by a stable hold (PRD §5.1).
//  An intro screen first, then one ring screen per prompt.
//

import SwiftUI

struct VocalRangeTestView: View {
    @State private var viewModel: VocalRangeViewModel
    @State private var showsIntro = true
    @State private var showsHelp = false

    init(viewModel: VocalRangeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if showsIntro {
                VocalRangeIntroView { showsIntro = false }
                    .transition(.opacity)
            } else {
                testScreen
                    .transition(.opacity)
            }
        }
        .animation(.default, value: showsIntro)
        .onDisappear { viewModel.stopListening() }
        .sheet(isPresented: $showsHelp) { help }
    }

    // MARK: - Test screen

    private var testScreen: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(title: "Back", systemImage: "arrow.left") {
                viewModel.restart()
                showsIntro = true
            }
            Spacer()
            microphoneLabel
            Spacer()
            CircleIconButton(title: "How the test works", systemImage: "questionmark") {
                showsHelp = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var microphoneLabel: some View {
        if let microphone = viewModel.microphoneName {
            Label(microphone, systemImage: "headphones")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(viewModel.prompt == .speaking && !isFinished ? .body : .subheadline)
                .foregroundStyle(viewModel.prompt == .speaking && !isFinished ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let error) = viewModel.status {
            ErrorStateView(error: error)
                .frame(minHeight: 320)
        } else {
            VocalRangeRing(progress: viewModel.holdProgress,
                           isListening: viewModel.status == .listening,
                           hearsVoice: viewModel.liveMIDI != nil,
                           label: ringLabel,
                           emphasizesLabel: emphasizesRingLabel)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let tip {
                TipCard(title: tip.title, message: tip.message, systemImage: tip.systemImage)
                    .padding(.bottom, 8)
            }
            actions
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var actions: some View {
        switch viewModel.status {
        case .idle:
            Button("Start") { viewModel.listen() }
                .buttonStyle(.primaryWithDot)
        case .listening:
            Button(viewModel.prompt == .speaking ? "Keep reading…" : "Listening…") {}
                .buttonStyle(.primary)
                .disabled(true)
        case .captured:
            Button("Continue") { viewModel.next() }
                .buttonStyle(.primary)
            secondaryButton("Retry") { viewModel.listen() }
        case .finished:
            Button("Save and Continue") { viewModel.save() }
                .buttonStyle(.primary)
            secondaryButton("Start Over") { viewModel.restart() }
        case .failed:
            Button("Retry") { viewModel.listen() }
                .buttonStyle(.primaryWithDot)
            secondaryButton("Start Over") { viewModel.restart() }
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.brandPlum)
            .frame(minHeight: 44)
    }

    // MARK: - Copy per state

    private var isFinished: Bool {
        if case .finished = viewModel.status { true } else { false }
    }

    private var heading: String {
        isFinished ? "Your vocal range" : viewModel.title
    }

    private var subtitle: String {
        isFinished ? "We'll use it to pick song keys that fit your voice." : viewModel.instructions
    }

    private var ringLabel: String {
        switch viewModel.status {
        case .idle:
            "Tap Start when you're ready"
        case .listening:
            viewModel.liveNoteName ?? (viewModel.prompt == .speaking ? "Listening…" : "Hmm…")
        case .captured(let note):
            name(note)
        case .finished(let range):
            "\(name(range.lowestMIDI)) – \(name(range.highestMIDI))"
        case .failed:
            ""
        }
    }

    private var emphasizesRingLabel: Bool {
        switch viewModel.status {
        case .captured, .finished: true
        case .listening: viewModel.liveNoteName != nil
        case .idle, .failed: false
        }
    }

    private var tip: (title: String, message: String, systemImage: String)? {
        switch viewModel.status {
        case .finished, .failed:
            return nil
        case .idle, .listening, .captured:
            switch viewModel.prompt {
            case .speaking:
                return ("Speak naturally", "Read at your usual pace until the ring fills.", "text.quote")
            case .lowest:
                return ("Keep your voice steady", "Try to hold the same tone until the ring fills.", "waveform")
            case .highest:
                return ("Keep it comfortable", "Don't shout or strain. Hold the note until the ring fills.", "waveform")
            }
        }
    }

    private func name(_ midi: Float) -> String {
        PitchMath.noteName(midi: Int(midi.rounded()))
    }

    // MARK: - Help

    private var help: some View {
        NavigationStack {
            List {
                Section("Three short steps") {
                    Label("Read a short passage in your normal speaking voice.", systemImage: "1.circle")
                    Label("Hum your lowest comfortable note and hold it.", systemImage: "2.circle")
                    Label("Sing your highest comfortable note and hold it.", systemImage: "3.circle")
                }
                Section {
                    Label("Connect a headset with a microphone. The test listens through the headset.",
                          systemImage: "headphones")
                    Label("The ring fills while your note stays steady. When it's full, the note is saved.",
                          systemImage: "circle.dashed")
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
    VocalRangeTestView(viewModel: VocalRangeViewModel(
        source: FakeLivePitchSource(notes: [57, 48, 67]), repository: FakeVocalRangeRepository(),
        configuration: .default, onSaved: {}))
}
#endif

//
//  ImportSongView.swift
//  finpro
//
//  Import screen (PRD §5.2): add a song from Files, drag a 15–60 s part on the waveform while
//  the synced lyrics of that part light up (and follow a preview), then watch it being prepared.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportSongView: View {
    @State private var viewModel: ImportSongViewModel
    @State private var picking = false
    let onBack: () -> Void
    let onUseDemo: () -> Void

    init(viewModel: ImportSongViewModel, onBack: @escaping () -> Void, onUseDemo: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onBack = onBack
        self.onUseDemo = onUseDemo
    }

    /// PRD §5.2: mp3, m4a, wav, and the audio track of a video.
    private static let types: [UTType] = [.mp3, .mpeg4Audio, .wav, .audio, .movie]

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Inset of the text and cards per the design.
    private let contentInset: CGFloat = 48
    private let topBarHeight: CGFloat = 48
    private let cornerRadius: CGFloat = 18

    var body: some View {
        Group {
            switch viewModel.status {
            case .idle:
                addSong
            case .loading:
                screen(onBack: onBack) {
                    ProgressView("Opening song…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } footer: { EmptyView() }
            case .trimming(let audio):
                trimmer(audio)
            case .preparing, .prepared:
                preparing
            case .failed(let error):
                screen(onBack: onBack) {
                    ErrorStateView(error: error, actionTitle: "Choose Another Song") {
                        viewModel.reset()
                        picking = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } footer: { EmptyView() }
            }
        }
        .background(Color.onboardingBackground.ignoresSafeArea())
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { viewModel.picked($0) }
        .onDisappear { viewModel.cancelPreparation() }
    }

    // MARK: - Shared frame

    private func screen<Content: View, Footer: View>(
        onBack: @escaping () -> Void,
        backIcon: String = "chevron.left",
        backLabel: String = "Back",
        title: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.plumInk)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack {
                    LiquidGlassGroup {
                        Button(action: onBack) {
                            Image(systemName: backIcon)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        .glassCircleButtonStyle()
                        .accessibilityLabel(backLabel)
                    }
                    Spacer()
                }
            }
            .frame(minHeight: topBarHeight)
            .padding(.horizontal, buttonInset)

            content()

            footer()
                .padding(.horizontal, buttonInset)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Add a song

    private var addSong: some View {
        screen(onBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add a song")
                            .font(.title.bold())
                            .foregroundStyle(Color.plumInk)
                            .accessibilityAddTraits(.isHeader)
                        Text("Import the song you want to cover and get ready to record.")
                            .font(.subheadline)
                            .foregroundStyle(Color.plumInkSecondary)
                    }
                    .padding(.top, 8)

                    importCard
                        .padding(.top, 20)

                    beforeYouImportCard
                        .padding(.top, 28)

                    Button("Try with the demo song", action: onUseDemo)
                        .font(.footnote)
                        .foregroundStyle(Color.plumInkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 8)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, contentInset)
            }
            .scrollBounceBehavior(.basedOnSize)
        } footer: {
            // The song moves on to trimming as soon as it is picked; this stays as the design's
            // anchor and explains why it is inactive.
            Button("Continue") {}
                .buttonStyle(.primaryDeep)
                .disabled(true)
                .accessibilityHint("Choose a song first")
        }
    }

    private var importCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 70)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.tileMauve))
                .accessibilityHidden(true)

            Text("Import your audio")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.plumInk)
                .padding(.top, 12)

            Text("Choose an audio from your device.")
                .font(.footnote)
                .foregroundStyle(Color.plumInkSecondary)
                .padding(.top, 6)

            Button {
                picking = true
            } label: {
                Label("Browse Files", systemImage: "square.and.arrow.down")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Color.plumNight))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Text("Supported format: MP3, M4A, WAV")
                .font(.caption2)
                .foregroundStyle(Color.plumInkSecondary)
                .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.importCard))
    }

    private var beforeYouImportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Before you import")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.plumInk)
            } icon: {
                Image(systemName: "info")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.plumInk)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white))
            }

            Text("Choose an audio file that includes both the original vocals and instrumental. This app uses the original vocal as a pitch reference while you sing.")
                .font(.caption2)
                .foregroundStyle(Color.plumInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.voiceCardSelected))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Trimmer

    private func trimmer(_ audio: ImportedAudio) -> some View {
        screen(onBack: {
            viewModel.reset()
        }, backIcon: "xmark", backLabel: "Choose another song") {
            VStack(spacing: 0) {
                Text(audio.name)
                    .font(.footnote)
                    .foregroundStyle(Color.plumInk)
                    .lineLimit(1)
                    .padding(.horizontal, contentInset)

                LyricsPanel(viewModel: viewModel)
                    .padding(.horizontal, buttonInset)
                    .padding(.vertical, 24)

                VStack(spacing: 8) {
                    TrimmerWaveform(viewModel: viewModel, audio: audio)
                        .frame(height: 77)

                    HStack {
                        Text(time(viewModel.selectionStart))
                        Spacer()
                        Button {
                            viewModel.toggleSelectionPreview()
                        } label: {
                            Label("\(lengthText(viewModel.selectionLength)) selected",
                                  systemImage: isPreviewing ? "stop.fill" : "play.fill")
                                .font(.caption2.weight(.semibold))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPreviewing ? "Stop preview" : "Play selected part")
                        .accessibilityValue("\(lengthText(viewModel.selectionLength)) selected")
                        Spacer()
                        Text(time(viewModel.selectionStart + viewModel.selectionLength))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.plumInk)
                    .monospacedDigit()
                }
                .padding(.horizontal, buttonInset + 9)
                .padding(.bottom, 32)
            }
        } footer: {
            Button("Continue") { viewModel.prepareSelection() }
                .buttonStyle(.primaryDeep)
        }
    }

    // MARK: - Preparing

    private var preparing: some View {
        let progress = viewModel.preparationProgress
            ?? .init(fraction: 0, vocals: .processing, instrumental: .processing)
        let isComplete = progress.isComplete

        return screen(onBack: viewModel.backToTrimming, title: "Preparing your song") {
            ScrollView {
                VStack(spacing: 0) {
                    preparingIcon(isComplete: isComplete)
                        .padding(.top, 30)

                    Text(isComplete ? "Your audio is ready!" : "Separating your audio")
                        .font(.headline)
                        .foregroundStyle(Color.plumInk)
                        .padding(.top, 24)

                    Text(isComplete
                         ? "Your vocals and instrumental have been separated successfully."
                         : "We’re separating the original vocals from the instrumental so you can use them as your recording reference.")
                        .font(.caption2)
                        .foregroundStyle(Color.plumInkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)

                    progressSection(progress)
                        .padding(.top, 24)

                    Divider()
                        .padding(.top, 20)

                    stemList(progress)
                        .padding(.top, 16)

                    Text("The singer is removed on your iPhone, so some original vocals may still be audible. The pitch guide comes from the original song and may be inaccurate in busy sections.")
                        .font(.caption2)
                        .foregroundStyle(Color.plumInkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 34)
                .animation(.easeInOut(duration: 0.3), value: progress)
            }
            .scrollBounceBehavior(.basedOnSize)
        } footer: {
            if isComplete {
                Button("Continue", action: viewModel.continueWithPreparedSong)
                    .buttonStyle(.primaryDeep)
            } else {
                Text("You can continue once your audio is ready.")
                    .font(.caption2)
                    .foregroundStyle(Color.plumInkSecondary)
                    .frame(minHeight: 56)
            }
        }
    }

    private func preparingIcon(isComplete: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isComplete ? Color.ringDisc : Color.surfaceLavender)
            Image(systemName: isComplete ? "checkmark" : "waveform")
                .font(.system(size: isComplete ? 48 : 52, weight: isComplete ? .medium : .semibold))
                .foregroundStyle(isComplete ? Color.white : Color.plumNight)
                .symbolEffect(.variableColor.iterative, isActive: !isComplete)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 120, height: 120)
        .accessibilityHidden(true)
    }

    private func progressSection(_ progress: ImportSongViewModel.PreparationProgress) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(progress.isComplete ? "Processing audio is completed" : "Processing audio…")
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(Color.plumInk)

            ProgressView(value: progress.fraction)
                .tint(Color.tileMauve)
                .accessibilityLabel("Preparing your song")
        }
    }

    private func stemList(_ progress: ImportSongViewModel.PreparationProgress) -> some View {
        VStack(spacing: 0) {
            stemRow("Original vocals", state: progress.vocals)
            Divider().padding(.horizontal, 16)
            stemRow("Instrumental", state: progress.instrumental)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surfaceElevated)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.chipBorder.opacity(0.3), lineWidth: 1)
        )
    }

    private func stemRow(_ name: String, state: ImportSongViewModel.PreparationProgress.StemState) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.plumInk)
                if state != .done {
                    Text("Being separated")
                        .font(.caption2)
                        .foregroundStyle(Color.plumInkSecondary)
                }
            }
            Spacer()
            Text(stateLabel(state))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: 26)
                .background(Capsule().fill(state == .waiting ? Color.badgeBackground.opacity(0.45) : Color.badgeBackground))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func stateLabel(_ state: ImportSongViewModel.PreparationProgress.StemState) -> String {
        switch state {
        case .waiting: "Waiting"
        case .processing: "Processing"
        case .done: "Done"
        }
    }

    /// From `playbackTime`, which views observe (the preview task itself is not observed).
    private var isPreviewing: Bool { viewModel.playbackTime != nil }

    // MARK: - Formatting

    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    /// "42s" or "1m 02s", as in the design.
    private func lengthText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)m \(String(format: "%02d", total % 60))s" : "\(total)s"
    }
}

/// Title first, icon after it ("Browse Files ⤓").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// Whole-song waveform with a draggable selection window, like the trimmers in social apps:
/// drag the window to move it, drag a handle to change the length (15–60 s).
private struct TrimmerWaveform: View {
    @Bindable var viewModel: ImportSongViewModel
    let audio: ImportedAudio

    private let handleWidth: CGFloat = 10
    private let cornerRadius: CGFloat = 10
    private let barCount = 60

    @State private var dragOrigin: (start: TimeInterval, length: TimeInterval)?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let x0 = x(for: viewModel.selectionStart, width: width)
            let x1 = x(for: viewModel.selectionStart + viewModel.selectionLength, width: width)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.trimmerTrack)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.trimmerSelection)
                    .frame(width: max(0, x1 - x0), height: height)
                    .offset(x: x0)
                    .gesture(moveGesture(width: width))

                bars(width: width, height: height)
                    .allowsHitTesting(false)

                handle(height: height)
                    .offset(x: x0 + 2)
                    .gesture(resizeGesture(width: width, leading: true))
                handle(height: height)
                    .offset(x: x1 - handleWidth - 2)
                    .gesture(resizeGesture(width: width, leading: false))

                if let playhead = viewModel.playbackTime {
                    Rectangle()
                        .fill(Color.plumNight)
                        .frame(width: 1.5, height: height)
                        .offset(x: x(for: playhead, width: width))
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Selected part")
        .accessibilityValue("\(Int(viewModel.selectionLength)) seconds starting at \(Int(viewModel.selectionStart)) seconds")
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 1
            viewModel.selectionStart += direction == .increment ? step : -step
        }
    }

    private func bars(width: CGFloat, height: CGFloat) -> some View {
        let levels = resampled()
        let spacing = width / CGFloat(levels.count)
        return HStack(spacing: 0) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 3, height: max(4, CGFloat(levels[index]) * height * 0.7))
                    .frame(width: spacing)
            }
        }
        .frame(width: width, height: height)
    }

    private func handle(height: CGFloat) -> some View {
        Capsule()
            .fill(Color.plumNight)
            .overlay(Capsule().fill(.white.opacity(0.8)).frame(width: 2, height: height * 0.35))
            .frame(width: handleWidth, height: height * 0.7)
            .frame(height: height)
            // Wider than drawn so the handle is easy to grab.
            .contentShape(Rectangle().inset(by: -12))
    }

    private func moveGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = dragOrigin ?? (viewModel.selectionStart, viewModel.selectionLength)
                dragOrigin = origin
                viewModel.selectionStart = origin.start + seconds(for: value.translation.width, width: width)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func resizeGesture(width: CGFloat, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin = dragOrigin ?? (viewModel.selectionStart, viewModel.selectionLength)
                dragOrigin = origin
                let delta = seconds(for: value.translation.width, width: width)
                if leading {
                    let end = origin.start + origin.length
                    let start = min(max(0, origin.start + delta), end - ImportSongViewModel.minimumLength)
                    viewModel.selectionStart = start
                    viewModel.selectionLength = end - start
                } else {
                    viewModel.selectionLength = origin.length + delta
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard audio.duration > 0 else { return 0 }
        return width * CGFloat(time / audio.duration)
    }

    private func seconds(for distance: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return TimeInterval(distance / width) * audio.duration
    }

    /// The waveform reduced to the number of bars drawn (peak per group).
    private func resampled() -> [Float] {
        let source = audio.waveform
        guard !source.isEmpty else { return Array(repeating: 0.2, count: barCount) }
        return (0..<barCount).map { index in
            let lower = index * source.count / barCount
            let upper = max(lower + 1, (index + 1) * source.count / barCount)
            return source[lower..<min(upper, source.count)].max() ?? 0
        }
    }
}

/// Synced lyrics, centered: lines in the chosen part are dark, the rest dimmed; during the preview
/// the current line is bold. Manual search when none match.
private struct LyricsPanel: View {
    @Bindable var viewModel: ImportSongViewModel

    var body: some View {
        Group {
            switch viewModel.lyrics {
            case .idle:
                Color.clear
            case .loading:
                ProgressView("Finding lyrics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .found(let song):
                lines(song)
            case .notFound:
                search(.lyricsNotFound)
            case .failed(let error):
                search(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Lines shown at once, as in the design.
    private static let visibleLineCount = 6
    /// Position of the highlighted line within the visible lines (the third).
    private static let highlightedPosition = 2

    /// The line to highlight: the one being sung during the preview, else the first line of
    /// the chosen part.
    private func highlightedID(in song: SongLyrics) -> Int? {
        viewModel.activeLineID ?? viewModel.firstSelectedLineID ?? song.lines.first?.id
    }

    /// Six lines with the highlighted one third, shifted at the start and end of the song.
    private func visibleLines(_ song: SongLyrics) -> ArraySlice<LyricLine> {
        let count = min(Self.visibleLineCount, song.lines.count)
        let highlighted = song.lines.firstIndex { $0.id == highlightedID(in: song) } ?? 0
        let start = min(max(0, highlighted - Self.highlightedPosition), song.lines.count - count)
        return song.lines[start..<(start + count)]
    }

    private func lines(_ song: SongLyrics) -> some View {
        let highlighted = highlightedID(in: song)
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(visibleLines(song)) { line in
                    lineText(line, isHighlighted: line.id == highlighted)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: highlighted)
            .padding(.top, 8)
            Spacer(minLength: 16)
            Text(source(of: song))
                .font(.caption2)
                .foregroundStyle(Color.plumInkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func source(of song: SongLyrics) -> String {
        #if DEBUG
        if song.matchedTitle == DummyLyricsProvider.placeholderTitle {
            return "Placeholder lyrics (debug build). No synced lyrics were found for this song."
        }
        #endif
        return "Lyrics: \(song.matchedTitle) – \(song.matchedArtist), from LRCLIB. Timing may be slightly off."
    }

    private func lineText(_ line: LyricLine, isHighlighted: Bool) -> some View {
        Text(line.text)
            .font(.body.weight(isHighlighted ? .bold : .semibold))
            .foregroundStyle(isHighlighted ? Color.plumInk : Color(.tertiaryLabel))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func search(_ error: UserFacingError) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.title, systemImage: error.systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.plumInk)
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(Color.plumInkSecondary)
                TextField("Song title", text: $viewModel.lyricsTitle)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { viewModel.searchLyrics() }
                TextField("Artist (optional)", text: $viewModel.lyricsArtist)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { viewModel.searchLyrics() }
                Button("Search Lyrics") { viewModel.searchLyrics() }
                    .buttonStyle(.bordered)
                    .tint(Color.plumInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }
}

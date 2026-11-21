# Optimizations

This document records measured optimizations made to `finpro`'s audio preparation pipeline, pitch guide, lyrics alignment, and cover preview.

- **2026-11-20:** Lyric guide timing, recognized-word anchoring, scoring thresholds, and cover preview.
- **2026-11-21:** Song preparation speed (HTDemucs, CREPE, stage parallelism, song-level chunk cache, trimmer pre-separation) and 120 s guide-note overlap fix.

---

# 2026-11-20 — Lyric guide timing and scoring

This note records every optimization made on 2026-11-20 to the pitch guide's notes, the lyrics under the guide, and the cover preview. It also gives the measured effect of each one.

All numbers come from three songs prepared with the real pipeline on the simulator: A Whole New World, Best Part and Abadi. The pipeline is HTDemucs separation, CREPE notes and synced lyrics. Each song was measured over its first 120 s.

## Summary

| Area | Before | After |
|---|---|---|
| Word start error, full 120 s songs (median) | 0.72 s | **0.19 s** |
| Word start error, 30 s clips (median / mean) | 0.72 s / 0.86 s | **0.22 s / 0.43 s** |
| Word start error, 15 s clips (median / mean) | 0.72 s / 0.80 s | **0.24 s / 0.46 s** |
| Words within 0.3 s of where they are sung (30 s clips) | 23% | **63%** |
| Lines the original vocal passes (pass threshold 0.75 → 0.30) | 4–30% | **96–100%** |
| Flat, one-pitch singing that passes | — | **8%** |
| Words within 0.3 s, with on-device word recognition (AWNW / Best Part, iOS 26+) | 65% / 73% | **77% / 86%** |
| Words more than 1 s off, with word recognition (AWNW / Best Part) | 3% / 7% | **0% / 2%** |
| Pitch guide rows on the cover preview | 4 (sometimes) | **at least 6** |
| Lyrics on the cover preview's pitch guide | none | **lyric line + word labels** |

## 1. How it was measured

**Data.** For each song, a temporary Debug-only tool dumped the inputs and outputs of preparation as JSON, together with the separated vocal stem. The dump held the lyric lines with their word weights, the CREPE pitch notes, and the word timing the guide produced. The tools were `GuideWordsDump` and an `-autoPrepare` launch argument, and both were removed before committing.

**Reference.** WhisperKit (`whisperkit-cli`, large-v3) was run on the same vocal stem, with word timestamps. Because it is the same stem, the reference shares the app's timeline exactly.

**Metric.** Our lyric words are aligned to Whisper's words by text. The metric is the error of each matched word's start time: the median, the mean, and the share within 0.3 s.

**Floor.** Placing each word on the CREPE note onset nearest to Whisper gives a median error of 0.11–0.13 s with no bias. No method built on CREPE notes can do better than that.

**Checking the reference.** Whisper's word starts were compared with loudness onsets of the stem. The difference was 0.03–0.14 s, so the reference has no meaningful bias.

**Short clips.** The app's selections are 15–60 s long. To test them, the full-song dumps were cut into sliding windows: 686 words in 30 s windows and 672 words in 15 s windows.

**Porting.** Each candidate method was first written in Python and grid-searched. The chosen one was then ported to Swift. The Swift port matches the Python on every dump to 0.0 s.

## 2. Word timing in `LyricGuideNotesUseCase`

### Problem

The device report said the note for "follow" in "Where you go, I'll follow…" ran long, and the words after it lagged. Measurement found two causes.

**1. Synced-lyric line times don't match the recording.** The line timestamps come from another release of the song, and each song is off by its own steady amount:

| Song | Line times vs. the vocal (median) |
|---|---|
| A Whole New World | ~1.0 s late |
| Best Part | ~0.8 s early |
| Abadi | ~0.4 s early |

Words were never placed before their line's timestamp, so every word inherited this error. AWNW was 1.21 s late on average. The reported Best Part line started 0.8 s early, so it ate the end of the previous line.

**2. Words were spread evenly by syllable count over the voiced time.** This caused two problems:
- A held note was counted as many syllables, so the words before it ran late.
- CREPE misses soft syllables, and words were only placed where it heard voice, so they bunched up in the voiced parts that came later.

### Change

**Line shift.** All lines of a selection are shifted by one amount. The search looks for the amount that puts each line start where the vocal guide goes from silent (0.5 s before) to voiced (0.5 s after).
- The search runs over ±1.5 s, in 0.05 s steps.
- The result is then moved 0.35 s earlier, because CREPE's first note comes after the consonant or soft attack.
- At least 2 lines are needed.
- A range of ±3 s, or matching on phrase onsets, let short clips jump to the neighbouring phrase.

**Spreading words in a line.** Words are spread by syllable weight from the line start to its last voiced moment. Each voiced part counts at most 0.2 s, and each silent part at most 0.5 s.

**Lyric line text.** The line text under the guide is moved by the same shift, so it changes when the line is actually sung.

Chosen parameters, all on a flat optimum where neighbouring values are within ±0.02 s:

| Constant | Value |
|---|---|
| `lineShiftRange` | 1.5 s |
| `lineShiftStep` | 0.05 s |
| `lineStartWindow` | 0.5 s |
| `attackLead` | 0.35 s |
| `minimumLinesForShift` | 2 |
| `heldNoteShare` | 0.2 s |
| `silenceShare` | 0.5 s |

### Result

Word start error per song, over the full 120 s:

| Song | Words matched | Before (median) | After (median) |
|---|---|---|---|
| A Whole New World | 100 | 1.14 s | 0.22 s |
| Best Part | 131 | 0.42 s | 0.16 s |
| Abadi | 54 | 0.46 s | 0.26 s |
| **All** | 285 | **0.72 s** | **0.19 s** |

Line shift found per song: AWNW −1.10 s, Best Part +0.70 s, Abadi +0.25 s. These match the measured offsets.

Short clips, which is how the app is used:

| Clip length | Words | Before (median / mean / ≤0.3 s) | After (median / mean / ≤0.3 s) |
|---|---|---|---|
| 30 s | 686 | 0.72 s / 0.86 s / 23% | 0.22 s / 0.43 s / 63% |
| 15 s | 672 | 0.72 s / 0.80 s / 23% | 0.24 s / 0.46 s / 58% |

A real 30 s Best Part selection, prepared in the simulator (60–90 s): median 0.73 s before, 0.45 s after.

The reported line, against Whisper:

| | "Where" starts | "Where" length |
|---|---|---|
| Reference (Whisper) | 66.08 s | — |
| Before | 65.30 s | 1.67 s |
| After | 66.10 s | 0.65 s |

### Approaches tried and dropped

| Approach | All-songs median | Why dropped |
|---|---|---|
| Cap held notes only, no line shift | 1.11–1.21 s (AWNW) | Line offset dominates |
| Shift by phrase onsets, ±3 s, snap per line | 0.34–0.48 s | Late bias; snapping added nothing |
| Words snapped to note onsets (DP) | 0.37 s | No better than the simpler spread |
| Notes grouped per word by syllable count (DP) | 0.39 s | CREPE fragments and misses syllables |
| Loudness envelope for voice activity | 0.26 s | Worse than CREPE-based; would also need a repository contract change |
| Shift search over ±3 s | 30 s clips mean 0.65 s | Short clips jump a phrase (e.g. −2.4 s instead of −0.7 s) |

## 2b. Recognized words as anchors (iOS 26+, English and other supported languages)

### Why

Notes alone can't tell a run of decoration on one syllable from separate syllables, so lines that end in a long ad-lib drifted late. One example is "If life is a movie, then you're the best part, oh", where "best" was 2.6 s late. Recognizing the sung words in the original vocal stem tells *which* word is sung when.

### What was measured first (Mac, same stems, Whisper as reference)

| Recognizer | Lyric words recognized | Timing of recognized words |
|---|---|---|
| `SFSpeechRecognizer` (iOS 18 API) | ~15%, many misheard | 0.5–1.4 s off, worse than the pitch-based method |
| **`SpeechTranscriber`** (iOS 26+) | **61–78%** | median 0.16–0.18 s, 2 min of audio in under 1 s |

`SpeechTranscriber` has no Indonesian model, and neither has the older API on device. Indonesian songs such as Abadi keep the pitch-based method.

### Change

- New contract, approved by the user:
  - `RecognizedWord` (entity)
  - `SungWordRecognitionRepository` (repository): it returns an empty list instead of throwing, so preparation never fails because of it.
- `SpeechTranscriberWordRecognition` (Data):
  - picks the language from the lyrics (`NLLanguageRecognizer`);
  - reserves that language and downloads its model once, waiting at most 20 s while the download carries on for the next song;
  - transcribes the vocal stem with word times.
- On iOS before 26, on the simulator, and for unsupported languages it returns nothing.
- `LyricGuideNotesUseCase`, per line:
  - the lyric words are matched (longest common subsequence) to the words recognized from 1 s before the line to 1 s after the next line starts;
  - a matched word starts where it was heard;
  - words between two matches keep their spacing;
  - words before the first match or after the last move with it;
  - the notes are rebuilt for the moved words.
- Guards against a wrong match:
  - matches stay in order;
  - a match may not move a word more than 3 s, because that is the same word sung elsewhere, such as a bracketed backing vocal;
  - a match may not fall before the previous line has ended, because a common word like "your" heard there belongs to that line;
  - lines never overlap.

### Result (Swift code, recognized words from the Mac run)

| Song | Words within 0.3 s | Mean error | Words more than 1 s off |
|---|---|---|---|
| A Whole New World | 65% → **77%** | 0.30 → 0.22 s | 3% → 0% |
| Best Part | 73% → **86%** | 0.32 → 0.20 s | 7% → 2% |

- On "If life is a movie… best part, oh", "best" moves from 79.60 s to 77.04 s (reference 76.86 s).
- Scoring at the 0.30 threshold is unchanged: 100% and 96% of lines pass for the original vocal.
- No notes overlap.

### Not yet verified (as of 2026-11-20)

- `SpeechTranscriber` doesn't run on the simulator ("unsupported"), where the app skips it and prepares as before. The real behaviour, model download time and timing on an iPhone still need a device test. The `WordRecognition` log category shows what happened.
- Whether `SpeechTranscriber` needs the speech recognition permission on iOS. The app never asks for it. If it is needed, recognition fails, the app falls back, and the log says so.
- **Update (2026-11-21):** Verified on a physical iPhone 17 (iOS 26.6.1) — `SpeechTranscriber` works without requesting speech permission, installs `en_US` automatically, and transcribes 30 s / 60 s / 120 s vocal stems in `0.49 s / 0.84 s / 1.50 s` (see the 2026-11-21 section below).

## 3. Guide notes and scoring

### Problem

After the timing change, every clip on the device scored off-pitch and every note showed red.

Each note covered its whole word, including the leading silence and breaths. `EvaluateSegmentUseCase` scores every frame of a note:
- Silent frames counted as misses, so notes were marked missed even in a good take.
- Below 60% voiced coverage, the clip score falls back to hits over all frames.

### Change

- A word's note starts where the word's voice starts and is **held until the next word**, the way a singer holds a word. The word's leading silence (a breath, or a soft start CREPE didn't hear) is left out of the note, so it isn't scored as missed. When CREPE heard only a sliver of the word, the start moves back so the note is at least 0.3 s (`minimumNoteLength`). Two earlier versions failed on the device:
  - Notes covering the whole word scored every clip off-pitch at the old 75% threshold.
  - Notes covering only the voiced part made held words like "follow" a 0.3 s block followed by a 1.2 s empty gap, and the soft "You" a 0.04 s block.
- A word with no voice heard at all still gets a note over its own time, with the nearest pitch in its line. Example: the soft "I" in "I just wanna see…" and in "I know you're a star". A real singer does sing these words. When they were dropped, the guide showed "beautiful → are" with no "you", and lost both "I"s.
- Word labels go to the note that overlaps the word most, no longer the note under the word's middle. This applies to both the recording guide and the cover preview.
- A label that would collide with an earlier one is no longer dropped. It goes above its note, or under it after the earlier word, and is left out only when none of those fit. On the narrower preview guide, "how" in "see how beautiful" was missing for this reason.
- `passThreshold` 0.75 → **0.30** and `missedNoteThreshold` 0.50 → **0.30**. This is a contract change, approved by the user. Saved settings migrate through `ConfigurationStore` version 3.
- A log line per clip, `segment N: score …, missed notes …/…, voiced samples …` (category `Notes`), so a device take can be checked.

### Result

This is an original-singer simulation: the original vocal's CREPE notes stand in for the singer, and they are scored with the app's own rules (80 cent tolerance, 0.1 s attack skip, 0.05 s frames). It is an upper bound, with no vibrato, mic noise or speaker bleed.

Share of lyric lines that pass, by pass threshold (all three songs, new notes):

| Singer | 0.75 | 0.60 | 0.45 | 0.40 | **0.30** |
|---|---|---|---|---|---|
| Original vocal | 45% | 73% | 92% | 97% | **~99%** |
| Flat, one pitch | 0% | 1% | 1% | 5% | **8%** |
| 1–2 semitones off | 0% | 0% | 0% | 0% | **0%** |

Even before 2026-11-20's changes, the original vocal passed only 4–30% of lines at 0.75.

Red notes for the original vocal: 27% of notes at a 0.50 missed-note threshold, 7% at 0.30 (voiced-only notes). With the 0.3 s minimum and the notes for unheard words, the simulation shows 21/142 (AWNW), 28/149 (Best Part) and 7/66 (Abadi). Most of the added ones are words CREPE did not hear, which a real singer does sing.

Notes held until the next word score the same as voiced-only notes: lines passing at 0.30 are identical, with 0–2 more red notes per song.

Simulator check (Best Part, selection from "I just wanna see…" at 0:52):
- every word of "see how beautiful you are" and "You know that I see it, I know you're a star" has its own block and label, both "I"s included;
- "follow" is held until a short breath before "no".

## 4. Cover preview (7.1)

- **Lyrics.** The preview's pitch guide had no lyrics. `CompingViewModel` never received them. The guide now shows the lyric line under it and a word label under each note, the same as when recording. This also works for drafts.
- **Rows.** The guide showed 4 lines, and widened only when notes spread. It now shows at least 6 (`RecordingDisplaySettings.guideRows`), the same as the recording guide.
- **Stutter.** The reported stutter did not come back on the device after these builds.

## 5. Checks

The domain check `LyricGuideNotesUseCaseChecks` was updated and now has 38 checks. New ones:
- a held last word doesn't push earlier words late;
- a long rest is split between the words around it;
- a note starts at its word's voice, is held to the word's end, and lasts at least 0.3 s;
- a soft word the tracker missed still gets a note;
- overlapping pitch notes still give ordered, non-overlapping notes;
- lyrics 1 s early are moved by 1 s minus the attack lead;
- a well-synced song is not moved;
- recognized words anchor the words they match, the words between keep their spacing, and a match too far away is ignored.

`check-domain.sh`, `check-contracts.sh`, `check-prep.sh`, `check-comping.sh` and the app build all pass.

## 6. Limits and open items

- **Existing work keeps old notes.** Songs prepared earlier, and their covers and drafts, keep their old notes. A song must be prepared again to get the new timing.
- **Lines ending in a long ad-lib or held note (known limit, accepted 2026-11-20).** These are still the largest errors.
  - Example: in "If life is a movie, then you're the best part, oh" (Best Part), the words are sung in about 5 s, then "part" is held and "oh" is decorated for about 4 s. CREPE splits both halves into about 10 short notes each, so the words are spread over both, and "life" runs long and the words after it drift up to 2–3 s late.
  - Notes alone can't tell a decoration on one syllable from separate syllables. Three general fixes were tested on all three songs, and none improved the overall result:
    - treating back-to-back notes as one held sound;
    - an English silent-"e" syllable count ("life", "you're");
    - a cap on share per syllable.
  - Addressed for English (iOS 26+) by recognized words as anchors (section 2b). It still applies to Indonesian songs and older iOS.
- **Separation on short selections.** A short selection is separated on its own, so its CREPE notes differ from those of the same part in a longer selection.
- **Device check pending.** The scoring change still needs a check on the device, using the per-clip `Notes` log.
- **English syllable count.** The lyric parser counts vowel groups, so a silent "e" adds a syllable: "life" and "you're" count as 2. A fix needs language detection, because Indonesian words like "sore" pronounce the final "e".


---

# 2026-11-21 — Song preparation speed and stability

This section records the preparation pipeline optimizations and 120 s bug fix completed on 2026-11-21 on branch `integration` (commits `c9e5a3c`, `25d8318`, and `d5137d2`), verified on a physical iPhone 17 (iOS 26.6.1).

## Summary

All end-to-end numbers below were measured on a physical **iPhone 17** (`iOS 26.6.1`) using *A Whole New World (End Title)* (MP3, English lyrics with `SpeechTranscriber` active):

| Selection length | Baseline | Phase 1 (`25d8318`) | Phase 2 (`d5137d2`) | Improvement |
|---|---|---|---|---|
| **30 s** | 6.16 s *(~4.7 s warm)* | **2.79 s** *(0 st)* | — | **−55%** *(−41% warm)* |
| **60 s** | 8.12 s *(−1 st)* | **5.44 s** *(−1 st)* | — | **−33%** |
| **120 s** | ~15.2 s *(14.53 s before crash)* | **9.91 s** *(−2 st)* | **7.07 s** *(−2 st, 8/19 chunks pre-warmed)* | **−53% (>2× faster)** |

Per-stage breakdown on 120 s selections (iPhone 17):

| Stage | Baseline (119.5 s) | Phase 1 (120.1 s) | Phase 2 (120.2 s) |
|---|---|---|---|
| **HTDemucs separation** | 10.19 s (21 chunks) + 0.52 s lead-in | 7.84 s (18 chunks, single pass) | **5.08 s** (11 computed + 8 cached, decode `0.00 s`) |
| **CREPE pitch extraction** | 2.56 s *(read `0.96 s`, infer `1.57 s`)* | 1.04 s *(read `0.00 s`, infer `1.01 s`)* | **0.99 s** *(read `0.00 s`, infer `0.96 s`)* |
| **Word recognition (`SpeechTranscriber`)** | 1.26 s *(sequential)* | 1.52 s *(parallel with CREPE → `1.60 s` wall)* | **1.50 s** *(parallel with CREPE → `1.57 s` wall)* |
| **Transposition (4 WAVs)** | *(not reached due to crash)* | 0.43 s *(parallel)* | **0.40 s** *(parallel)* |
| **Peak memory** | 927 MB | 917 MB | **946 MB** *(2,688 MB available)* |

## 1. How it was measured

- **Device timing logs.** Detailed stage and sub-stage timings were logged to `Library/Logs/events.log` across `[Preparation]`, `[Separation]`, `[Analysis]`, `[WordRecognition]`, and `[Transposition]`, then pulled from the physical iPhone 17 via `xcrun devicectl device copy from`.
- **Why device instead of simulator.** The iOS Simulator runs CoreML HTDemucs on CPU (~3.2–4.5 s/chunk instead of ~0.38 s/chunk on iPhone 17 Metal GPU) and marks `SpeechTranscriber` as unsupported, so all latency profiling used the physical iPhone 17.
- **Correctness & seam checks.** Every phase was verified against `./scripts/check-contracts.sh`, `./scripts/check-domain.sh`, `./scripts/check-prep.sh`, and a Mac MP3 seam benchmark comparing cached chunk assembly against direct decode.

## 2. Bug fix: 120 s overlapping notes (`c9e5a3c`)

### Problem

Preparing a 120 s clip of *A Whole New World* failed with `"The keys couldn't be prepared"` right after word recognition.

`LyricGuideNotesUseCase.anchored` shifted line *i* forward using `SpeechTranscriber` word anchors past the start of line *i + 1*. When line *i + 1* had no matched anchors (`anchors.isEmpty`) or a word-count mismatch, it returned early without clamping against the previous line's new end time. `SliceSegmentsUseCase` then rejected the overlapping notes (`"Guide must be monophonic before segmentation."`).

### Change

- Added `clampedAfter(_:line:)` in `LyricGuideNotesUseCase.swift` and applied it before returning unanchored or mismatched-count lines, preserving strict monotonicity across all lines.
- Added error logging in `ImportSongViewModel.prepareSelection()` so preparation failures always record the underlying error in `events.log`.

### Result

120 s preparation completed with 0 errors across all subsequent runs.

## 3. Phase 1 — Single-pass HTDemucs lead-in, batched CREPE, and parallel stages (`25d8318`)

### Problem

Baseline profiling on iPhone 17 (60 s: `8.12 s`, 120 s: `~15.2 s`) showed five compounding bottlenecks:
1. **Duplicate HTDemucs pass for lead-in.** `PrepareSongUseCase` called `separateStems` twice: once for the trim range and a second time for the 3 s lead-in right before it (`+0.48–0.52 s` plus extra file I/O).
2. **HTDemucs chunk & iSTFT overhead.** 25% chunk overlap produced 21 chunks for 120 s, ran 4 iSTFTs per chunk (even though vocals are written as mono), used scalar Swift loops for complex deinterleaving, and wrote stems slowly (`0.93 s` on 120 s).
3. **CREPE per-frame overhead.** `CrepeAnalysisRepository` read samples in a scalar Swift loop (`0.96 s` on 120 s), resampled/normalized per frame, boxed `Float` values into `NSNumber` for CoreML `MLMultiArray`, and invoked CoreML 1 frame at a time (2,400 calls for 120 s).
4. **Sequential pipeline stages.** CREPE and `SpeechTranscriber` ran back-to-back on the same vocal stem, and transposition rendered 4 files (`mix`, `instrumental`, `leadInMix`, `leadInInstrumental`) sequentially.

### Change

- **Single-pass lead-in separation (`LeadInStemSeparation.swift`, `HTDemucsStemSeparationRepository.swift`, `PrepareSongUseCase.swift`):**
  - Added optional capability protocol `LeadInStemSeparation` in `Domain/UseCases/` (no locked contract changes).
  - Separated `[leadInStart, trimEnd]` in one pass and sliced `leadIn` + `main` stems directly from memory.
- **Faster HTDemucs DSP & chunking (`HTDemucsStemSeparationRepository.swift`):**
  - Reduced chunk overlap from 25% to 12.5% (~0.975 s overlap; 18 chunks instead of 21 for 120 s) and fixed a tail-chunk alignment edge case.
  - Averaged vocal L/R in the complex frequency domain before iSTFT (3 iSTFTs per chunk instead of 4).
  - Replaced scalar deinterleave loops with Accelerate `vDSP_ctoz` and sped up stem writing (`0.93 s → 0.06 s` on 120 s).
- **Batched, zero-boxing CREPE (`CrepePitchDetector.swift`, `CrepeAnalysisRepository.swift`):**
  - Bulk `UnsafeBufferPointer` / `vDSP` mono reading (`0.96 s → 0.00 s` on 120 s).
  - Single-pass track resample to 16 kHz, `vDSP_normalize`, raw `Float` pointer CoreML I/O (zero `NSNumber` boxing), and batched `model.predictions(from:)` with batch size 64.
- **Stage parallelism (`PrepareSongUseCase.swift`, `AudioTranspositionRepositoryImpl.swift`):**
  - Ran `CREPE` and `SpeechTranscriber` concurrently via `async let`.
  - Rendered all transposed stem files (`mix`, `instrumental`, `leadInMix`, `leadInInstrumental`) in parallel and reused the slice `AVAudioPCMBuffer` during offline rendering.

### Result

- **30 s:** `6.16 s` (cold) / `~4.7 s` (warm) → **`2.79 s`**
- **60 s:** `8.12 s` → **`5.44 s`** (−33%)
- **120 s:** `~15.2 s` → **`9.91 s`** (−35%)
- **CREPE 120 s:** `2.56 s` → **`1.04 s`** (**2.5× faster**; completely hidden behind `SpeechTranscriber`'s `1.52 s` when run in parallel).
- **Quality (`check-prep.sh`):** HTDemucs mix residual remained `-24.9 dB` (unchanged); CREPE worst edge error remained `32 ms` (unchanged).

## 4. Phase 2 — Song-level chunk cache and background trimmer pre-separation (`d5137d2`)

### Problem

Even after Phase 1, HTDemucs CoreML inference (`7.84 s` on 120 s) accounted for ~79% of total preparation time, while the user already spends several seconds listening to the preview and adjusting trim handles before tapping confirm.

A naive trim-range cache misses whenever the user moves a handle by even 0.1 s, and direct `AVAssetReader.timeRange` seeking on MP3 files introduces ~12 ms frame-boundary drift (`maxDiff 0.044`), which corrupts overlap-add seams across cached chunks.

### Change

- **Optional pre-separation protocol (`StemPreseparation.swift`):**
  - Added `StemPreseparation` in `Domain/UseCases/` (`preseparate(audioURL:trimRange:leadInDuration:)`) and forwarded it through `LoggingStemSeparationRepository`.
- **Sample-exact song decode + fixed chunk grid (`HTDemucsStemSeparationRepository.swift`):**
  - Decodes each song once via streaming (<2 MB RAM) to an atomically moved 44.1 kHz stereo Float32 file at `Caches/HTDemucsSeparation/chunks/<songKey>/source.caf`, eliminating MP3 seek drift (`-34.6 dB` seam residual across shifted trims).
  - Aligns all HTDemucs inference to a fixed song-timeline chunk grid (`segmentSamples = 343_980`, `chunkStride = 300_982`, `edgeMargin = 4096`), storing each separated chunk losslessly as `<k>.bin` (~4.13 MB) with LRU eviction keeping the 3 most recent songs (`maxCachedSongChunkFolders = 3`).
  - Added a private `actor ChunkCoordinator` to serialize Metal/CoreML execution and deduplicate in-flight decodes and chunk tasks. Foreground `separateStems` awaits any in-flight work for the same chunk and falls back cleanly (`try?`) if a cancelled background attempt failed.
- **Trimmer lifecycle scheduling (`ImportSongViewModel.swift`, `ImportSongView.swift`):**
  - Runs pre-separation at `.utility` priority after opening a song (0.8 s delay), after chorus suggestion (0.4 s), after `endSelectionEditing()` (0.6 s), and when returning to `.active`.
  - Immediately cancels/pauses pre-separation during slider drags (`beginSelectionEditing()`), on `prepareSelection()`, `saveToSongList()`, `picked()`, `suspend()`, and whenever `scenePhase != .active` (preventing iOS background GPU termination).

### Result

- **iPhone 17 (120.2 s, normal trimmer flow):**
  - Background pre-separation finished `source.caf` decoding and warmed **8 of 19 chunks** (~`0.66 s/chunk` at `.utility` QoS) with smooth trimmer audio preview and scrubbing.
  - On confirm: HTDemucs computed only the remaining 11 chunks in **`5.08 s`** (`decode 0.00 s`), bringing total 120.2 s preparation to **`7.07 s`** (**−53% / >2× faster** vs baseline; **−29%** vs Phase 1).
  - If the user picks 120 s and taps confirm immediately with 0 s wait, behavior gracefully matches Phase 1 (`~9.9 s`) without errors or races.
  - Re-trimming a nearby range on the same song reuses cached chunks on disk and finishes separation in under 1–2 s.
- **Peak memory:** `946 MB` (well within device headroom; 2,688 MB available).

## 5. Device verification of `SpeechTranscriber`

Resolved the open device-verification item from 2026-11-20 on a physical iPhone 17 (iOS 26.6.1):
- `SpeechTranscriber` runs without requesting iOS speech recognition permission.
- `en_US` installs automatically; first-run setup took `1.44 s`, and subsequent runs took `0.05–0.08 s` setup.
- On-device transcription latency: `0.49 s` (30 s, 33 words), `0.84 s` (60.5 s, 79 words), `1.50 s` (120.2 s, 143 words).

## 6. Checks, limits, and trade-offs

- **Checks passing:** `xcodebuild` (iOS Simulator), `./scripts/check-contracts.sh`, `./scripts/check-domain.sh`, and `./scripts/check-prep.sh` (`htdemucs: 20 s in 1.67 s, residual -24.9 dB`; `CREPE: 60 s in 0.30 s, worst edge error 32 ms`; `pipeline: 0.07 s`).
- **Pre-separation QoS (`.utility`):** Intentionally kept at `.utility` (`~0.66 s/chunk` vs `~0.38 s/chunk` foreground) so trimmer audio playback and handle dragging stay glitch-free. Raising to `.medium` could warm more chunks in the same trimmer window (~14–16 chunks, pushing 120 s toward ~4 s) at the cost of higher foreground GPU/CPU contention.
- **Chunk cache storage:** Each cached chunk is ~4.13 MB (a 2-minute range is ~19 chunks ≈ 78 MB plus `source.caf`), stored in `Library/Caches` (purgeable by iOS) and bounded to the 3 most recent songs via LRU pruning.
- **First-launch CoreML compilation:** Cold first-launch `prewarm` on iPhone 17 still compiles CoreML models once per install/update (`CREPE ~14–16 s`, `htdemucs ~4.2 s` in background on app launch); subsequent launches prewarm in `CREPE 0.05–0.08 s` and `htdemucs ~1.25 s`.

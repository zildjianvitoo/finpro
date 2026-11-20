# Lyric guide timing and scoring: what we optimized (2026-11-20)

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

The domain check `LyricGuideNotesUseCaseChecks` was updated and now has 27 checks. New ones:
- a held last word doesn't push earlier words late;
- a long rest is split between the words around it;
- a note covers only the voiced part of its word;
- lyrics 1 s early are moved by 1 s minus the attack lead;
- a well-synced song is not moved.

`check-domain.sh`, `check-contracts.sh`, `check-prep.sh` and the app build all pass.

## 6. Limits and open items

- **Existing work keeps old notes.** Songs prepared earlier, and their covers and drafts, keep their old notes. A song must be prepared again to get the new timing.
- **Lines ending in a long ad-lib or held note (known limit, accepted 2026-11-20).** These are still the largest errors.
  - Example: in "If life is a movie, then you're the best part, oh" (Best Part), the words are sung in about 5 s, then "part" is held and "oh" is decorated for about 4 s. CREPE splits both halves into about 10 short notes each, so the words are spread over both, and "life" runs long and the words after it drift up to 2–3 s late.
  - Notes alone can't tell a decoration on one syllable from separate syllables. Three general fixes were tested on all three songs, and none improved the overall result:
    - treating back-to-back notes as one held sound;
    - an English silent-"e" syllable count ("life", "you're");
    - a cap on share per syllable.
  - The way forward is recognizing the sung words on device and using their timestamps as anchors.
- **Separation on short selections.** A short selection is separated on its own, so its CREPE notes differ from those of the same part in a longer selection.
- **Device check pending.** The scoring change still needs a check on the device, using the per-clip `Notes` log.
- **English syllable count.** The lyric parser counts vowel groups, so a silent "e" adds a syllable: "life" and "you're" count as 2. A fix needs language detection, because Indonesian words like "sore" pronounce the final "e".

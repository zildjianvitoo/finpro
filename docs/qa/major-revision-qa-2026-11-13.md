# Major revision QA — 13 November 2026

## Status

Branch: `takin`. Audit covers all 17 attached QA images and all 10 current files in `docs/design/v2` (the actual checkout path; no `docs/desain/v2` folder exists). Previous user changes, including signing/project settings, are preserved.

**Source revision implemented; no screen is marked visually complete.** Simulator baseline and post-change screenshots remain blocked: CoreSimulator refuses the execution session's connection, and the native app-control kernel exits with Broken pipe. This report distinguishes code changes, logic verification and visual verification.

## Checklist

Every row still needs comparison on a running Simulator. “Implemented” below means the code was revised, not that the screen passed visual QA.

| ID | QA requirement | Code revision | Simulator |
|---|---|---|---|
| Q01 | Get Started chevron after text | Explicit trailing HStack | Pending |
| Q02 | Welcome latest copy, typography and layout | Record covers effortlessly; design-system title; bounded pager | Pending |
| Q03 | SF Pro on First / Meet | Default system display font, no rounded face | Pending |
| Q04 | Intro shape, bounds, shadow and CTA | Background excluded from foreground sizing; semantic plum; contained text/CTA | Pending |
| Q05 | Humming header | Shared full-width responsive header | Pending |
| Q06 | Humming surface and text | Light semantic surface with plum text | Pending |
| Q07 | Mic placement consistent across four stages | One proportional anchor and common diameter/layout | Pending |
| Q08 | Remove text below mic | Visible hints removed; accessibility hints retained | Pending |
| Q09 | Filled idle mic | mic.fill | Pending |
| Q10 | Warm-up ring follows passage duration | Voiced time divided by passage-length estimate, not a fixed six seconds | Pending |
| Q11 | Breathing and tap-to-start, one-second notes | Breathing affordance; real stream starts on tap; hold duration remains 1 s | Pending |
| Q12 | Curved vocal pitch scale | Shared CurvedPitchDial replaces horizontal ruler | Pending |
| Q13 | Green position follows microphone pitch | LivePitchPositionUseCase maps stabilized MIDI; invalid/silent input has no indicator | Pending |
| Q14 | Lowest/highest instructions and states | Distinct prompts; shared anchored layout; raw detector retained | Pending |
| Q15 | No extra note/instruction above meter | Removed; musical note labels stay on the scale and in accessibility | Pending |
| Q16 | No Debug button in Home | Overlay removed; developer settings available through explicit launch argument | Pending |
| Q17 | Compact tooltip | One message, no Got it action, custom style and arrow toward + | Pending |
| Q18 | Lyrics bold without green word highlighting | Removed word background color; active/selected line uses existing tokens | Pending |
| Q19 | Match waveform variants | Real source peaks, zoomed viewport, clip and library variants | Pending |
| Q20 | No play/pause beneath waveform | Removed; selection autoplay/looping retained | Pending |
| Q21 | No Opening song full-state modal | Keep import surface while actual file import runs | Pending |
| Q22 | No Finding lyrics full-state spinner | Lyrics load in place; waveform remains usable; honest missing/error states retained | Pending |
| Q23 | Song List title capitalization | Corrected | Pending |
| Q24 | Select/Cancel component | Reusable semantic chip, disabled/pressed states | Pending |
| Q25 | Relative dates | Calendar-aware Yesterday/Today/Tomorrow, formatted dates otherwise | Pending |
| Q26 | Row tap must not open section modal | Row expands only | Pending |
| Q27 | Voice Memos style player | Inline player/progress and right waveform action | Pending |
| Q28 | Remove lower-left duplicate pencil | Rename remains beside title and edits inline | Pending |
| Q29 | Waveform action opens section sheet | Dedicated action; compact library detent and centered header | Pending |
| Q30 | Dark preparation overlay with spinner | Replaces progress/step page; real task and errors retained | Pending |
| Q31 | Remove Back to selection | Removed visible action; cleanup/cancellation remains internal | Pending |
| Q32 | More curved key control | Shared curved geometry | Pending |
| Q33 | No extra horizontal Slider | Dial drag/VoiceOver change the rendered key directly | Pending |
| Q34 | No extra preview caption/button | Dial and vocal-note area provide preview interaction | Pending |
| Q35 | Key preview must include vocals | Both preview paths use earphoneMixURL | Pending |
| Q36 | Remove Get Ready screen | Key confirmation starts recording; permission gate and session setup retained | Pending |
| Q37 | Consistent design system | Shared spacing/layout/dial/chip/secondary button; existing colors and SF typography | Pending |
| Q38 | Vocal result chart/header | Curved header, true octave grid and measured range; shared CTA styles | Pending |
| Q39 | Export preview portrait and clips | Portrait player, Export action, actual thumbnails, seekable clip strip | Pending |
| Q40 | No fabricated functional media | Real RMS envelope and saved-cover thumbnails; device uses real microphone; existing simulator fixtures are not real-audio validation | Pending |
| Q41 | Responsive/interaction validation | Bounded content, scrollable text areas, adaptive mic/video sizing and input accessibility | Pending |

## Logic and build verification

Recorded outcomes:

- PASS: standalone vocal range checks, including one-second hold, explicit mic taps, passage duration, actual RMS history, live MIDI position, invalid/silent input, ascending/clamped movement, interruption and full saved-range flow.
- PASS: `VocalKeyChecks` — 47 checks, including preview of the vocal mix.
- PASS: `SongSelectionChecks` — 35 checks, including relative dates, persistence, waveform viewport and old-screen/new-screen playback ownership.
- PASS: all existing contract and domain checks (including randomized segmentation/evaluation checks).
- PASS: supplementary all-source iOS typecheck, also with the project's default MainActor isolation. Temporary SDK macro stand-ins were used; this is not an app build.
- PASS: `git diff --check`.
- BLOCKED: full `xcodebuild` for iOS Simulator. SDK CoreML stages fail with `sandbox-exec: sandbox_apply: Operation not permitted`; CoreSimulator also refuses the session connection. The model packages themselves were restored and separately verified earlier.
- BLOCKED: screenshot script before/after implementation; no booted Simulator can be queried from this session.
- BLOCKED: native Simulator access; the application-control kernel exits with Broken pipe.

Logic tests cover 1 s stability, voiced reading progress, RMS history, invalid pitch, frequency-to-MIDI mapping, consecutive chromatic notes and cents offset, silence, jitter/glissando, restart, relative dates, selection viewport, persistence, one recommendation, mix preview and playback ownership during navigation.

The all-source iOS typecheck uses temporary macro stand-ins because the execution sandbox blocks the SDK macro plugin sandbox. It catches ordinary typing errors but is **not** an app build or Simulator run. Full app build and screenshot commands are attempted separately and failures are recorded honestly.

## Reference interpretation and retained behavior

- v2 `Pitch - Lowest.png` introduces the curved scale; green movement is calculated from real pitch. Vocal scale labels are consecutive chromatic notes that recenter on the nearest detected microphone note, with its indicator snapped to that same note and fading at both ends; key labels remain semitone offsets. The microphone value is not replaced by a decorative key animation.
- Reading progress is based on accumulated voiced sample time and a configured reading-rate estimate for the paragraph. It is not speech recognition and does not claim to know the exact spoken word.
- The 1 s requirement applies to sung limits and humming practice, not the entire reading passage.
- Actual separation remains HTDemucs; audio/target notes use the same transpose. The reference vocal mix is used for key audition, and instrumental remains the recording backing/export input.
- Saved songs and exports remain durable. Cover cards now request real thumbnails from saved video files; a neutral video affordance handles unavailable frames without fabricating media.
- Removing Get Ready does not remove Recording Settings: the existing recording settings sheet still reads the same persisted preferences. Permissions, route checks, session cleanup and PreparedSong validation are retained.
- The export + menu offers supported recording/new-cover actions; appending arbitrary clips to an existing composition is not invented as a dummy interaction.
- Warm-up/Humming/highest/Song List do not have individual new v2 files in this checkout. The annotated QA images supply their missing visual details; archived v1 was not used.
- Do not mark any screen done until screenshots and interactions have been reviewed at small, reference (402×874 pt) and large sizes. Physical audio/camera testing remains necessary for hardware behavior.

## Follow-up corrections — intro typography and ordered pitch scale

- Replaced the intro ellipse with a curved-top shape that extends through the bottom safe area.
- Tightened Your / vocal / range using the existing SF Pro bold font cap-height metrics; warm-up paragraph and instructions use existing title/subheadline tokens.
- Ordered MIDI notes scroll under the detected pitch, retain their last position during silence and reset between low/high tests. No timer-generated pitch is used.
- PASS: one-second hold / microphone state / ordered pitch mapping checks, contract and domain checks, and 47 key checks.
- Simulator visual validation remains pending: the verification command cannot connect to CoreSimulatorService (Connection refused).

## Follow-up — Song List and key autoplay

- Select uses a neutral material capsule with plum text, matching the latest supplied reference; Cancel retains the active plum fill.
- Inline `pencil.line` sits beside the expanded song title. Plain row buttons isolate playback, rename and section actions from List's automatic button activation.
- A row tap expands and starts in-place playback. Only the waveform action (or explicit context menu section action) opens the section sheet.
- Preparation uses the supplied dimmed overlay treatment with a white film icon and “Preparing your song…” plus pipeline-stage percentage, without simulated progress or a Back to selection button.
- Today / Yesterday / Tomorrow use calendar days; dates farther away use localized dates.
- Find your key starts the selected vocal-and-backing preview on entry. Repeated appearances do not toggle active playback off.
- PASS: 41 SongSelectionChecks, including row playback, repeated entry autoplay and date fallback. Supplementary whole-source typecheck passes; this does not substitute for a full Xcode build.
- Simulator visual validation remains pending because CoreSimulator access is unavailable in this session.
- Full Xcode build attempted with writable DerivedData: blocked by `sandbox-exec: sandbox_apply: Operation not permitted` during model build steps. No project signing/build settings changed.

## Follow-up — exact vocal slider alignment

- Both the vocal slider marker and scale center now use the rounded chromatic MIDI note shown by the label. Fractional detected MIDI previously placed the marker beside the labelled tick.
- Raw MIDI and cents remain unchanged for vocal analysis; only the visual anchor snaps to the note.
- Regression coverage includes slightly flat/sharp C3 input, semitone boundaries and every interior MIDI note.
- Simulator verification was attempted again; CoreSimulatorService is still unavailable, so visual validation remains pending.

## Follow-up — idle microphone ring

- Removed the green outline on the microphone icon state across vocal-test steps. The base ring uses existing plum tokens; the lime mic icon remains.
- Progress is shown only after capture has started, so an idle mic cannot display a stale green progress arc.
- Visual validation remains pending while simulator access is unavailable.

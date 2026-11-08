---
name: ui-verify
description: Check a finpro screen on the iOS simulator cheaply. Use for UI slicing and any request to run the app, see a screen, or take a screenshot. Opens the app straight on a screen with launch arguments and returns one small screenshot, instead of tapping through the flow.
---

# ui-verify

Goal: see a screen with as few tool calls and image tokens as possible.

## Do this

1. Run the script (builds, installs, launches on the screen, saves a small screenshot):

   ```bash
   .claude/skills/ui-verify/ui-verify.sh <screen> [importFile]
   ```

   `screen`: `onboarding`, `vocalRange`, `home`, `importSong`. Its last output line is the PNG path.
2. Read that PNG once. It is 400 px wide, enough to compare layout, spacing and colors with Figma.
3. Edit, then re-run with `SKIP_BUILD=1` only if nothing in Swift changed; otherwise run it normally.

## The trimmer (needs a song)

```bash
SONG=$(.claude/skills/ui-verify/make-dummy-song.sh)      # 60 s synthetic melody, our own
.claude/skills/ui-verify/ui-verify.sh importSong "$SONG" # opens it in the trimmer
```

`-importFile` skips the file picker. To test the real picker, copy the song into the simulator's
Files (`.../Containers/Shared/AppGroup/<id>/File Provider Storage`, the group whose metadata says
`group.com.apple.FileProvider.LocalStorage`).

## How it works

Debug builds read two launch arguments (`DebugOptions`): `-startScreen <step>` (applied in
`AppFlow.init`) and `-importFile <path>` (applied in `ImportSongView`). Release builds ignore them.
Steps that need earlier data (`chooseKey`, `ready`, `recording`, `export`) have no argument; reach
them with taps, or add a launch argument that loads demo data.

## Keep it cheap

- Use the script's screenshot, not full-resolution `control screenshot` (1206×2622). If you must
  use the tool, pass `scale: 0.4`.
- Tap only for the interaction under test (drag, toggle), not to navigate.
- Logic-only changes (state, enabled/disabled) need a build, not a screenshot.
- Never run the build twice with different destinations; the script builds once for the booted device.
- If the app does not show up after launch, run the script again instead of probing with screenshots.

## Gotchas

- More than one simulator can be booted; `simctl ... booted` then hits an arbitrary one while the
  `control` tool targets another. Use the UDID (the script does) and pass `device` to `control`.
- `control screenshot` can ignore `scale` and return the full 1206×2622 image. For screenshots after
  taps, use `xcrun simctl io <UDID> screenshot f.png` and `sips --resampleWidth 300 f.png`.
- The fakes container sings every segment correctly, so a failed attempt (retry countdown) never
  happens on its own; to look at it, force the condition temporarily and revert.

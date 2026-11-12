# Design source

The UI is designed in **Sketch**. This page says where, and how to read exact values (colors, fonts,
sizes, spacing) instead of guessing them from screenshots.

## The file

- Document: **`[C6] Project Besar`** (keep it open in Sketch while working on UI).
- Pages:
  - **Hi-Fid** — the final screens. This is the one to build from.
  - **Mid-Fid** — earlier mid-fidelity versions of the same flow. Reference only.
  - **Design System** — shared components (today: `Primary Button`, `secondary`). Grows with the design system work.
  - **Artifact** — scratch.
- Device frame: 402 × 874 pt (iPhone 17). Units in Sketch are points, the same as SwiftUI.
- Screenshots of frames, named by capture time, live in versioned folders under `docs/design/`.
  **Active reference: none yet (waiting for the redesign; it goes in `docs/design/v2/`).** `docs/design/v1/` is the
  archived first design: do not read it unless asked. Until `v2/` exists, use Sketch for the current design.
  Screenshots can be older than the file; Sketch wins when it is reachable.

### Screens on Hi-Fid (frame names)

| Flow | Frames |
|---|---|
| Onboarding | `splash`, `onboard 1`, `onboard 2`, `onboard 3` |
| Vocal test | unnamed `iPhone 17 Copy …` frames, `RESULT vocrang Copy 3` |
| Home | `main screen empty state`, `tool tip`, `main screen`, `ketika pencet see all` |
| Import | `add a song`, `add a tittle`, `selected part`, `selected part copy` (later sheet variant, not built), `loading progres`, `progress done` |
| Get ready | `Settingan sebelum record`, `tips for headphones` |
| Recording, camera layout | `record ga ada linenya`, `record ada linenya`, `record if true`, `record if false`, `if false try again in tht phrase` |
| Recording, full guide | `record with full guide`, `if bener`, `if salah`, `if salah try again` |
| Recording settings and pause | `setting preferences`, `setting on offf lyrics`, `setting opacity`, `lyrics off`, `pause`, `settingan …` |
| Final result | the `iPhone 17 Copy 11`–`13` frames and `ketika pencet see all` (second one) in the lowest row |

Frame names are the designer's working names and may change. Ask the user when a frame is unclear.

## Sketch MCP

Sketch has a built-in MCP server. It is configured in a local, git-ignored `.mcp.json` at the repo root (the port differs per machine, so create it yourself):

```json
{ "mcpServers": { "sketch": { "type": "http", "url": "http://localhost:31126/mcp" } } }
```

Setup, once per machine:

1. Sketch → **Settings → General → "Allow AI tools to interact with open documents"**.
2. Copy the **MCP server URL** shown there into `.mcp.json`. Do not assume the port: it can differ per machine or
   change after an update. If a call fails with a transport error, re-check the URL in Sketch first.
3. Open the document, then (re)start the coding session and approve the `sketch` server.

Tools: `get_document_info`, `get_layer_tree_summary`, `get_screenshot`, `get_libraries`,
`get_design_assets`, `get_symbol_overrides`, `run_code` (Sketch JavaScript API), `get_guide`.
The guides ship inside the app: `/Applications/Sketch.app/Contents/Resources/MCPGuides/*.md`.

Rules for agents:

- **Read only.** Inspect and take screenshots; never create, edit or delete layers in the designer's file.
- Call `get_guide` with `topic: "mcp"` before any other Sketch tool, as the guide asks.
- `run_code` takes its source in the `script` argument and reports through `console.log(JSON.stringify(...))`.
- Prefer layer IDs from `get_document_info` / `get_layer_tree_summary` over names (names repeat across pages).
- To compare a screen, take `get_screenshot` of the Hi-Fid frame and a simulator screenshot
  (`.claude/skills/ui-verify`) at the same width.

### Without the MCP tools loaded

The server speaks plain JSON-RPC over HTTP, so a script can call it (this is how it was probed):

```bash
curl -s -X POST http://localhost:31126/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_document_info","arguments":{}}}'
```

### Reading tokens

Both snippets were run against the file and work. Send them through `run_code`.

Swatches (colors with the designer's names):

```javascript
const sketch = require('sketch');
const doc = sketch.getSelectedDocument();
console.log(JSON.stringify(doc.swatches.map(s => ({ name: s.name, color: s.color }))));
```

Texts of one frame: the string, its shared text style, color and position. Change the frame name as needed:

```javascript
const sketch = require('sketch');
const doc = sketch.getSelectedDocument();
const page = doc.pages.find(p => p.name === 'Hi-Fid');
const frame = page.layers.find(l => l.name === 'add a song');
console.log(JSON.stringify(sketch.find('Text', frame).map(t => ({
  text: t.text, style: t.sharedStyle ? t.sharedStyle.name : null, color: t.style.textColor,
  x: Math.round(t.frame.x), y: Math.round(t.frame.y), w: Math.round(t.frame.width),
}))));
```

Notes from probing this file:

- The **shared text style name is the reliable font source**: it is the iOS style, e.g. `02 Title1/2 Bold`,
  `04 Title3/2 Bold`, `08 Subheadline/1 Default`, `09 Footnote/1 Default`, `11 Caption2/1 Default`
  (family `SF Pro`). Map `/1 Default` to regular and `/2 Bold` to bold on the SwiftUI font of the same name.
- `fontSize` and `fontWeight` come back `null` through this API, and `sharedTextStyles[].style` exposes no
  properties. Do not rely on them; use the style name, or measure the frame height.
- Fills, borders and radii: read `style.fills[].color`, `style.borders`, `style.cornerRadii`; positions from `frame`
  (relative to the parent group, so add the parents' offsets for absolute values).

## Design system in code (Sketch page "Design System", read 2026-11-12)

The single source of truth for colors, type, radii and buttons is the Sketch page **Design System** (one frame).
The code mirrors it 1:1; compare with the debug gallery: `-startScreen designSystem` (`DesignSystemGalleryView`).

**Colors** (asset catalog, generated symbols such as `Color.primary500`):

| Sketch | Asset / symbol | Light | Dark (derived) |
| --- | --- | --- | --- |
| Primary ramp, 8 steps | `Primary100` … `Primary800` | `F3EAF1 C9A3BC A66B94 843D70 6A1E55 5D1941 4F123E 3F0D31` | same |
| Secondary ramp (lime), 8 steps | `Secondary100` … `Secondary800` | `F7FDE8 E9FCBD DFFB87 D6FB61 B2D94A 91B52E 718F20 526A13` | same |
| PrimaryBrand | `primaryBrand` | `6A1E55` | `A66B94` |
| SecBrand | `secBrand` | `D6FB61` | `D6FB61` |
| PrimaryDark | `primaryDark` | `4F123E` | `6A1E55` |
| SmallButton | `smallButton` | `D6FB61` | `D6FB61` |
| PrimaryButton | `primaryButton` | `6A1E55` | `843D70` |
| SelectedButton | `selectedButton` | `4F123E` | `6A1E55` |
| SecondaryButton | `secondaryButton` | `F3EAF2` | `3F0D31` |
| Background | `screenBackground` (not `background`: it clashes with `ShapeStyle.background`) | `FAF7F9` | `1F0A19` |
| BodyText | `bodyText` | `6A1E55` | `F3EAF1` |
| SecText | `secText` | `843D70` | `C9A3BC` |
| SecondaryText | `secondaryText` | `92547F` | `B07C9F` |
| TertiaryText | `tertiaryText` | `B77FA6` | `8F5E82` |

- Sketch has **light values only**. The dark column is derived by the rule "text roles move to the light end of the
  ramp, fills move one step lighter so white text stays readable, the primary/selected relation (selected is darker)
  is kept". It is not from the designer: review it before shipping dark mode.
- Measured, not read: the lime ramp labels in Sketch are copy-pasted from the primary ramp, so the lime values come from
  the swatch pixels (`D6FB61` appears as step 400, which cross-checks). `TertiaryText` is the placeholder text
  `#Tertiary` in Sketch; its value is the swatch pixel `B77FA6`. Replace them if the designer fixes the page.
- Old assets (`BrandPlum`, `PlumInk`, `Ring*`, `Surface*`, …) are not part of the design system. They stay until the
  screen that uses them is re-sliced; delete each when its last user is gone.

**Typography**: system text styles via `Font+Typography.swift`: `appLargeTitle` (Bold 34), `appTitle1` (SemiBold 28),
`appTitle2` (SemiBold 22), `appTitle3` (20), `appHeadline` (SemiBold 17), `appBody` (17), `appSubheadline` (15),
`appFootnote` (13), `appCaption` (12), `appCaption2` (11), `appCTA` (SemiBold 17). They follow Dynamic Type.

**Radius**: `AppRadius.large` 20, `.medium` 16, `.small` 12.

**Buttons** (`Presentation/DesignSystem/Buttons/`), 56 pt capsule, text `appCTA`:

- `.appPrimary`: fill `primaryButton`, white text; pressed `primary800`; disabled fill `secondaryButton`, text `secText`.
- `.appAccent` (Sketch "Secondary Button"): fill `smallButton`, text `primary800`; pressed `secondary500` (derived).
- `.appIcon(.primary | .secondary | .tinted)`: 44 pt circle; fills `primaryButton` / `smallButton` / `secondaryButton`,
  glyphs white / `primary800` / `primaryBrand`; pressed and disabled use opacity (derived).
- Sketch backs these with the Liquid Glass "Button Backgrounds - Tinted" symbol; the code uses a plain tinted capsule,
  which reproduces the colors exactly.

## Older snapshot of document-wide values (2026-11-09)

Read from the whole document before the Design System page was used; where it disagrees with the section above, the
section above wins.

- 39 swatches, many left over from exploration (`idk`, `hmm`, `BASE`, …). The ones the app uses:
  `bg #FAF7F9`, `primary text #3B1C32`, `second text #806D79`, `card #6A1E55`,
  `selected bg card #F0E5EC`, `progress bar #805B71`, `button` / `toggle on #3B1C32`,
  `right phrase #80E04B`, `false #E85B67`, `hijau berani #D6FB61`.
- 34 text styles, all based on the iOS system styles (LargeTitle … Caption2, regular and bold), so SwiftUI
  semantic fonts (`.title`, `.headline`, `.footnote`, …) map directly and keep Dynamic Type.
- Liquid Glass layer styles (Light and Dark) for the round buttons and sheets.
- Known drift: the app's `OnboardingBackground` asset is `#FBF8FA`, Sketch's `bg` is `#FAF7F9`.

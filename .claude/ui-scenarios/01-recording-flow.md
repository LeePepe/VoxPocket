# Scenario: 录音主流程 (Recording Flow)

**Trigger layers**: VoxPresentation, VoxApplication, VoxInfrastructure (audio)
**Priority**: P0 — always run

## Required AX Elements

| Identifier | Role | Condition |
|---|---|---|
| `vox.record.button` | AXButton | Must be visible on launch |
| `vox.transcript.live` | AXStaticText | Appears during recording |
| `vox.transcript.final` | AXStaticText | Appears after stop |

## Steps

1. **Launch check**: Get AX tree immediately after bridge ready
   - Verify `vox.record.button` present → FAIL if missing
   - Take screenshot
   - Evaluate: "VoxPocket main editor is shown, recording button is clearly visible, no error dialogs"

2. **UI state before recording**:
   - Evaluate screenshot: "The interface looks clean and ready to record. No unexpected loading states."

3. **Recording state check** (observation only — no actual recording in CI):
   - Verify `vox.editor.undo` present (toolbar)
   - Verify `vox.editor.redo` present (toolbar)
   - Verify `vox.editor.refine.toggle` present (toolbar)
   - Take screenshot
   - Evaluate: "Toolbar buttons are visible and appropriately sized. Layout feels balanced."

## Pass Criteria

- All required AX elements found in tree
- Both vision evaluations return `pass: true`
- No error dialogs or crash indicators visible

## Notes for Vision Evaluator

This is a macOS app. The editor should show:
- A prominent record button (microphone icon)
- A text area for transcription
- A toolbar with undo/redo/refine controls
- Clean, minimal design with no visual glitches

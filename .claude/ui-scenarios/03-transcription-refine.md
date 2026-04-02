# Scenario: Transcription + Refinement UI

**Trigger layers**: VoxPresentation (EditorViewModel, RefinementPanelView), VoxApplication (RefinementUseCase)
**Priority**: P1 — run when editor or refinement files changed

## Context

Verifies the editor UI that shows transcription text and refinement controls. Since we cannot perform actual transcription in CI, we verify the structural integrity of the refinement panel.

## Required AX Elements

| Identifier | Role | Condition |
|---|---|---|
| `vox.editor.refine.toggle` | AXButton | Must be in toolbar |
| `vox.editor.undo` | AXButton | Must be in toolbar |
| `vox.editor.redo` | AXButton | Must be in toolbar |
| `vox.transcript.final` | AXStaticText | May be empty but element must exist |

## Steps

1. **Editor toolbar check**:
   - Get AX tree
   - Verify all 4 required elements present
   - Take screenshot
   - Evaluate: "The editor toolbar shows refinement toggle, undo and redo buttons. They are clearly visible and not overlapping."

2. **Refinement toggle accessibility**:
   - Confirm `vox.editor.refine.toggle` is in the AX tree with role AXButton
   - Evaluate: "The refine button appears interactive and correctly positioned within the toolbar"

3. **Text area availability**:
   - Verify `vox.transcript.final` present (even if empty)
   - Take screenshot
   - Evaluate: "The main text area / transcript area is present and has a clear visual boundary. No UI elements are overlapping it unexpectedly."

## Pass Criteria

- All 4 AX elements found
- Both vision evaluations return `pass: true`
- Toolbar layout is not broken (buttons not overlapping or hidden)

## Notes for Vision Evaluator

Focus on:
- Toolbar button layout and spacing
- Text area prominence and accessibility
- Whether the refinement toggle looks distinct from other controls
- Any visual regression compared to expected macOS editor design

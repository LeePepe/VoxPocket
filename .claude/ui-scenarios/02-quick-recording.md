# Scenario: Quick Recording Panel (macOS)

**Trigger layers**: VoxPresentation (QuickRecordingView), PlatformAdapters (macOS)
**Priority**: P1 — run when macOS-specific or QuickRecording files changed

## Context

Quick Recording is a floating NSPanel triggered by the Fn hotkey on macOS. In CI we cannot simulate the global hotkey, so we verify the panel can be opened programmatically and its UI is correct.

## Required AX Elements

The quick recording panel is a separate window. After it opens:

| Identifier | Role | Condition |
|---|---|---|
| `vox.record.button` | AXButton | In the quick panel |

## Steps

1. **Panel availability check**:
   - Get AX tree
   - Evaluate the main screenshot: "The VoxPocket main window is visible and correctly laid out for macOS"
   - Check that macOS-specific toolbar (sidebar icons) are present

2. **Layout integrity**:
   - Take screenshot
   - Evaluate: "The macOS app window has a proper title bar, sidebar or toolbar with navigation icons, and a main content area. No visual corruption or misaligned elements."

3. **Sidebar navigation check** (iPad/Mac split view):
   - Verify toolbar buttons for navigation are visible
   - Evaluate: "Navigation controls are visible and accessible"

## Pass Criteria

- Main editor window renders without visual glitches
- macOS toolbar/sidebar controls are visible
- No overlapping or cut-off UI elements

## Notes for Vision Evaluator

This is a macOS native app (not iOS). Expect:
- A standard macOS window with title bar
- Sidebar or toolbar with session/history navigation
- Main content area with the recording interface
- Dark or light mode depending on system setting

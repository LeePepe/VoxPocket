# HomeRecorderView + BackgroundAtmosphere Redesign (Liquid Glass Minimal)

Date: 2026-02-03

## Goal
Redesign `HomeRecorderView` and `BackgroundAtmosphere` into a minimal, Apple 2026-aligned visual language with light glass layers, calm typography, and state-driven atmosphere. iOS should hide the raw transcript inline and expose it through a top-right Raw entry. Larger screens keep the raw transcript inline as a secondary panel.

## Aesthetic Direction
**Liquid Glass Minimal**
- Thin glass layers with restrained blur and edge highlights.
- Low-saturation, cool palette; no dramatic accents.
- Clear hierarchy: refined text as the hero; raw transcript is secondary.
- Motion is subtle and consistent (fade + slight lift + slow breathing).

## Layout & Behavior
- Maintain vertical layout with TopBar, refined text, optional raw pane, and bottom controls.
- iOS: hide raw inline pane; provide Raw entry in top-right (capsule / icon+text).
- macOS / iPad: show raw inline pane below refined pane.

## Component-Level Design
### TopBar
- Slim floating bar with light glass background, fine stroke, subtle inner highlight.
- Buttons are small rounded rectangles with light material and minimal hover/press feedback.
- Raw entry appears in top-right on iOS.

### RefinedTextPane
- Primary glass card with larger corner radius and slightly stronger depth.
- Typography uses SF Pro (system) for Apple-native feel.
- Status text small, low contrast, anchored beneath the main text.

### RawInlinePane
- Secondary glass card with lower opacity, lighter stroke, smaller text.
- Title becomes a small label-like header.

### BottomControls
- Primary button color responds to status but stays low saturation.
- Secondary buttons use lighter glass style; consistent sizing and rounded corners.
- Press feedback: slight scale (0.98) and reduced highlight.

## BackgroundAtmosphere
- Three-layer structure: base gradient + soft light bloom + controlled vignette.
- State-driven palette and brightness shifts:
  - idle: brighter, airy
  - listening: deeper, cooler
  - refining: slightly violet, calm
  - done: lift back to clear
  - error: muted red tint (no harsh saturation)
- Use slow breathing animations (6–10s periods), avoid aggressive pulses.

## States & Transitions
- All status changes animate with 0.4–0.6s ease in/out.
- Entry animation: 0.35–0.45s fade + slight upward offset.
- Subtle breathing effect tied to status in BackgroundAtmosphere.

## Accessibility & Performance
- Keep contrast readable despite glass layers; avoid overly low text opacity.
- Limit blur layers and shadow depth to avoid heavy GPU cost.
- Keep animations lightweight (no excessive per-frame effects beyond TimelineView usage).

## Testing / Validation
- Visual pass for all RecorderStatus values.
- Verify iOS vs macOS/iPad layout behavior.
- Check Raw entry visibility and accessibility on iOS.
- Ensure no regressions in existing state-driven behavior.

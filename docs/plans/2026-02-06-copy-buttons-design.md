# Copy Buttons Design

**Goal:** Add copy functionality so the main Copy button duplicates the refined editor text, and the Raw Transcript screen provides a Copy Raw action for the raw transcript.

**Context:** UIShared presents the HomeRecorderView, RawTranscriptView, and related UI. The platform clipboard implementation exists in PlatformAdapters (ClipboardService). The UIShared layer should remain platform-agnostic, so copy behavior is injected via closures from the app layer or view models.

## User Experience

- **Bottom “Copy” button**: copies the current refined text (editor content).
- **Raw Transcript screen**: adds a “Copy Raw” button in the navigation toolbar, copying the raw transcript text.
- If raw transcript is empty, “Copy Raw” is disabled (reduced opacity).

## Architecture

- UIShared views receive copy closures:
  - HomeRecorderView already accepts `onCopy`. Wire it to copy the editor text.
  - RawTranscriptView will accept a new `onCopyRaw` closure and a `canCopyRaw` flag.
- The app layer (e.g., VoxPocket / RootViewModel owner) will supply closures that call a clipboard service.
- Clipboard integration uses `PlatformAdapters.ClipboardService` (macOS has MacOSClipboardService). iOS can use a platform-appropriate implementation behind the same interface.

## Data Flow

- `HomeRecorderView` → `onCopy` → clipboard copies `editorState.text`.
- `RawTranscriptView` → `onCopyRaw` → clipboard copies raw transcript string.

## Error Handling

- No new error states; copy is a best-effort action.
- Disable “Copy Raw” when raw transcript is empty to avoid copying empty content.

## Testing

- Add a UIShared unit test to verify:
  - `onCopy` is invoked for the bottom Copy button.
  - “Copy Raw” button is disabled when raw transcript is empty and enabled otherwise.

## Implementation Notes

- Update `RawTranscriptView` signature to include `onCopyRaw` and `canCopyRaw`.
- Wire `HomeRecorderView`’s `onCopy` to a closure provided by the view model or top-level view.
- Keep UIShared free of platform-specific clipboard types; use closure injection instead.

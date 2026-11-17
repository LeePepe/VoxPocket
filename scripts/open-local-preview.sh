#!/usr/bin/env bash
# open-local-preview.sh — One-command launcher for VoxPocket's native macOS SwiftUI 4-Up Todo Unfold Preview Window
#
# Usage:
#   scripts/open-local-preview.sh            Build & launch VoxTodoPreviewHost in the foreground (NSApp.activate)
#   scripts/open-local-preview.sh --xcode    Open Packages/VoxPresentation in Xcode for #Preview Canvas
#   scripts/open-local-preview.sh --export <dir>  Export 60fps real SwiftUI transition frames & keyframes
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case "${1:-}" in
    --xcode)
        echo "[open-local-preview] Opening Packages/VoxPresentation in Xcode for #Preview Canvas..."
        xed "$ROOT/Packages/VoxPresentation"
        exit 0
        ;;
    --export)
        OUT_DIR="${2:?--export requires an output directory}"
        echo "[open-local-preview] Exporting real SwiftUI frames & keyframes to $OUT_DIR..."
        swift build --package-path "$ROOT/Packages/VoxPresentation" --product VoxTodoPreviewHost
        BIN_PATH="$(swift build --package-path "$ROOT/Packages/VoxPresentation" --product VoxTodoPreviewHost --show-bin-path)/VoxTodoPreviewHost"
        "$BIN_PATH" --export-frames-only "$OUT_DIR"
        for v in v01 v02 v03 v04; do
            for m in dark light; do
                "$BIN_PATH" --encode-single-video "$OUT_DIR" "$v" "$m"
            done
        done
        exit 0
        ;;
    --snapshot)
        OUT_FILE="${2:?--snapshot requires an output PNG file}"
        swift run --package-path "$ROOT/Packages/VoxPresentation" VoxTodoPreviewHost --snapshot-board "$OUT_FILE"
        exit 0
        ;;
esac

echo "[open-local-preview] Building VoxTodoPreviewHost (Packages/VoxPresentation)..."
swift build --package-path "$ROOT/Packages/VoxPresentation" --product VoxTodoPreviewHost

BIN_PATH="$(swift build --package-path "$ROOT/Packages/VoxPresentation" --product VoxTodoPreviewHost --show-bin-path)/VoxTodoPreviewHost"
echo "[open-local-preview] Launching $BIN_PATH to foreground..."
nohup "$BIN_PATH" >/tmp/vox-todo-preview-host.log 2>&1 &
PREVIEW_PID=$!
echo "$PREVIEW_PID" >/tmp/vox-todo-preview-host.pid
echo "[open-local-preview] VoxTodoPreviewHost running (PID=$PREVIEW_PID)"

# Quick Recording Live Text Design

## Goal

在长按触发的 quick recording panel 中展示实时转写文字，并在文字过长时保持最新内容可见，左侧旧内容以渐出方式被裁切，且不改变当前 panel 尺寸。

## Context

- 当前 quick recording panel 由 `QuickRecordingView` 渲染，视觉上是一个固定尺寸的胶囊。
- `QuickRecordingViewModel` 已经提供 `liveTranscription`，并且在录音、转写、优化阶段维护实时文字状态。
- 现有 panel 只渲染背景氛围，没有文字层。

## Requirements

1. 长按开始录音后，panel 内显示实时转写内容。
2. 文本必须保持单行，不允许撑大 panel，也不调整窗口尺寸。
3. 文本超出可见宽度时，最新文字固定保持在右侧可见。
4. 被裁掉的左侧旧文字需要有渐出效果，而不是硬截断。
5. 松手后进入 `transcribing` / `refining` 时，继续显示最后一版实时转写，直到 panel 结束。
6. `idle`、`done`、`error` 等无展示必要的状态不显示文字。

## Chosen Approach

采用固定尺寸单行文本层叠加到现有胶囊背景上：

- 文本使用单行、尾部对齐布局，确保最新内容始终在右侧。
- 文本容器使用固定宽度并裁切溢出内容。
- 在文本层上应用左侧渐隐 mask，让旧内容从左边界淡出。
- 保留现有 `QuickRecordingLayout` 尺寸，必要时仅补充内部 padding 常量。

## Alternatives Considered

### Horizontal scroll

使用横向滚动容器并自动滚到尾部。问题是频繁更新时更容易出现跳动和同步问题，收益低于复杂度。

### Manual text slicing

通过宽度测量手动裁切前缀，仅渲染尾部子串。可控性高，但实现复杂且维护成本过高，不适合当前需求。

## Impacted Files

- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingView.swift`
- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingLayout.swift`
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingLayoutTests.swift`
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingViewModelTests.swift`

## Testing Strategy

- 修正 layout 常量测试，使测试与现有紧凑尺寸一致。
- 为 `QuickRecordingViewModel` 增加行为测试，确认 `liveTranscription` 在停止录音后仍保留最后一次实时内容，供 `transcribing` / `refining` 阶段显示。
- 通过 `swift test --package-path Packages/VoxPresentation` 进行验证。

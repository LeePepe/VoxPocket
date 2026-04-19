# Research Brief: Streaming Long-Text Input Feature

## Feature Goal
支持长文本/流式输入模式：
1. 转录器持续提交语音片段（chunks）给分析层
2. 分析（LLM refinement）对每个提交的片段进行增量优化
3. 结果直接推送到剪贴板和输入框
4. 输入框支持"整体替换"——只替换语音输入的部分，保留手动输入的内容

## Current Architecture

### Layer Stack
VoxDomain → VoxInfrastructure → VoxApplication → VoxPresentation

### Key Files
- `Packages/VoxApplication/Sources/UseCases/DefaultTranscriptionUseCase.swift`
  - `liveTextPublisher`: 实时转录（Apple Speech 连续输出）
  - `finalResultPublisher`: 稳定的最终结果（stop后emit一次）
  - `commitCurrentTranscription()`: 手动提交当前 liveText 到 EditingUseCase
  - `clearLiveText()`: 清空实时转录状态

- `Packages/VoxApplication/Sources/UseCases/DefaultRefinementUseCase.swift`
  - `refineStreaming()`: 对 editingUseCase.currentText 做流式优化
  - 当前模式：必须先 stop → commit → refine（串行）

- `Packages/VoxApplication/Sources/UseCases/EditingUseCase.swift`
  - `replaceAll(with:)`: 替换全部
  - `append(_:)`: 追加
  - `applyEdit(range:newText:)`: 范围替换
  - 无区分"语音区域"和"手动区域"的概念

- `Packages/VoxApplication/Sources/UseCases/RefinementUseCase.swift`
  - `RefinementEvent`: `.state` | `.chunk(String)`
  - `.chunk` 是累积的完整文本，直接覆盖

- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift`
  - 完整 Quick 流程：record→transcribe→refine→clipboard+paste→complete
  - 使用 `makeFinalResultWaitTask(timeout:15s)` 等待 finalResult

- `Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift`
  - 续写模式支持：`isAppendMode = !text.isEmpty` → `append("\n" + newText)`
  - 自动2.5s静默停止
  - 停止后一次性 `autoRefine()`

### Current Flow (Quick Recording)
1. startRecording → liveText stream builds up
2. stopRecording → waitForFinalResult (15s timeout) → rawTranscription
3. commitCurrentTranscription → editingUseCase has text
4. refineStreaming → LLM chunks → complete text
5. clipboard.copy + simulatePaste → onComplete → window hides

### Current Flow (Editor)
1. startRecording → liveText updates → scheduleAutoStop (2.5s silence)
2. stopRecording → append/replaceAll → rawTranscription
3. autoRefine → refineStreaming → editingUseCase.replaceAll

## Key Gaps for Streaming Long-Text

### Gap 1: No "voice region" tracking
- EditingUseCase has no concept of "voice-input range" vs "user-typed range"
- `replaceAll` blindly replaces everything
- Need: track where voice text starts/ends to replace only that region

### Gap 2: No continuous chunk-based refinement
- Current: refine fires ONCE after full stop
- Need: as liveText grows significantly, trigger incremental refinement
  - Option A: Timer-based (every N seconds of new content)
  - Option B: Word-count threshold (every K words)
  - Option C: Pause-based (silence gap triggers partial refine)

### Gap 3: No streaming paste integration
- Current: clipboard+paste happens only at end (Quick flow)
- Need: intermediate results pushed to clipboard/input field progressively

### Gap 4: Quick flow is fully sequential stop→refine
- No path for streaming intermediate refined output while still recording

## Implementation Strategy

### Core Concept: "Streaming Refinement with Voice Range Tracking"

**Phase 1 - Voice Region Anchor (VoxDomain/VoxApplication)**
- Add `voiceRange: NSRange?` to EditingUseCase or as a separate tracking struct
- When voice transcription updates → track [voiceStart, voiceEnd) in the text
- `replaceVoiceRange(with:)` → replaces only the tracked voice region

**Phase 2 - Chunked Transcription Submission (VoxApplication)**
- Add `chunkSubmissionInterval` (e.g., 5s or 100 chars) to TranscriptionUseCase
- New protocol method: `streamingChunkPublisher: AnyPublisher<String, Never>`
- Periodically emit stable portions of liveText as committed chunks

**Phase 3 - Incremental Refinement (VoxApplication)**
- New use case or extension: `IncrementalRefinementUseCase`
- Or: add `refineStreamingIncremental(chunk:)` to RefinementUseCase
- Each chunk → LLM call → output appended/replaced in voice region

**Phase 4 - Streaming Output (VoxPresentation)**
- EditorViewModel: during recording, periodically trigger chunk refinement
- QuickRecordingViewModel: support progressive clipboard updates
- Visual feedback: show "processing..." indicator for in-flight chunks

## Simplest Viable Approach (MVP)

Given complexity, recommend MVP:

1. **VoiceRangeTracking in DefaultEditingUseCase**
   - Add `voiceInsertionStart: Int` property (position where voice text begins)
   - Add `replaceVoiceContent(with:)` → replace from voiceInsertionStart to end

2. **Periodic Chunk Submission**
   - In EditorViewModel: detect when liveTranscription gains >50 chars since last submit
   - Submit chunk to editingUseCase, trigger refineStreaming on chunk
   - Replace voice region with refined result

3. **Quick Recording: streaming intermediate output**
   - During recording, every 5s of liveText growth → interim refine → clipboard copy
   - On stop → final refine → clipboard + paste


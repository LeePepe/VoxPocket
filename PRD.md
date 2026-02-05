Voice-to-Text App – Production Requirements Document (PRD)

1. Product Overview

1.1 Background

Voice input is one of the fastest ways to capture ideas, but speech-to-text tools often fail once users need to revise, refine, or revisit earlier content. Traditional voice transcription treats text as disposable output rather than an evolving artifact.

This product treats voice-generated text as a first-class, voice-driven artifact with predictable history, reversible changes, and professional-grade undo/redo behavior—without manual text editing.

1.2 Problem Statement
	•	Voice transcription results are often hard to revise reliably
	•	Users want to correct or refine output without manual editing
	•	Undo/redo behavior is inconsistent or unavailable
	•	AI-based refinements often overwrite user intent and cannot be reverted

1.3 Target Users
	•	Knowledge workers capturing thoughts via voice
	•	Developers, writers, and product managers
	•	Users who want a hands-free, voice-only workflow
	•	macOS power users who want to inject text into any focused input field

1.4 Value Proposition

A cross-platform Voice-to-Text workflow that:
	•	Converts speech into text incrementally
	•	Treats every change as reversible
	•	Allows users to confidently correct and refine by voice
	•	Maintains trust through deterministic undo/redo

⸻

2. Core Features

2.1 Voice Input & Transcription
	•	Real-time speech-to-text with streaming partial results
	•	Finalized transcription segments committed as stable text
	•	Clear separation between temporary (partial) and historical (final) text

2.2 Undo / Redo
	•	Linear undo/redo model similar to professional editors
	•	Works across:
	•	Voice transcription results
	•	Voice-based corrections and rewrite instructions
	•	AI-generated refinements
	•	Users can move backward and forward through text history predictably

2.3 LLM-based Refinement
	•	Optional AI-powered text optimization (rewrite, polish, summarize)
	•	Multiple model providers supported
	•	AI output is always committed as reversible changes (never destructive)
	•	No manual text editing; corrections and rewrites are issued via voice

2.4 Cross-Platform Support
	•	Shared SwiftUI codebase for iOS and macOS
	•	macOS menu bar integration
	•	macOS support for inserting text into the currently focused editable field
	•	Widgets for one-tap voice input

2.5 iCloud Sync
	•	Automatic sync of documents and text history across all user devices
	•	CloudKit-based synchronization for reliability and privacy
	•	Conflict resolution strategy:
	•	Last-write-wins for simple text changes
	•	Merge-based resolution for concurrent edits when possible
	•	Offline support with automatic sync when connectivity is restored
	•	Sync scope includes:
	•	Text documents and sessions
	•	Undo/redo history (patches and checkpoints)
	•	User preferences and settings
	•	Sync status indicator in UI for transparency

2.6 Snackbar 通知系统
	•	轻量级、非阻塞式的用户反馈机制
	•	应用场景：
	•	操作成功反馈（如：文本已复制、Session 已保存）
	•	操作失败提示（如：网络错误、权限不足）
	•	状态变更通知（如：同步完成、录音已停止）
	•	系统提示（如：新功能提示、版本更新）
	•	设计原则：
	•	非阻塞：不中断用户当前操作
	•	自动消失：默认 3 秒后自动隐藏
	•	可交互：支持可选的操作按钮（如：重试、撤销）
	•	队列管理：多条通知按优先级排队显示
	•	通知类型：
	•	info：普通信息提示
	•	success：操作成功
	•	warning：警告提示
	•	error：错误提示
	•	优先级支持：
	•	low：普通通知，排队等待
	•	normal：默认优先级
	•	high：紧急通知，可打断当前显示

⸻

3. Text History & Undo/Redo Model

3.1 Design Principles
	•	Text history is append-only and linear
	•	No branching or hidden state
	•	Every change is explicit and reversible

3.2 Delta / Patch-Based History
	•	Text changes are represented as deltas (patches) instead of full text replacements
	•	Each patch:
	•	Can be applied to produce a new state
	•	Can be inverted to undo its effect
	•	Undo = apply inverted patch
	•	Redo = re-apply patch

3.3 Change Sources (Unified)

All of the following generate patches and enter the same history:
	•	Finalized voice transcription segments
	•	Voice-based corrections / rewrite instructions
	•	LLM refinements

This ensures consistent behavior regardless of how text changes.

3.4 Checkpoints
	•	Periodic full-text snapshots (checkpoints) are stored
	•	Used to:
	•	Limit patch chain length
	•	Enable fast recovery
	•	Guarantee determinism

⸻

4. Platform Capabilities

4.1 iOS
	•	Voice recording and transcription
	•	Voice-based correction and history navigation
	•	Widgets for quick input

4.2 macOS
	•	Menu bar resident controls
	•	Global hotkeys (optional)
	•	Text injection into focused input fields:
	•	Primary: system paste
	•	Optional: Accessibility APIs (with explicit user permission)

Accessibility APIs are optional and must be clearly disclosed to users.

⸻

5. Technical Architecture

5.1 Architectural Goals
	•	Clear separation of concerns
	•	Replaceable core algorithms
	•	High testability
	•	Strong observability
	•	Scalable text history for long sessions

5.2 High-Level Layers
	•	UI Layer (SwiftUI)
Views, widgets, menu bar UI
	•	Use Case Layer
Application orchestration (record, commit, refine, undo, redo)
	•	Domain Layer
Text history, patches, sessions, segments
	•	Infrastructure Layer
ASR, LLM providers, persistence, logging, platform APIs

⸻

6. Module Structure (Swift Package Manager)

6.1 App Targets
	•	VoiceToTextApp-iOS
	•	VoiceToTextApp-macOS

6.2 Core Packages
	•	CoreModels
Domain entities and invariants
	•	TextHistory
Patch-based undo/redo engine, checkpoints
	•	TranscriptionKit
Audio capture and speech-to-text abstraction
	•	LLMKit
AI model abstraction and refinement pipeline
	•	Persistence
SwiftData storage and migrations
	•	Observability
Logging and telemetry interfaces
	•	PlatformAdapters
iOS/macOS-specific capabilities
	•	UIShared
Shared SwiftUI components
	•	UseCases
Application orchestration layer
	•	CloudSync
iCloud/CloudKit synchronization, conflict resolution, offline queue

⸻

7. Dependency Graph

graph TD

A_iOS[VoiceToTextApp-iOS] --> UI[UIShared]
A_mac[VoiceToTextApp-macOS] --> UI
A_mac --> PM[PlatformAdapters]

UI --> UC[UseCases]

UC --> CM[CoreModels]
UC --> TH[TextHistory]
UC --> TK[TranscriptionKit]
UC --> LK[LLMKit]
UC --> PS[Persistence]
UC --> OB[Observability]
UC --> PM
UC --> CS[CloudSync]

CS --> CM
CS --> PS
CS --> OB

TH --> CM
TK --> CM
LK --> CM
PS --> CM
OB --> CM

PM --> CM
PM --> OB

⸻

8. Non-Goals
	•	Real-time multi-user collaboration
	•	Rich document formatting (tables, styles, layout)
	•	Version branching or Git-like history

⸻

9. Quality Attributes

9.1 Performance
	•	Low-latency transcription
	•	Fast undo/redo regardless of document length

9.2 Reliability
	•	Undo/redo must be deterministic and lossless
	•	Patch failures must be recoverable via checkpoints

9.3 Maintainability
	•	Algorithm implementations must be replaceable
	•	Clear package boundaries and test coverage

9.4 Privacy
	•	Voice data handled locally when possible
	•	Cloud / LLM usage is explicit and opt-in
	•	iCloud data encrypted in transit and at rest

9.5 Sync Reliability
	•	Graceful handling of network failures
	•	No data loss during sync conflicts
	•	Clear user feedback on sync status and errors

⸻

10. Future Considerations
	•	Advanced text analysis and summaries
	•	Alternative history visualizations
	•	Model-specific refinement presets
	•	Real-time collaborative editing (multi-user sync)

⸻

Summary

This application treats voice-generated text not as disposable output, but as an evolving, voice-driven artifact with professional-grade history management. By combining patch-based undo/redo, modular architecture, and cross-platform SwiftUI design, it enables users to confidently iterate on ideas using voice as a primary input method—without manual text editing.

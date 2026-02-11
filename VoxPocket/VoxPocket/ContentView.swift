//
//  ContentView.swift
//  VoxPocket
//
//  Created by 李天培 on 1/26/26.
//

import SwiftUI
import UIShared
import TranscriptionKit
import LLMKit
import UseCases
#if os(macOS)
import PlatformAdapters
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var rootViewModel: RootViewModel<SessionListViewModel, EditorViewModel>
    @StateObject private var snackbarService = DefaultSnackbarService()

    init() {
        let transcriber = AppleSpeechTranscriber()
        let editing = DefaultEditingUseCase()
        let recording = DefaultRecordingUseCase(coordinator: transcriber)
        let transcription = DefaultTranscriptionUseCase(coordinator: transcriber, editing: editing)
        let history = DefaultHistoryUseCase(editing: editing)

        // LLM 服务与优化用例
        let llmService = DefaultLLMService()
        let refinement = DefaultRefinementUseCase(llmService: llmService, editing: editing)

#if os(macOS)
        let clipboard: ClipboardService? = MacOSClipboardService.shared
#else
        let clipboard: ClipboardService? = nil
#endif
        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: editing,
            history: history,
            refinement: refinement,
            clipboard: clipboard
        )
        let sessionUseCase = InMemorySessionUseCase()
        let sessionList = SessionListViewModel(sessionUseCase: sessionUseCase)
        _rootViewModel = StateObject(wrappedValue: RootViewModel(
            sessionListState: sessionList,
            editorState: editor
        ))
    }

    var body: some View {
        VoxPocketRootView(
            viewModel: rootViewModel,
            onCopyRefined: { text in
                guard !text.isEmpty else { return }
#if os(macOS)
                MacOSClipboardService.shared.copy(text)
#elseif os(iOS)
                UIPasteboard.general.string = text
#endif
                snackbarService.showSuccess("已复制精炼文本")
            },
            onCopyRaw: { text in
                guard !text.isEmpty else { return }
#if os(macOS)
                MacOSClipboardService.shared.copy(text)
#elseif os(iOS)
                UIPasteboard.general.string = text
#endif
                snackbarService.showSuccess("已复制原始转写")
            }
        )
        .snackbarOverlay(service: snackbarService)
    }
}

#Preview {
    ContentView()
}

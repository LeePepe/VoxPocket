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
    @StateObject private var rootViewModel: RootViewModel<MockSessionListViewModel, EditorViewModel>

    init() {
        let transcriber = AppleSpeechTranscriber()
        let editing = DefaultEditingUseCase()
        let recording = DefaultRecordingUseCase(coordinator: transcriber)
        let transcription = DefaultTranscriptionUseCase(coordinator: transcriber, editing: editing)
        let history = DefaultHistoryUseCase()

        // LLM 服务与优化用例
        let llmService = DefaultLLMService()
        let refinement = DefaultRefinementUseCase(llmService: llmService, editing: editing)

        // 意图识别用例
        let intentRecognition = DefaultIntentRecognitionUseCase(
            llmService: llmService,
            editingUseCase: editing,
            isLLMEnhancementEnabled: true
        )

        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: editing,
            history: history,
            refinement: refinement
        )
        let sessionList = MockSessionListViewModel()
        _rootViewModel = StateObject(wrappedValue: RootViewModel(
            sessionListState: sessionList,
            editorState: editor
        ))
    }

    var body: some View {
        VoxPocketRootView(
            viewModel: rootViewModel,
            onCopyRefined: { text in
#if os(macOS)
                MacOSClipboardService.shared.copy(text)
#elseif os(iOS)
                UIPasteboard.general.string = text
#endif
            },
            onCopyRaw: { text in
#if os(macOS)
                MacOSClipboardService.shared.copy(text)
#elseif os(iOS)
                UIPasteboard.general.string = text
#endif
            }
        )
    }
}

#Preview {
    ContentView()
}

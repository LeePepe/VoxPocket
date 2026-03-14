//
//  ContentView.swift
//  VoxPocket
//
//  Created by 李天培 on 1/26/26.
//

import SwiftUI
import UIShared
import UseCases
import TranscriptionKit
import Combine
#if os(macOS)
import PlatformAdapters
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var rootViewModel: RootViewModel<SessionListViewModel, EditorViewModel>
    @StateObject private var snackbarService = DefaultSnackbarService()
    @StateObject private var localModelLoadingStatus: LocalModelLoadingStatus

    init() {
        let vm = ServiceContainer.shared.makeRootViewModel()
        _rootViewModel = StateObject(wrappedValue: vm)

        let status: LocalModelLoadingStatus
        if let observable = ServiceContainer.shared.localModelLoadingObservable {
            status = LocalModelLoadingStatus(observable: observable)
        } else {
            // 非本地模型（Apple Speech 等）不展示加载状态
            final class NeverLoadingObservable: ModelLoadingObservable {
                var modelLoadingState: ModelLoadingState { .idle }
                var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
                    Just(.idle).eraseToAnyPublisher()
                }
            }
            status = LocalModelLoadingStatus(observable: NeverLoadingObservable())
        }
        _localModelLoadingStatus = StateObject(wrappedValue: status)
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
            },
            localModelLoadingStatus: localModelLoadingStatus
        )
        .snackbarOverlay(service: snackbarService)
        .task {
            // 延迟初始化 SwiftData，避免在 App init 阶段创建 ModelContainer 阻塞 UI
            await ServiceContainer.shared.initializePersistence()
        }
        .onAppear {
            // 注入 snackbar 到 EditorViewModel，使录音被阻止时能显示提示
            rootViewModel.editorState.snackbarService = snackbarService
        }
    }
}

#Preview {
    ContentView()
}

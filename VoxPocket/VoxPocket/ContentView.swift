//
//  ContentView.swift
//  VoxPocket
//
//  Created by 李天培 on 1/26/26.
//

import SwiftUI
import UIShared
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
        let vm = ServiceContainer.shared.makeRootViewModel()
        _rootViewModel = StateObject(wrappedValue: vm)
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

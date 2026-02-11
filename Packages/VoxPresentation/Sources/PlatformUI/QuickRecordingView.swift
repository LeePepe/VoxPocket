#if os(macOS)
import SwiftUI
import UIShared

/// Quick recording pill.
public struct QuickRecordingView: View {
    @ObservedObject var viewModel: QuickRecordingViewModel

    public init(viewModel: QuickRecordingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            BackgroundAtmosphere(status: viewModel.recorderStatus)
        }
        .frame(width: QuickRecordingLayout.pillWidth, height: QuickRecordingLayout.pillHeight)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}
#endif

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
        .background(
            Capsule()
                .fill(Color.black.opacity(0.25))
                .blur(radius: 8)
                .offset(y: 4)
        )
    }
}
#endif

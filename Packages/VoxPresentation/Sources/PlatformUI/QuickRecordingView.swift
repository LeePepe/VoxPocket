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
            if viewModel.showsLiveTranscription {
                liveTranscriptionOverlay
            }
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

    private var liveTranscriptionOverlay: some View {
        Text(viewModel.liveTranscription)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(1)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, QuickRecordingLayout.textHorizontalInset)
            .compositingGroup()
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: QuickRecordingLayout.textLeftFadeWidth)

                    Rectangle()
                        .fill(.black)
                }
            }
    }
}
#endif

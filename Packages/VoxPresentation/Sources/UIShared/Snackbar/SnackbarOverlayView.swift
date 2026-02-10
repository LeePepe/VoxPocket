import SwiftUI

/// 全局 Snackbar 弹窗覆盖层
///
/// 在视图层级顶部显示 Snackbar 通知，带有滑入/滑出动画。
/// 用法：在根视图上添加 `.snackbarOverlay(service:)`。
public struct SnackbarOverlayView: View {
    @ObservedObject var service: DefaultSnackbarService

    public init(service: DefaultSnackbarService) {
        self.service = service
    }

    public var body: some View {
        VStack {
            if let message = service.currentMessage {
                SnackbarBannerView(message: message) {
                    service.dismiss(messageId: message.id)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.currentMessage?.id)
    }
}

// MARK: - Banner 单条通知视图

struct SnackbarBannerView: View {
    let message: SnackbarMessage
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var iconName: String {
        switch message.type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var accentColor: Color {
        switch message.type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
                .font(.system(size: 16, weight: .semibold))

            Text(message.message)
                .font(FontToken.callout)
                .foregroundColor(.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if let action = message.action {
                Button(action.title) {
                    action.handler()
                    onDismiss()
                }
                .font(FontToken.callout)
                .foregroundColor(.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GlassCardBackground(cornerRadius: 16, strength: 0.22))
    }
}

// MARK: - View Modifier

public extension View {
    /// 添加 Snackbar 覆盖层
    func snackbarOverlay(service: DefaultSnackbarService) -> some View {
        overlay(alignment: .top) {
            SnackbarOverlayView(service: service)
        }
    }
}

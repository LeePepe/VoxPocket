import SwiftUI

extension View {
    func foregroundColor(_ token: ColorToken) -> some View {
        modifier(ThemedForegroundModifier(token: token))
    }

    func font(_ token: FontToken) -> some View {
        modifier(ThemedFontModifier(token: token))
    }
}

private struct ThemedForegroundModifier: ViewModifier {
    let token: ColorToken
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.foregroundColor(theme.palette.resolve(token))
    }
}

private struct ThemedFontModifier: ViewModifier {
    let token: FontToken
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.font(theme.typography.resolve(token))
    }
}

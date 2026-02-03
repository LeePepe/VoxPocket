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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = Theme.current(colorScheme)
        return content.foregroundColor(theme.palette.resolve(token))
    }
}

private struct ThemedFontModifier: ViewModifier {
    let token: FontToken
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = Theme.current(colorScheme)
        return content.font(theme.typography.resolve(token))
    }
}

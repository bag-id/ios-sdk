import BagIdSDK
import SwiftUI
import UIKit

struct ManagedBleFlowTheme {
    let primary: Color
    let background: Color
    let text: Color
    let onPrimary: Color
    let error: Color
    let surface: Color
    let cardBackground: Color
    let onLight: Color
    let borderRadius: CGFloat
    let paddingSmall: CGFloat
    let paddingMedium: CGFloat
    let paddingLarge: CGFloat
    let titleSize: CGFloat
    let titleWeight: Font.Weight
    let bodySize: CGFloat
    let bodyWeight: Font.Weight
    let captionSize: CGFloat
    let captionWeight: Font.Weight
    let fontName: String?
    let buttonHeight: CGFloat?
    let buttonStyle: ButtonStyle
    let inputStyle: InputStyle
    let iosLogo: String?

    enum ButtonStyle {
        case filled, outlined, text
    }

    enum InputStyle {
        case outlined, filled, underlined
    }

    /// Frozen snapshot for the screen that is about to appear. Does not track later OS flips.
    static func snapshot() -> ManagedBleFlowTheme {
        let value = resolve()
        frozen = value
        return value
    }

    /// Last snapshot taken at screen launch. Builds one if none exists yet.
    static var current: ManagedBleFlowTheme { frozen ?? snapshot() }

    private static var frozen: ManagedBleFlowTheme?

    private static func resolve() -> ManagedBleFlowTheme {
        let merged = BagIdSdk.shared.configuredTheme
        let dark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        let palette = dark ? merged?.dark : merged?.light
        let primaryHex = palette?.primaryColor ?? merged?.primaryColor
        let backgroundHex = palette?.backgroundColor ?? merged?.backgroundColor
        let textHex = palette?.textColor ?? merged?.textColor
        let onPrimaryHex = palette?.onPrimaryColor ?? merged?.onPrimaryColor
        let errorHex = palette?.errorColor ?? merged?.errorColor
        let surfaceHex = palette?.surface ?? merged?.surface
        let cardHex = palette?.cardBackground ?? merged?.cardBackground
        let text = Color(bagIdHex: textHex) ?? .white
        let background = Color(bagIdHex: backgroundHex) ?? Color(red: 27 / 255, green: 49 / 255, blue: 45 / 255)
        return ManagedBleFlowTheme(
            primary: Color(bagIdHex: primaryHex) ?? Color(red: 88 / 255, green: 188 / 255, blue: 173 / 255),
            background: background,
            text: text,
            onPrimary: Color(bagIdHex: onPrimaryHex) ?? Color(red: 0 / 255, green: 22 / 255, blue: 36 / 255),
            error: Color(bagIdHex: errorHex) ?? .red,
            surface: Color(bagIdHex: surfaceHex) ?? Color(red: 250 / 255, green: 247 / 255, blue: 243 / 255),
            cardBackground: Color(bagIdHex: cardHex) ?? .white,
            onLight: text.isVisuallyLight ? background : text,
            borderRadius: Self.cg(merged?.borderRadius) ?? 10,
            paddingSmall: Self.cg(merged?.paddingSmall) ?? 8,
            paddingMedium: Self.cg(merged?.paddingMedium) ?? 16,
            paddingLarge: Self.cg(merged?.paddingLarge) ?? 20,
            titleSize: Self.cg(merged?.titleSize) ?? 22,
            titleWeight: (merged?.titleWeight).map(Self.fontWeight) ?? .semibold,
            bodySize: Self.cg(merged?.bodySize) ?? 16,
            bodyWeight: (merged?.bodyWeight).map(Self.fontWeight) ?? .regular,
            captionSize: Self.cg(merged?.captionSize) ?? 13,
            captionWeight: (merged?.captionWeight).map(Self.fontWeight) ?? .regular,
            fontName: merged?.fontFamily,
            buttonHeight: Self.cg(merged?.buttonHeight),
            buttonStyle: Self.buttonStyle(merged?.buttonStyle),
            inputStyle: Self.inputStyle(merged?.inputStyle),
            iosLogo: merged?.iosLogo
        )
    }

    func titleFont() -> Font { themedFont(size: titleSize, weight: titleWeight, relativeTo: .title) }
    func bodyFont() -> Font { themedFont(size: bodySize, weight: bodyWeight, relativeTo: .body) }
    func captionFont() -> Font { themedFont(size: captionSize, weight: captionWeight, relativeTo: .caption) }

    func primaryButtonHeight() -> CGFloat {
        let visual = buttonHeight ?? UIScreen.main.bounds.height * 0.075
        return max(visual, 44)
    }

    func themedFont(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(style))
        let scaled = metrics.scaledValue(for: size)
        if let fontName, UIFont(name: fontName, size: scaled) != nil {
            return Font.custom(fontName, size: scaled, relativeTo: style)
        }
        return Font.system(size: scaled, weight: weight)
    }

    @ViewBuilder
    func hostLogo() -> some View {
        if let iosLogo, let image = UIImage(named: iosLogo, in: .main, compatibleWith: nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 36)
        }
    }

    private static func cg(_ value: Any?) -> CGFloat? {
        (value as? NSNumber).map { CGFloat(truncating: $0) }
    }

    private static func fontWeight(_ weight: ThemeFontWeight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        default: return .regular
        }
    }

    private static func buttonStyle(_ style: BagIdSDK.ButtonStyle?) -> ButtonStyle {
        switch style {
        case .outlined: return .outlined
        case .text: return .text
        default: return .filled
        }
    }

    private static func inputStyle(_ style: BagIdSDK.InputStyle?) -> InputStyle {
        switch style {
        case .filled: return .filled
        case .underlined: return .underlined
        default: return .outlined
        }
    }

    private func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .title: return .title1
        case .caption: return .caption1
        default: return .body
        }
    }
}

extension Color {
    fileprivate init?(bagIdHex: String?) {
        guard var raw = bagIdHex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") { raw.removeFirst(2) }
        guard raw.count == 6 || raw.count == 8, let value = UInt64(raw, radix: 16) else {
            return nil
        }
        if raw.count == 6 {
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            self.init(red: r, green: g, blue: b)
        } else {
            let a = Double((value >> 24) & 0xFF) / 255
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        }
    }

    fileprivate var isVisuallyLight: Bool {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }
}

struct BagIdThemedPrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let theme: ManagedBleFlowTheme
    let action: () -> Void

    var body: some View {
        let height = theme.primaryButtonHeight()
        Button(action: action) {
            Text(title)
                .font(theme.titleFont())
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: theme.borderRadius))
                .overlay {
                    if theme.buttonStyle == .outlined {
                        RoundedRectangle(cornerRadius: theme.borderRadius)
                            .stroke(theme.primary, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .padding(.horizontal, theme.paddingLarge)
        .padding(.bottom, 12)
    }

    private var foreground: Color {
        switch theme.buttonStyle {
        case .filled: return theme.onPrimary
        case .outlined, .text: return theme.primary
        }
    }

    private var background: Color {
        switch theme.buttonStyle {
        case .filled: return theme.primary
        case .outlined, .text: return .clear
        }
    }
}

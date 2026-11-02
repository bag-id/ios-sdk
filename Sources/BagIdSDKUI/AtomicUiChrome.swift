import BagIdSDK
import SwiftUI

enum AtomicUiCopy {
    static let selectTitle = "Choose your type of\ndevice to continue"
    static let bagIdName = "BagID"
    static let otherName = "Other"

    static let serviceTitle = "Check in baggage digitally\nwith your Electronic Bag Tag"
    static let serviceBody =
        "Baggage check-in and electronic bag tag transfer is provided by BagID on behalf of your airline. " +
        "We process your journey and baggage data to generate and transfer your bag tag."
    static let serviceAcceptPrefix = "By continuing, you accept our Terms of Use and "
    static let servicePolicy = "Privacy and Data Policy"
    static let servicePolicyUrl = "https://www.bagid.com/privacy"
    static let serviceContinue = "Continue"

    static let prepareTitle = "Press the left button on your BagID to activate Bluetooth."
    static let prepareContinue = "Scan for device"
    static let prepareSkip = "Don't show this again"
    static let prepareNeedHelp = "Need help with your tag?"
    static let prepareHelpSubtitle = "BagID setup guide"
    static let helpGotIt = "Got it"

    static func displayName(_ type: AtomicTagType) -> String {
        type == .bagid ? bagIdName : otherName
    }

    static func helpSteps(_ type: AtomicTagType) -> [String] {
        if type == .bagid {
            return [
                "Make sure your tag is charged — connect it with the USB cable if the battery is low.",
                "If pairing mode doesn't start, hold the button for 5 seconds and try again.",
                "Move closer to your tag and ensure no other phone is connected to it.",
            ]
        }
        return [
            "Check that the power switch is fully in the ON position.",
            "If the LED doesn't blink, press and hold the pairing button for 8 seconds.",
            "Move closer to your tag and ensure Bluetooth is enabled on your phone.",
        ]
    }
}

struct AtomicUiCloseBar: View {
    let onLight: Bool
    let onClose: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(onLight ? MapFlowTheme.onLight : Color.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .showAfter15s()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct ShowAfter15s: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                shown = true
            }
    }
}

extension View {
    func showAfter15s() -> some View {
        modifier(ShowAfter15s())
    }
}

struct AtomicUiBottomButton: View {
    let title: String
    var disabled: Bool = false
    let theme: ManagedBleFlowTheme
    let action: () -> Void

    var body: some View {
        BagIdThemedPrimaryButton(title: title, disabled: disabled, theme: theme, action: action)
    }
}

/// Same ring as SHOW_MAP loading. Used between atomic sections and managed BLE wait states.
struct AtomicUiRingSpinner: View {
    var showsCheckmark: Bool = false
    var size: CGFloat = 88
    var lineWidth: CGFloat = 6
    @State private var rotating = false

    var body: some View {
        let color = MapFlowTheme.accent
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            if showsCheckmark {
                Circle()
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .trim(from: 0.08, to: 0.42)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(rotating ? 360 : 0))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !showsCheckmark else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }
}

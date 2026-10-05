import SwiftUI

enum ManagedBleTrackingCopy {
    static let ctaTitle = "Your bag is ready to be tracked"
    static let ctaBody =
        "Turn on tracking to follow your bag in real-time, from check-in to arrival, together with your airline."
    static let start = "Start tracking"
    static let notNow = "Not Now"
    static let consentTitle = "Enable Journey Tracking?"
    static let consentBody = "You can share your baggage's location with the airline during this journey."
    static let item1Title = "Airlines can help you locate your bag"
    static let item1Body =
        "The location is shared with your airline and will only be used for its purpose to ensure that your bag arrives together with you."
    static let item2Title = "Tracking Duration"
    static let item2Body =
        "If activated, your bag becomes traceable 2 hours before departure and 7 days after arrival, or until you remove the tag from the BagID."
    static let item3Title = "You're in Control"
    static let item3Body = "You can stop location sharing with immediate effect anytime during your journey."
    static let item4Title = "Tracking Network"
    static let item4Body =
        "For your airline to see your bag's location, we need to switch to the airline's network. Your private network pauses, but resumes automatically after the journey ends."
    static let check1 = "I've read and understood how tracking works"
    static let check2 = "I consent to this bag being tracked for this trip"
    static let enable = "Enable Tracking"
    static let setupTitle = "Setting up tracking"
     static let setupBody =
        "Keep your BagID nearby. This may take a few seconds."
    static let setupFinalizing = "Finalizing …"
    static let failedTitle = "Enable Tracking Failed"
    static let retry = "Retry"
    static let close = "Close"
}

struct ManagedBleTrackingCtaView: View {
    let theme: ManagedBleFlowTheme
    let onStart: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            ManagedBleTrackingSignalIcon(style: .orange)
            Text(ManagedBleTrackingCopy.ctaTitle)
                .font(.title2)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image("TrackingMapMock", bundle: .module)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            Text(ManagedBleTrackingCopy.ctaBody)
                .font(.title3)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 8)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                ManagedBleOutlineButton(title: ManagedBleTrackingCopy.notNow, action: onNotNow)
                AtomicUiBottomButton(title: ManagedBleTrackingCopy.start, theme: theme, action: onStart)
            }
        }
    }
}

struct ManagedBleTrackingConsentView: View {
    let theme: ManagedBleFlowTheme
    let onEnable: () -> Void
    let onDecline: () -> Void
    @State private var check1 = false
    @State private var check2 = false

    private var canEnable: Bool { check1 && check2 }

    private let items: [(icon: String, title: String, body: String)] = [
        ("airplane", ManagedBleTrackingCopy.item1Title, ManagedBleTrackingCopy.item1Body),
        ("clock", ManagedBleTrackingCopy.item2Title, ManagedBleTrackingCopy.item2Body),
        ("person.crop.circle.badge.checkmark", ManagedBleTrackingCopy.item3Title, ManagedBleTrackingCopy.item3Body),
        ("point.3.connected.trianglepath.dotted", ManagedBleTrackingCopy.item4Title, ManagedBleTrackingCopy.item4Body),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    ManagedBleTrackingSignalIcon(style: .teal)
                        .padding(.top, 12)
                    VStack(spacing: 8) {
                        Text(ManagedBleTrackingCopy.consentTitle)
                            .font(.title2.bold())
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                        Text(ManagedBleTrackingCopy.consentBody)
                            .font(.subheadline)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(items, id: \.title) { item in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 0.94))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: item.icon)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color(red: 20 / 255, green: 97 / 255, blue: 109 / 255))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.black)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item.body)
                                        .font(.caption)
                                        .foregroundStyle(.black.opacity(0.55))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        checkbox(ManagedBleTrackingCopy.check1, checked: $check1)
                        checkbox(ManagedBleTrackingCopy.check2, checked: $check2)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                ManagedBleOutlineButton(title: ManagedBleTrackingCopy.notNow, action: onDecline)
                AtomicUiBottomButton(
                    title: ManagedBleTrackingCopy.enable,
                    disabled: !canEnable,
                    theme: theme,
                    action: onEnable
                )
            }
        }
    }

    private func checkbox(_ label: String, checked: Binding<Bool>) -> some View {
        Button { checked.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(checked.wrappedValue ? MapFlowTheme.accent : Color.clear)
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            checked.wrappedValue ? MapFlowTheme.accent : MapFlowTheme.onLight.opacity(0.4),
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)
                    if checked.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 20, height: 20)
                .padding(.top, 1)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ManagedBleTrackingSetupView: View {
    let onCancel: () -> Void
    @State private var progress: Double = 0.02

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer()
                Text(ManagedBleTrackingCopy.setupTitle)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                Text(ManagedBleTrackingCopy.setupBody)
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 8)
                        Capsule()
                            .fill(MapFlowTheme.accent)
                            .frame(width: max(16, geo.size.width * progress), height: 8)
                        Circle()
                            .fill(MapFlowTheme.accent)
                            .frame(width: 14, height: 14)
                            .offset(x: max(0, geo.size.width * progress - 7))
                    }
                }
                .frame(height: 14)
                .padding(.horizontal, 32)
                Text(ManagedBleTrackingCopy.setupFinalizing)
                    .font(.footnote.italic())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
                Spacer()
            }
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ManagedBleFlowTheme.current.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 28)) { progress = 0.92 }
        }
    }
}

struct ManagedBleTrackingFailedView: View {
    let theme: ManagedBleFlowTheme
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(ManagedBleTrackingCopy.failedTitle)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: onClose) {
                    Text(ManagedBleTrackingCopy.close)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                AtomicUiBottomButton(title: ManagedBleTrackingCopy.retry, theme: theme, action: onRetry)
            }
            .padding(.bottom, 12)
        }
    }
}

struct ManagedBleTrackingSignalIcon: View {
    enum Style { case orange, teal }
    var style: Style = .orange

    var body: some View {
        let fill = style == .orange
            ? MapFlowTheme.accent.opacity(0.08)
            : Color(red: 20 / 255, green: 97 / 255, blue: 109 / 255).opacity(0.10)
        let iconColor = style == .orange
            ? MapFlowTheme.accent
            : Color(red: 20 / 255, green: 97 / 255, blue: 109 / 255)
        ZStack {
            Circle().fill(fill)
            Image(systemName: "location.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: 72, height: 72)
    }
}

import BagIdSDK
import SwiftUI

enum ManagedBleCopy {
    static let searchingTitle = "Searching for device"
    static let searchingHint = "Ensure that the blue light on your device is still blinking"
    static let foundTitle = "We found the following device(s)"
    static let foundSubtitle = "Choose your BagID device to continue"
    static let connect = "Connect"
    static let searchAgain = "Search again"
    static let transferringTitle = "Working on it"
    static let transferringHint = "This may take a few seconds"
    static let successTitle = "Tag successfully transferred"
    static let next = "Next"
    static let bagIdTitle = "BagID 2"
    static let bagIdModel = "BagID 2 for Apple"
    static let otherTitle = "BagTag Flex"
    static let otherModel = "BagTag Flex"
}

struct ManagedBleSearchingView: View {
    var body: some View {
        VStack(spacing: 20) {
            AtomicUiRingSpinner()
            Text(ManagedBleCopy.searchingTitle)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(ManagedBleCopy.searchingHint)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ManagedBleWorkingView: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 20) {
            AtomicUiRingSpinner()
            Text(title)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(hint)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ManagedBleSuccessView: View {
    var body: some View {
        VStack(spacing: 20) {
            AtomicUiRingSpinner(showsCheckmark: true)
            Text(ManagedBleCopy.successTitle)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ManagedBleFoundDeviceCard: View {
    let title: String
    let modelLine: String
    var isSelected: Bool = false
    var isOther: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(isOther
                    ? Color(red: 0.72, green: 0.78, blue: 0.80)
                    : Color(red: 1, green: 0.93, blue: 0.82))
                Image(isOther ? "TagTypeOther" : "TagTypeBagId", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                Text(modelLine)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? MapFlowTheme.accent : Color.white,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.clear : Color.black.opacity(0.14), lineWidth: 1)
        )
    }
}

/// Secondary action (Back / Not Now / Cancel / Close). Same height, radius and inset as
/// [BagIdThemedPrimaryButton]; opaque so scrolled content never shows through it.
struct ManagedBleOutlineButton: View {
    let title: String
    var onDark: Bool = false
    var theme: ManagedBleFlowTheme = .current
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.borderRadius)
        let foreground = onDark ? Color.white : MapFlowTheme.onLight
        Button(action: action) {
            Text(title)
                .font(theme.themedFont(size: theme.bodySize + 2, weight: .regular, relativeTo: .body))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: theme.primaryButtonHeight())
                .background(onDark ? theme.background : Color.white, in: shape)
                .overlay(shape.stroke(foreground.opacity(onDark ? 0.7 : 0.35), lineWidth: 1.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.paddingLarge)
    }
}

/// Opaque bottom action bar for `safeAreaInset(edge: .bottom)` — content scrolling underneath
/// stays hidden behind it, with a hairline separating the two.
struct ManagedBleBottomBar<Content: View>: View {
    var background: Color = .white
    var onDark: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill((onDark ? Color.white : Color.black).opacity(0.08))
                .frame(height: 1)
        }
    }
}

func managedBleModelLine(_ device: DiscoveredEbtBleDevice) -> String {
    let blob = [
        device.rnBagIdModelString(),
        device.displayLabel(),
        String(describing: device.identity),
        device.advertisedLocalName ?? "",
        device.rnAdvertisedLocalName(),
    ].joined(separator: " ").uppercased()
    let compact = blob.filter { $0.isLetter || $0.isNumber }
    if device.rnBagIdModelString() == "bagid_2_st" ||
        blob.contains("BAGID_2ST") ||
        compact.contains("2ST") ||
        compact.contains("STFIND") ||
        compact.contains("SMARTTHINGS") ||
        compact.contains("SAMSUNG") {
        return "BagID 2 for Samsung"
    }
    if device.rnBagIdModelString() == "bagid_go" || compact.contains("BAGIDGO") {
        return "BagID Go"
    }
    return ManagedBleCopy.bagIdModel
}

struct ManagedBleFoundDevicesView: View {
    let devices: [DiscoveredEbtBleDevice]
    let selectedDeviceId: String?
    let isOther: Bool
    let errorText: String?
    /** Developer detail under the message; the flow passes it only when SDK debug logging is on. */
    var errorDetail: String? = nil
    let onSelect: (DiscoveredEbtBleDevice) -> Void
    let onConnect: () -> Void
    let onSearchAgain: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let theme: ManagedBleFlowTheme

    var body: some View {
        VStack(spacing: 0) {
            AtomicUiCloseBar(onLight: true, onClose: onClose)
            VStack(alignment: .leading, spacing: 8) {
                Text(ManagedBleCopy.foundTitle)
                    .font(.title2)
                    .foregroundStyle(MapFlowTheme.onLight)
                Text(ManagedBleCopy.foundSubtitle)
                    .font(.body)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {
                    if let errorText, !errorText.isEmpty {
                        ManagedBleNoticeBanner(message: errorText, detail: errorDetail)
                    }
                    ForEach(devices.sorted { $0.signalStrength > $1.signalStrength }, id: \.deviceId) { device in
                        Button { onSelect(device) } label: {
                            ManagedBleFoundDeviceCard(
                                title: isOther ? ManagedBleCopy.otherTitle : ManagedBleCopy.bagIdTitle,
                                modelLine: isOther ? ManagedBleCopy.otherModel : managedBleModelLine(device),
                                isSelected: selectedDeviceId == device.deviceId,
                                isOther: isOther
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ManagedBleBottomBar {
                ManagedBleOutlineButton(title: "Back", theme: theme, action: onBack)
                if selectedDeviceId != nil {
                    AtomicUiBottomButton(title: ManagedBleCopy.connect, theme: theme, action: onConnect)
                } else {
                    AtomicUiBottomButton(title: ManagedBleCopy.searchAgain, theme: theme, action: onSearchAgain)
                }
            }
        }
    }
}


/** Calm notice for a failed attempt: passenger copy, plus developer detail only in debug builds. */
struct ManagedBleNoticeBanner: View {
    let message: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.body)
                .foregroundStyle(Color(red: 0.72, green: 0.42, blue: 0.0))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.88))
        )
        .accessibilityElement(children: .combine)
    }
}

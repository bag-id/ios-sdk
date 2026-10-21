import BagIdSDK
import SwiftUI

enum MapFlowSettingsChrome {
    static let settingsBackground = Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255)
    static let stopRed = Color(red: 196 / 255, green: 57 / 255, blue: 57 / 255)
    static let stopRose = Color(red: 252 / 255, green: 228 / 255, blue: 231 / 255)

    @ViewBuilder
    static func closeBar(onClose: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MapFlowTheme.onLight)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    static func deviceHeader(device: MapDevice) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MapFlowDeviceChrome.iconCircleFill(isHighlighted: true))
                    .frame(width: 56, height: 56)
                MapFlowBagIdGlyph(maxSide: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.title3.bold())
                        .foregroundStyle(MapFlowTheme.onLight)
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
                    if device.trackingLive {
                        MapFlowLiveBadge()
                            .padding(.leading, 2)
                    }
                }
                Text(device.modelName)
                    .font(.footnote)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                Text(serialLine(for: device))
                    .font(.caption)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    static func serialLine(for device: MapDevice) -> String {
        let sn = device.serialNumber
        if sn.lowercased().hasPrefix("s/n") { return sn }
        return "S/N \(sn)"
    }

    @ViewBuilder
    static func sectionTitle(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    static func statusPill(active: Bool) -> some View {
        let bg = active ? Color(red: 0.91, green: 0.96, blue: 0.91) : MapFlowSettingsChrome.stopRose
        let fg = active ? Color(red: 0, green: 0.52, blue: 0.31) : MapFlowSettingsChrome.stopRed
        Text(active ? "Active" : "Disabled")
            .font(.caption.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
    }

    @ViewBuilder
    static func networkCardTitle() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            Text("Network")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    /// `loading` — consent not read yet: show a spinner instead of guessing on/off, so the badge never flips.
    static func networkBadgeRow(title: String, active: Bool, loading: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer()
            if loading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking network")
            } else {
                statusPill(active: active)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    static func infoCallout(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
            Text(text)
                .font(.footnote)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.75))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.94, blue: 0.95), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    static func actionButton(
        title: String,
        fill: Color,
        text: Color,
        border: Color?,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? text : text.opacity(0.38))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(fill, in: RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius))
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius)
                            .stroke(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    /// Consent read failed — treat as sharing off for network badges (matches Kotlin `trackingConsentNotGranted()`).
    static let trackingConsentOff = TrackingConsentView(
        granted: false,
        windowStartsAt: nil,
        windowEndsAt: nil,
        flightDepartureTimes: []
    )
}

/// "LIVE" pill with a pulsing dot, shown wherever a bag with active tracking appears.
struct MapFlowLiveBadge: View {
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(MapFlowTheme.accent)
                .frame(width: 6, height: 6)
                .opacity(dimmed ? 0.25 : 1)
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MapFlowTheme.accent)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(MapFlowTheme.accent.opacity(0.12), in: Capsule())
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live tracking")
    }
}

enum MapFlowFreshnessColor {
    /// Location line colour by last-seen age: green, yellow (amber, readable on white), red. nil = default grey.
    static func color(lastSeenAt: String?) -> Color? {
        guard let freshness = MapDeviceListPresentationKt.mapLocationFreshness(lastSeenAt: lastSeenAt) else {
            return nil
        }
        // if/else, not switch: a Kotlin enum is not exhaustive in Swift.
        if freshness == .fresh { return Color(red: 30 / 255, green: 142 / 255, blue: 62 / 255) }
        if freshness == .aging { return Color(red: 201 / 255, green: 138 / 255, blue: 0) }
        return Color(red: 196 / 255, green: 57 / 255, blue: 57 / 255)
    }
}

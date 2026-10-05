import BagIdSDK
import SwiftUI
import UIKit

struct MapFlowDeviceSettingsView: View {
    let device: MapDevice
    let onStopTracking: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keepLockOn = true

    private let stopRed = Color(red: 196 / 255, green: 57 / 255, blue: 57 / 255)
    private let stopRose = Color(red: 252 / 255, green: 228 / 255, blue: 231 / 255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                smallActionButton(
                    title: "View in map",
                    fill: .black,
                    text: .white,
                    border: nil,
                    action: { dismiss() }
                )
                settingsCard
                smallActionButton(
                    title: "Stop tracking",
                    fill: stopRose,
                    text: .black,
                    border: stopRed,
                    action: onStopTracking
                )
                section(title: "Lost or Missing BagID") {
                    lostCard
                }
                section(title: "Help and Support") {
                    helpCard
                }
            }
            .padding(.bottom, 28)
        }
        .background(Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MapFlowTheme.onLight)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MapFlowDeviceChrome.iconCircleFill(isHighlighted: true))
                        .frame(width: 56, height: 56)
                    MapFlowBagIdGlyph(maxSide: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(MapFlowDeviceChrome.nameEmoji(for: device))
                        Text(device.displayName)
                            .font(.title3.bold())
                            .foregroundStyle(MapFlowTheme.onLight)
                        Image(systemName: "pencil")
                            .font(.footnote)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
                    }
                    Text(device.modelName)
                        .font(.footnote)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                    Text(serialLine)
                        .font(.caption)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    private var serialLine: String {
        let sn = device.serialNumber
        if sn.lowercased().hasPrefix("s/n") { return sn }
        return "S/N \(sn)"
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "wifi", title: "Network", value: "Shared Network")
            Divider().padding(.leading, 52)
            settingsRow(icon: "lock.shield", title: "Consent & Privacy", value: "Active")
            Divider().padding(.leading, 52)
            settingsRow(icon: "gearshape", title: "Settings", value: nil)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
        .padding(.horizontal, 20)
    }

    private func settingsRow(icon: String, title: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var lostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If your bag is lost, keep the lock on so your airline can help trace it.")
                .font(.footnote)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
            HStack {
                Text("Keep lock on for now")
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight)
                Spacer()
                Toggle("", isOn: $keepLockOn)
                    .labelsHidden()
                    .tint(MapFlowTheme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
    }

    private var helpCard: some View {
        VStack(spacing: 14) {
            helpRow("Device Support", "BagID")
            helpRow("Journey Support", "Contact your airline")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
    }

    private func helpRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                .accessibilityLabel("Opens in a new tab")
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
            content()
        }
        .padding(.horizontal, 20)
    }

    private func smallActionButton(
        title: String,
        fill: Color,
        text: Color,
        border: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(fill, in: RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius))
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius)
                            .stroke(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

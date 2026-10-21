import BagIdSDK
import SwiftUI

/// Preferred device setting (design 15.4 — default device only).
struct MapFlowAppSettingsView: View {
    let device: MapDevice
    let onBack: () -> Void
    let onViewInMap: () -> Void
    var onClose: (() -> Void)?

    @State private var preferredDeviceOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MapFlowSettingsChrome.closeBar(onClose: onClose ?? onViewInMap)
                MapFlowSettingsChrome.deviceHeader(device: device)
                MapFlowSettingsChrome.actionButton(
                    title: "View in map",
                    fill: MapFlowTheme.accent,
                    text: MapFlowTheme.onPrimary,
                    border: nil,
                    action: onViewInMap
                )
                .padding(.top, 4)

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
                        Text("Default Device")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MapFlowTheme.onLight)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    Divider().padding(.leading, 16)
                    HStack {
                        Text("BagID as my default device type")
                            .font(.subheadline)
                            .foregroundStyle(MapFlowTheme.onLight)
                        Spacer()
                        Toggle("", isOn: $preferredDeviceOn)
                            .labelsHidden()
                            .tint(MapFlowTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
                .padding(.horizontal, 20)
                .padding(.top, 16)

                MapFlowSettingsChrome.actionButton(
                    title: "Back",
                    fill: .white,
                    text: MapFlowTheme.onLight,
                    border: Color(red: 0.8, green: 0.8, blue: 0.8),
                    action: onBack
                )
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(MapFlowSettingsChrome.settingsBackground.ignoresSafeArea())
    }
}

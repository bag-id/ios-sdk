import BagIdSDK
import SwiftUI

/// `SELECT_TAG_TYPE` — tap a row to continue; small “Don’t show this again” sets remember-choice.
struct SelectTagTypeFlowView: View {
    let onResult: (String) -> Void

    @State private var skipNextTime = false
    @State private var theme = ManagedBleFlowTheme.snapshot()

    var body: some View {
        VStack(spacing: 0) {
            AtomicUiCloseBar(onLight: true) {
                onResult(AtomicUi.shared.cancelSelectTagType())
            }
            theme.hostLogo()
                .padding(.leading, 20)
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Text(AtomicUiCopy.selectTitle)
                    .font(.title2)
                    .foregroundStyle(MapFlowTheme.onLight)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 28) {
                    tagRow(.bagid)
                    tagRow(.other)
                }
                Button { skipNextTime.toggle() } label: {
                    Text(AtomicUiCopy.prepareSkip)
                        .font(.footnote)
                        .foregroundStyle(
                            skipNextTime
                                ? MapFlowTheme.accent
                                : MapFlowTheme.onLight.opacity(0.55)
                        )
                        .underline()
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
        }
        .background(theme.cardBackground.ignoresSafeArea())
        .onAppear {
            skipNextTime = AtomicUi.shared.snapshot().rememberTagChoice
        }
    }

    private func tagRow(_ type: AtomicTagType) -> some View {
        Button {
            let json = AtomicUi.shared.confirmSelectTagType(
                tagType: type,
                rememberChoice: skipNextTime
            )
            onResult(json)
        } label: {
            HStack(spacing: 16) {
                Image(type == .bagid ? "TagTypeBagId" : "TagTypeOther", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 48)
                Text(AtomicUiCopy.displayName(type))
                    .font(.title2)
                    .foregroundStyle(MapFlowTheme.onLight)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MapFlowTheme.accent)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height * 0.075)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(MapFlowTheme.accent, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

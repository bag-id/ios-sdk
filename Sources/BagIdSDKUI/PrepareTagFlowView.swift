import BagIdSDK
import SwiftUI

/// `PREPARE_TAG` — pairing guidance. “Need help” is a sheet here, not a separate host present.
struct PrepareTagFlowView: View {
    let tagType: AtomicTagType
    let onResult: (String) -> Void

    @State private var showHelp = false
    @State private var theme = ManagedBleFlowTheme.snapshot()

    var body: some View {
        VStack(spacing: 0) {
            AtomicUiCloseBar(onLight: true) {
                onResult(AtomicUi.shared.cancelPrepareTag())
            }
            VStack(alignment: .leading, spacing: 32) {
                Text(AtomicUiCopy.prepareTitle)
                    .font(.title2)
                    .foregroundStyle(MapFlowTheme.onLight)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                if tagType == .bagid {
                    Image("BagIdPairGuide", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.height * 0.34)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button { showHelp = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AtomicUiCopy.prepareNeedHelp)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MapFlowTheme.onLight)
                            Text(AtomicUiCopy.prepareHelpSubtitle)
                                .font(.caption)
                                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(MapFlowTheme.onLight.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Button {
                    let json = AtomicUi.shared.skipPrepareTag(tagType: tagType)
                    onResult(json)
                } label: {
                    Text(AtomicUiCopy.prepareSkip)
                        .font(.footnote)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                        .underline()
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            AtomicUiBottomButton(title: AtomicUiCopy.prepareContinue, theme: theme) {
                let json = AtomicUi.shared.continuePrepareTag(tagType: tagType)
                onResult(json)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .sheet(isPresented: $showHelp) {
            PrepareTagHelpSheet(tagType: tagType)
        }
    }
}

private struct PrepareTagHelpSheet: View {
    let tagType: AtomicTagType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(AtomicUiCopy.helpSteps(tagType).enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("•")
                                .foregroundStyle(MapFlowTheme.accent)
                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    }
                }
                .padding(24)
            }
            .background(MapFlowTheme.background)
            .navigationTitle(AtomicUiCopy.prepareNeedHelp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AtomicUiCopy.helpGotIt) { dismiss() }
                        .foregroundStyle(MapFlowTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

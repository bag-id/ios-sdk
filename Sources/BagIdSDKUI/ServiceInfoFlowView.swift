import BagIdSDK
import SwiftUI

/// `SERVICE_INFO` — terms / privacy. Skip-if-recorded is decided in [BagIdIosHost.presentServiceInfo]
/// before this view is created.
struct ServiceInfoFlowView: View {
    let apiBaseUrl: String
    let sourceAppKey: String
    let federatedToken: String
    let payloadJson: String?
    /// Host already ran configure/initialize + resolve; show terms without a second GET.
    let sessionAlreadyReady: Bool
    let onResult: (String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var loading: Bool
    @State private var loadError: String?
    @State private var theme = ManagedBleFlowTheme.snapshot()
    @State private var privacyPolicyUrl: String?

    init(
        apiBaseUrl: String,
        sourceAppKey: String,
        federatedToken: String,
        payloadJson: String?,
        sessionAlreadyReady: Bool = false,
        onResult: @escaping (String) -> Void
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.sourceAppKey = sourceAppKey
        self.federatedToken = federatedToken
        self.payloadJson = payloadJson
        self.sessionAlreadyReady = sessionAlreadyReady
        self.onResult = onResult
        _loading = State(initialValue: !sessionAlreadyReady)
        _loadError = State(initialValue: nil)
    }

    private var heroHeight: CGFloat { UIScreen.main.bounds.height * 0.42 }
    private var fadeHeight: CGFloat { heroHeight * 0.42 }
    private var policyURL: URL? {
        let raw = privacyPolicyUrl ?? AtomicUiCopy.servicePolicyUrl
        return URL(string: raw)
    }

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.ignoresSafeArea())
            } else if let loadError {
                VStack(spacing: 12) {
                    Text("Unable to open")
                        .font(.headline)
                    Button("Close") { onResult(loadError) }
                        .showAfter15s()
                }
                .padding()
            } else {
                content
            }
        }
        .task {
            await loadLegalLinks()
            guard !sessionAlreadyReady else { return }
            await bootstrap()
        }
    }

    private func loadLegalLinks() async {
        if let links = try? await BagIdSdk.shared.legalLinks() {
            await MainActor.run {
                privacyPolicyUrl = links.privacyPolicy
            }
        }
    }

    private var content: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Image("TermsHero", bundle: .module)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .clipped()
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.35), location: 0.4),
                            .init(color: .white.opacity(0.82), location: 0.75),
                            .init(color: .white, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: fadeHeight)
                    .allowsHitTesting(false)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("BagID")
                            .font(.title3)
                            .foregroundStyle(MapFlowTheme.accent)
                        Text(AtomicUiCopy.serviceTitle)
                            .font(.title2)
                            .foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AtomicUiCopy.serviceBody)
                            .font(.body)
                            .foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            if let policyURL { openURL(policyURL) }
                        } label: {
                            (Text(AtomicUiCopy.serviceAcceptPrefix)
                                + Text(AtomicUiCopy.servicePolicy).bold()
                                + Text(" ")
                                + Text(Image(systemName: "arrow.up.right.square")))
                                .font(.body)
                                .foregroundStyle(.black)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .background(Color.white)
            }
            .ignoresSafeArea(edges: .top)

            AtomicUiCloseBar(onLight: true) {
                onResult(AtomicUi.shared.cancelServiceInfo())
            }
        }
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ManagedBleBottomBar {
                AtomicUiBottomButton(title: AtomicUiCopy.serviceContinue, theme: theme) {
                    Task {
                        do {
                            let json = try await AtomicUi.shared.acceptServiceInfo()
                            onResult(json)
                        } catch {
                            onResult(serviceInfoFailureJson(error))
                        }
                    }
                }
            }
        }
    }

    private func bootstrap() async {
        let request = ServiceInfoLaunchRequest(
            apiBaseUrl: apiBaseUrl,
            sourceAppKey: sourceAppKey,
            federatedToken: federatedToken,
            payloadJson: payloadJson
        )
        do {
            if let failure = try await AtomicUi.shared.prepareServiceInfoSession(request: request) {
                await MainActor.run {
                    loading = false
                    loadError = failure
                }
                return
            }
            let decision = try await AtomicUi.shared.resolveServiceInfo()
            await MainActor.run {
                switch onEnum(of: decision) {
                case .skipUi(let skip):
                    onResult(skip.resultJson)
                case .showUi:
                    loading = false
                }
            }
        } catch {
            await MainActor.run {
                loading = false
                loadError = serviceInfoFailureJson(error)
            }
        }
    }
}

private func serviceInfoFailureJson(_ error: Error) -> String {
    let message = error.localizedDescription
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "{\"status\":\"FAILURE\",\"operation\":\"SERVICE_INFO\",\"code\":\"ACCEPT_FAILED\",\"message\":\"\(message)\"}"
}

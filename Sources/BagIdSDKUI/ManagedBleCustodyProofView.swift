import BagIdSDK
import SwiftUI

enum ManagedBleCustodyCopy {
    static let title = "Your BagID is attached to a journey"
    static let body =
        "To keep your bag safe, we need to confirm it's yours before it can be used again. " +
        "Enter the booking reference and surname of the journey below."
    static let journeyHeader = "Current journey"
    static let bookingRef = "Booking reference"
    static let surname = "Surname"
    static let bookingRefPlaceholder = "e.g. ABC123"
    static let surnamePlaceholder = "As shown on the booking"
    static let disconnected = "Connection to your BagID was lost. Keep it close to your phone — reconnecting…"
    static let cancel = "Cancel"
    static let confirm = "Confirm"
    static let waitingForTag = "Waiting for BagID…"

    static func attemptsLeft(_ n: Int) -> String {
        n == 1 ? "1 attempt left" : "\(n) attempts left"
    }
}

/// Full-screen custody proof (PNR + surname) shown while `transferTag` suspends in the collector.
struct ManagedBleCustodyProofView: View {
    let hints: CustodyHints
    let attemptIndex: Int
    let maxAttempts: Int
    let lastError: String?
    let tagDisconnected: Bool
    let waitingForTag: Bool
    @Binding var recordLocator: String
    @Binding var surname: String
    let theme: ManagedBleFlowTheme
    let onSubmit: () -> Void
    let onCancel: () -> Void

    private enum Field { case recordLocator, surname }
    @FocusState private var focus: Field?

    private var canSubmit: Bool {
        !recordLocator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !surname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !waitingForTag
    }

    var body: some View {
        VStack(spacing: 0) {
            AtomicUiCloseBar(onLight: true, onClose: onCancel)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    connectionSlot
                    journeyCard
                    if let lastError, !lastError.isEmpty {
                        errorRow(lastError)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        field(
                            ManagedBleCustodyCopy.bookingRef,
                            placeholder: ManagedBleCustodyCopy.bookingRefPlaceholder,
                            text: $recordLocator,
                            field: .recordLocator
                        )
                        .submitLabel(.next)
                        .onSubmit { focus = .surname }
                        field(
                            ManagedBleCustodyCopy.surname,
                            placeholder: ManagedBleCustodyCopy.surnamePlaceholder,
                            text: $surname,
                            field: .surname
                        )
                        .submitLabel(.done)
                        .onSubmit { if canSubmit { onSubmit() } }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ManagedBleBottomBar {
                ManagedBleOutlineButton(title: ManagedBleCustodyCopy.cancel, theme: theme, action: onCancel)
                AtomicUiBottomButton(
                    title: waitingForTag ? ManagedBleCustodyCopy.waitingForTag : ManagedBleCustodyCopy.confirm,
                    disabled: !canSubmit,
                    theme: theme,
                    action: {
                        focus = nil
                        onSubmit()
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: tagDisconnected)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 1, green: 0.93, blue: 0.82))
                    .frame(width: 64, height: 64)
                Image("TagTypeBagId", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            }
            Text(ManagedBleCustodyCopy.title)
                .font(.title2.bold())
                .foregroundStyle(MapFlowTheme.onLight)
                .fixedSize(horizontal: false, vertical: true)
            Text(ManagedBleCustodyCopy.body)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Reserved area for the reconnect notice — appears/disappears without shifting the form much.
    @ViewBuilder
    private var connectionSlot: some View {
        if tagDisconnected {
            HStack(alignment: .top, spacing: 10) {
                ProgressView()
                    .tint(MapFlowTheme.onLight)
                Text(ManagedBleCustodyCopy.disconnected)
                    .font(.footnote)
                    .foregroundStyle(MapFlowTheme.onLight)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                Color(red: 1, green: 0.93, blue: 0.82),
                in: RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ManagedBleCustodyCopy.journeyHeader.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
            if let route = routeLine {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .foregroundStyle(theme.primary)
                    Text(route)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MapFlowTheme.onLight)
                }
            }
            if let departure = formattedDeparture {
                Text(departure)
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            }
            HStack(spacing: 24) {
                hintColumn(ManagedBleCustodyCopy.bookingRef, hints.maskedRecordLocator)
                hintColumn(ManagedBleCustodyCopy.surname, hints.maskedSurname)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
    }

    @ViewBuilder
    private func hintColumn(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                Text(value)
                    .font(.body.monospaced())
                    .foregroundStyle(MapFlowTheme.onLight)
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        let remaining = max(maxAttempts - attemptIndex + 1, 0)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(theme.error)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.error)
                Text(ManagedBleCustodyCopy.attemptsLeft(remaining))
                    .font(.caption)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.6))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        let radius = MapFlowTheme.cornerRadius
        let active = focus == field
        let stroke = active ? theme.primary : MapFlowTheme.onLight.opacity(0.25)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
            TextField(placeholder, text: text)
                .font(.body)
                .foregroundStyle(MapFlowTheme.onLight)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .focused($focus, equals: field)
                .padding(.horizontal, theme.inputStyle == .underlined ? 0 : 14)
                .frame(height: 48)
                .background {
                    switch theme.inputStyle {
                    case .outlined:
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(stroke, lineWidth: active ? 1.5 : 1)
                    case .filled:
                        RoundedRectangle(cornerRadius: radius)
                            .fill(Color(white: 0.95))
                            .overlay(
                                RoundedRectangle(cornerRadius: radius)
                                    .stroke(active ? theme.primary : .clear, lineWidth: 1.5)
                            )
                    case .underlined:
                        VStack {
                            Spacer()
                            Rectangle().fill(stroke).frame(height: active ? 1.5 : 1)
                        }
                    }
                }
        }
    }

    private var routeLine: String? {
        let parts = [hints.departureAirport, hints.destinationAirport]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " → ")
    }

    private var formattedDeparture: String? {
        guard let iso = hints.departureAtIso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

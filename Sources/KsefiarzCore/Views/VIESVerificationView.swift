import SwiftUI

/// Karta weryfikacji kontrahenta unijnego w VIES (unijna baza VAT). Odpowiednik
/// `ContractorVerificationView` dla kontrahentów spoza Polski: sprawdza
/// aktywność numeru VAT-UE i — jeśli podano NIP naszej firmy — pobiera numer
/// potwierdzenia zapytania (dowód należytej staranności). Dane pobierane na
/// żywo z REST API Komisji Europejskiej; nic nie jest utrwalane lokalnie.
public struct VIESVerificationView: View {

    let countryCode: String
    let vatNumber: String
    let expectedName: String?

    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @Environment(\.dismiss) private var dismiss

    @State private var result: VIESVerificationResult?
    @State private var isLoading = false

    public init(countryCode: String, vatNumber: String, expectedName: String? = nil) {
        self.countryCode = countryCode
        self.vatNumber = vatNumber
        self.expectedName = expectedName
    }

    /// NIP naszej firmy pozwala uzyskać numer potwierdzenia zapytania VIES.
    private var requesterNIP: String? {
        let digits = myNIP.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 440)
        .task { await run() }
    }

    // MARK: Nagłówek

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weryfikacja VAT-UE (VIES)")
                .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                if let expectedName, !expectedName.isEmpty {
                    Text(expectedName)
                    Text("•")
                }
                Text("VAT-UE: \(VIESVerification.normalizedCountry(countryCode))\(vatNumber.uppercased().filter { $0.isLetter || $0.isNumber })")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: Zawartość

    @ViewBuilder
    private var content: some View {
        if isLoading && result == nil {
            VStack(spacing: 10) {
                ProgressView()
                Text("Sprawdzam numer w systemie VIES…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    verdictBanner(result)
                    ForEach(result.findings) { finding in
                        FindingRow(finding: finding)
                    }
                    if requesterNIP == nil {
                        Text("Aby uzyskać numer potwierdzenia zapytania (dowód sprawdzenia), uzupełnij NIP swojej firmy w Ustawieniach.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
        } else {
            Color.clear
        }
    }

    private func verdictBanner(_ result: VIESVerificationResult) -> some View {
        let severity = result.overallSeverity
        return HStack(spacing: 10) {
            Image(systemName: ContractorVerificationView.icon(for: severity))
                .font(.title2)
                .foregroundStyle(ContractorVerificationView.color(for: severity))
            Text(result.headline)
                .font(.headline)
            Spacer()
        }
        .padding(12)
        .background(ContractorVerificationView.color(for: severity).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Stopka

    private var footer: some View {
        HStack {
            Label("Źródło: VIES (Komisja Europejska)", systemImage: "flag")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await run() }
            } label: {
                Label("Sprawdź ponownie", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
            Button("Zamknij") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: Dane

    @MainActor
    private func run() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let service = VIESVerificationService()
        result = await service.verify(
            countryCode: countryCode,
            vatNumber: vatNumber,
            requesterNIP: requesterNIP
        )
    }
}

#Preview {
    VIESVerificationView(countryCode: "DE", vatNumber: "123456789", expectedName: "ACME GmbH")
}

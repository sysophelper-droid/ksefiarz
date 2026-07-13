import SwiftUI

/// Karta weryfikacji kontrahenta: łączy status z Wykazu podatników VAT
/// (Biała lista) z KSeF-natywnym sprawdzeniem relacji uprawnień podmiotowych
/// (czy kontrahent nadał nam uprawnienie w KSeF). Dane pobierane na żywo —
/// źródłem prawdy są usługi MF, nic nie jest utrwalane lokalnie.
public struct ContractorVerificationView: View {

    let nip: String
    let expectedName: String?

    @ObservedObject private var tokenStore = TokenStore.shared
    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.production.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var result: ContractorVerificationResult?
    @State private var isLoading = false

    public init(nip: String, expectedName: String? = nil) {
        self.nip = nip
        self.expectedName = expectedName
    }

    private var environment: KSeFEnvironment {
        KSeFEnvironment(rawValue: environmentRaw) ?? .production
    }

    /// Poświadczenia KSeF potrzebne do sprawdzenia relacji uprawnień.
    /// Bez nich karta pokazuje wyłącznie status z wykazu VAT.
    private var hasKSeFCredentials: Bool {
        !myNIP.isEmpty
            && (!tokenStore.token.isEmpty
                || KSeFCertificateStore.shared.authenticationCertificate != nil)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 460)
        .task { await run() }
    }

    // MARK: Nagłówek

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weryfikacja kontrahenta")
                .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                if let expectedName, !expectedName.isEmpty {
                    Text(expectedName)
                    Text("•")
                }
                Text("NIP: \(formattedNIP)")
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
                Text("Sprawdzam w Wykazie podatników VAT\(hasKSeFCredentials ? " i KSeF" : "")…")
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
                    if !hasKSeFCredentials {
                        Text("Aby sprawdzić relację uprawnień w KSeF, uzupełnij NIP oraz token lub certyfikat w Ustawieniach.")
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

    private func verdictBanner(_ result: ContractorVerificationResult) -> some View {
        let severity = result.overallSeverity
        return HStack(spacing: 10) {
            Image(systemName: Self.icon(for: severity))
                .font(.title2)
                .foregroundStyle(Self.color(for: severity))
            Text(result.headline)
                .font(.headline)
            Spacer()
        }
        .padding(12)
        .background(Self.color(for: severity).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Stopka

    private var footer: some View {
        HStack {
            Label("Środowisko KSeF: \(environment.displayName)", systemImage: "server.rack")
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

    private var formattedNIP: String {
        let digits = nip.filter(\.isNumber)
        guard digits.count == 10 else { return nip }
        // Format NIP: XXX-XXX-XX-XX.
        let d = Array(digits)
        return "\(d[0])\(d[1])\(d[2])-\(d[3])\(d[4])\(d[5])-\(d[6])\(d[7])-\(d[8])\(d[9])"
    }

    @MainActor
    private func run() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let service = ContractorVerificationService(ksef: hasKSeFCredentials ? makeKSeFService() : nil)
        result = await service.verify(nip: nip)
    }

    private func makeKSeFService() -> KSeFService {
        KSeFService(
            environment: environment,
            nip: myNIP,
            authToken: tokenStore.token,
            certificate: KSeFCertificateStore.shared.authenticationCertificate
        )
    }

    // MARK: Ikony / kolory wagi

    static func icon(for severity: ContractorVerificationSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    static func color(for severity: ContractorVerificationSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Wiersz ustalenia

/// Pojedyncza linia karty: ikona wagi, tytuł i opcjonalny szczegół.
private struct FindingRow: View {
    let finding: ContractorVerificationResult.Finding

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ContractorVerificationView.icon(for: finding.severity))
                .foregroundStyle(ContractorVerificationView.color(for: finding.severity))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.callout)
                if let detail = finding.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContractorVerificationView(nip: "5260250274", expectedName: "ACME Sp. z o.o.")
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sekcja Ustawień: certyfikaty KSeF (uwierzytelniający typ 1 i offline typ 2).
/// Certyfikaty można uzyskać wprost z KSeF (wniosek CSR — wymaga zalogowania
/// podpisem: na środowisku testowym wystarcza self-signed, na produkcji
/// istniejący certyfikat KSeF) albo zaimportować z pliku (.p12 / PEM).
struct CertificateSettingsSection: View {

    @ObservedObject private var certificateStore = KSeFCertificateStore.shared
    @AppStorage(AppSettingsKeys.nip) private var nip = ""
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue

    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var environment: KSeFEnvironment {
        KSeFEnvironment(rawValue: environmentRaw) ?? .test
    }

    /// Czy da się złożyć wniosek do KSeF: na teście zawsze (bootstrap
    /// self-signed), gdzie indziej tylko z ważnym certyfikatem typu 1.
    private var canRequestFromKSeF: Bool {
        environment == .test
            || certificateStore.authenticationCertificate?.info?.isValid() == true
    }

    var body: some View {
        Section {
            certificateRow(
                type: .authentication,
                certificate: certificateStore.authenticationCertificate
            )
            certificateRow(
                type: .offline,
                certificate: certificateStore.offlineCertificate
            )

            HStack(spacing: 12) {
                Menu {
                    Button("Certyfikat uwierzytelniający (typ 1)") {
                        Task { await requestFromKSeF(type: .authentication) }
                    }
                    Button("Certyfikat offline (typ 2)") {
                        Task { await requestFromKSeF(type: .offline) }
                    }
                } label: {
                    Label("Uzyskaj z KSeF", systemImage: "checkmark.seal")
                }
                .fixedSize()
                .disabled(isBusy || !canRequestFromKSeF || nip.isEmpty)
                .help(canRequestFromKSeF
                    ? "Składa wniosek certyfikacyjny — klucz prywatny powstaje na tym komputerze."
                    : "Wniosek wymaga zalogowania podpisem — najpierw zaimportuj certyfikat z Aplikacji Podatnika.")

                Menu {
                    Button("Jako uwierzytelniający (typ 1)") {
                        Task { await importFromFile(type: .authentication) }
                    }
                    Button("Jako offline (typ 2)") {
                        Task { await importFromFile(type: .offline) }
                    }
                } label: {
                    Label("Importuj z pliku…", systemImage: "square.and.arrow.down")
                }
                .fixedSize()
                .disabled(isBusy)

                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            if let statusMessage {
                Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(statusIsError ? .red : .green)
            }
        } header: {
            Text("Certyfikaty KSeF")
        } footer: {
            Text("Certyfikat uwierzytelniający (typ 1) to preferowany sposób logowania do KSeF — tokeny API mają przestać działać (zapowiadane: koniec 2026 r.). Aplikacja loguje się certyfikatem, a przy niepowodzeniu wraca do tokenu. Certyfikat offline (typ 2) służy wyłącznie do podpisywania kodu QR „CERTYFIKAT” na dokumentach trybu offline24. Na środowisku produkcyjnym pierwszy certyfikat pozyskasz w Aplikacji Podatnika KSeF 2.0 (wymaga podpisu kwalifikowanego lub Profilu Zaufanego) i zaimportujesz z pliku — kolejne aplikacja odnowi sama. Certyfikaty i klucze prywatne są przechowywane w pęku kluczy, osobno dla każdego środowiska; nie trafiają do kopii zapasowych.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Wiersz certyfikatu

    @ViewBuilder
    private func certificateRow(type: KSeFCertificateType, certificate: KSeFCertificate?) -> some View {
        LabeledContent(type.displayName) {
            HStack(spacing: 8) {
                if let certificate, let info = certificate.info {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(info.subjectSummary)
                        Text("nr \(certificate.serialNumberHex) · ważny do \(info.validTo.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(expiryColor(info))
                    }
                    .font(.callout)
                    Button {
                        certificateStore.delete(type: type)
                        showStatus("Usunięto certyfikat: \(type.displayName).", isError: false)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Usuń certyfikat z pęku kluczy")
                } else {
                    Text("brak")
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let info = certificate?.info {
            if !info.isValid() {
                Label("Certyfikat wygasł — uzyskaj nowy albo zaimportuj aktualny.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if info.daysToExpiry() <= 30 {
                Label("Certyfikat wygasa za \(info.daysToExpiry()) dni — odnów go zawczasu.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func expiryColor(_ info: KSeFCertificate.CertificateInfo) -> Color {
        if !info.isValid() { return .red }
        if info.daysToExpiry() <= 30 { return .orange }
        return .secondary
    }

    // MARK: Wniosek do KSeF

    /// Składa wniosek o certyfikat: loguje się istniejącym certyfikatem
    /// typu 1, a na środowisku testowym — jednorazowym self-signed.
    @MainActor
    private func requestFromKSeF(type: KSeFCertificateType) async {
        guard !nip.isEmpty else {
            showStatus("Uzupełnij NIP w zakładce Firma.", isError: true)
            return
        }
        isBusy = true
        defer { isBusy = false }

        do {
            let bootstrap: KSeFCertificate
            if let existing = certificateStore.authenticationCertificate,
               existing.info?.isValid() == true {
                bootstrap = existing
            } else if environment == .test {
                let key = try X509Builder.generateRSAKeyPair()
                let der = try X509Builder.makeSelfSignedCertificate(
                    subject: [
                        .countryName("PL"),
                        .organizationName("Ksefiarz \(nip)"),
                        .commonName("Ksefiarz \(nip)"),
                        .organizationIdentifier("VATPL-\(nip)"),
                    ],
                    privateKey: key
                )
                bootstrap = KSeFCertificate(
                    certificateDER: der,
                    privateKeyDER: try X509Builder.exportPrivateKey(key)
                )
            } else {
                showStatus("Na tym środowisku wniosek wymaga ważnego certyfikatu typu 1 — zaimportuj go z pliku.", isError: true)
                return
            }

            let service = KSeFService(
                environment: environment,
                nip: nip,
                authToken: "",
                certificate: bootstrap
            )
            let issued = try await service.requestCertificate(
                name: "Ksefiarz \(type == .authentication ? "uwierzytelniający" : "offline")",
                type: type
            )
            certificateStore.save(issued, type: type)
            let expiry = issued.info?.validTo.formatted(date: .abbreviated, time: .omitted) ?? "?"
            showStatus("Wystawiono certyfikat (\(type.displayName)), ważny do \(expiry).", isError: false)
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    // MARK: Import z pliku

    /// Importuje certyfikat z pliku .p12/.pfx (z hasłem) albo PEM
    /// (certyfikat + klucz — w jednym lub dwóch plikach).
    @MainActor
    private func importFromFile(type: KSeFCertificateType) async {
        let panel = NSOpenPanel()
        panel.message = "Wybierz plik certyfikatu (.p12/.pfx albo PEM)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }

        do {
            let certificate: KSeFCertificate
            if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN") {
                certificate = try importPEM(text)
            } else {
                guard let password = askPassword(fileName: url.lastPathComponent) else { return }
                certificate = try KSeFCertificateImporter.importPKCS12(data: data, password: password)
            }
            guard let info = certificate.info else {
                showStatus("Nie udało się odczytać pól certyfikatu.", isError: true)
                return
            }
            certificateStore.save(certificate, type: type)
            showStatus(
                "Zaimportowano: \(info.subjectSummary), ważny do \(info.validTo.formatted(date: .abbreviated, time: .omitted)).",
                isError: false
            )
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    /// Import PEM — gdy w pliku brak klucza prywatnego, prosi o drugi plik.
    @MainActor
    private func importPEM(_ text: String) throws -> KSeFCertificate {
        if text.contains("PRIVATE KEY-----") {
            return try KSeFCertificateImporter.importPEM(certificatePEM: text, privateKeyPEM: text)
        }
        let panel = NSOpenPanel()
        panel.message = "Wybierz plik klucza prywatnego (PEM)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let keyText = try? String(contentsOf: url, encoding: .utf8) else {
            throw KSeFCertificateImporter.ImportError.invalidPEM("nie wybrano pliku klucza prywatnego")
        }
        return try KSeFCertificateImporter.importPEM(certificatePEM: text, privateKeyPEM: keyText)
    }

    /// Modalne pytanie o hasło pliku PKCS#12.
    @MainActor
    private func askPassword(fileName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Hasło pliku \(fileName)"
        alert.informativeText = "Podaj hasło zabezpieczające plik PKCS#12."
        alert.addButton(withTitle: "Importuj")
        alert.addButton(withTitle: "Anuluj")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

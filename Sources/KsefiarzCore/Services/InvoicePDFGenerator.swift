import SwiftUI
import AppKit

/// Generator dokumentu PDF z fakturą — renderuje klasyczny układ faktury
/// (strony, pozycje, podsumowanie, dane płatności) do stron A4.
/// Długie faktury są dzielone na wiele stron: pierwsza zawiera nagłówek
/// i dane stron transakcji, środkowe samą tabelę pozycji, ostatnia
/// podsumowanie z danymi płatności i uwagami.
@MainActor
public enum InvoicePDFGenerator {

    /// Rozmiar strony A4 w punktach.
    private static let pageSize = CGSize(width: 595, height: 842)

    /// Pojemności stron w wierszach pozycji — dobrane zachowawczo
    /// (wiersz z zawijaną nazwą i kodem CN/PKWiU zajmuje do dwóch linii).
    enum PageCapacity {
        /// Pierwsza strona: nagłówek + strony transakcji zabierają miejsce.
        static let first = 12
        /// Strony środkowe: tylko mini-nagłówek i tabela.
        static let middle = 22
        /// Maksimum wierszy na stronie, która mieści też podsumowanie,
        /// płatność i uwagi.
        static let withSummary = 10
    }

    /// Generuje dane PDF dla faktury. Zwraca `nil` przy błędzie renderowania.
    public static func pdfData(for invoice: Invoice) -> Data? {
        let qrCodes = makeQRCodes(for: invoice)
        let chunks = paginate(invoice.sortedLines, reserveQRSpace: qrCodes != nil)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for (index, chunk) in chunks.enumerated() {
            let page = InvoicePrintPageView(
                invoice: invoice,
                lines: chunk,
                isFirstPage: index == 0,
                isLastPage: index == chunks.count - 1,
                pageNumber: index + 1,
                pageCount: chunks.count,
                qrCodes: index == chunks.count - 1 ? qrCodes : nil
            )
            .frame(width: pageSize.width - 80)
            .padding(40)
            .background(Color.white)
            .environment(\.colorScheme, .light) // wydruk zawsze w jasnym motywie

            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
            renderer.render { size, render in
                context.beginPDFPage(nil)
                // Zawartość rysowana od górnej krawędzi strony.
                context.translateBy(x: 0, y: pageSize.height - size.height)
                render(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// Dzieli pozycje na strony. Ostatnia strona musi pomieścić podsumowanie —
    /// jeśli pozycje jej nie zostawiają miejsca, podsumowanie dostaje
    /// osobną stronę (pusty ostatni fragment).
    /// - Parameter reserveQRSpace: sekcja kodów QR na ostatniej stronie
    ///   zabiera miejsce ok. trzech wierszy pozycji.
    static func paginate(_ lines: [InvoiceLine], reserveQRSpace: Bool = false) -> [[InvoiceLine]] {
        let summaryCapacity = PageCapacity.withSummary - (reserveQRSpace ? 3 : 0)
        guard lines.count > summaryCapacity else { return [lines] }

        var chunks: [[InvoiceLine]] = []
        var remaining = lines[...]
        while !remaining.isEmpty {
            let capacity = chunks.isEmpty ? PageCapacity.first : PageCapacity.middle
            chunks.append(Array(remaining.prefix(capacity)))
            remaining = remaining.dropFirst(capacity)
        }
        if let last = chunks.last, last.count > summaryCapacity {
            chunks.append([])
        }
        return chunks
    }

    // MARK: Kody QR wizualizacji

    /// Kody QR wymagane na wizualizacji faktury KSeF.
    struct InvoiceQRCodes {
        /// KOD I — link weryfikacyjny faktury.
        let verification: CGImage
        /// Etykieta pod KODEM I: numer KSeF albo „OFFLINE”.
        let verificationLabel: String
        /// KOD II („CERTYFIKAT”) — tylko dokumenty offline.
        let certificate: CGImage?
        /// Informacja, gdy KOD II jest wymagany, ale nie dało się go zbudować.
        let certificateNote: String?
    }

    /// Buduje kody QR dla faktury: KOD I dla każdego dokumentu z numerem KSeF
    /// lub wystawionego offline, KOD II dodatkowo dla dokumentów offline
    /// (podpis certyfikatem KSeF typu 2 — domyślnie z pęku kluczy).
    static func makeQRCodes(
        for invoice: Invoice,
        offlineCertificate: KSeFCertificate? = KSeFCertificateStore.shared.offlineCertificate
    ) -> InvoiceQRCodes? {
        guard !invoice.sellerNIP.isEmpty else { return nil }
        guard invoice.ksefId != nil || invoice.isOfflineMode else { return nil }

        // Skrót dokładnie tych bajtów XML, które są/będą w KSeF.
        let hashBase64: String
        if invoice.isOfflineMode, !invoice.offlineHashBase64.isEmpty {
            hashBase64 = invoice.offlineHashBase64
        } else if let xml = invoice.rawXmlContent, !xml.isEmpty {
            hashBase64 = KSeFCrypto.sha256Base64(Data(xml.utf8))
        } else {
            return nil
        }

        // Środowisko dokumentu; dla pobranych (bez zapisanego) — bieżące.
        let environmentRaw = invoice.ksefEnvironmentRaw.isEmpty
            ? UserDefaults.standard.string(forKey: AppSettingsKeys.environment) ?? ""
            : invoice.ksefEnvironmentRaw
        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .production

        let verificationURL = KSeFVerificationLink.invoiceURL(
            environment: environment,
            sellerNIP: invoice.sellerNIP,
            issueDate: invoice.issueDate,
            xmlHashBase64: hashBase64
        )
        guard let verification = QRCodeRenderer.image(for: verificationURL) else { return nil }

        var certificateImage: CGImage?
        var certificateNote: String?
        if invoice.isOfflineMode {
            if let offlineCertificate,
               offlineCertificate.info?.isValid() == true,
               let url = try? KSeFVerificationLink.certificateURL(
                   environment: environment,
                   contextNip: invoice.sellerNIP,
                   sellerNIP: invoice.sellerNIP,
                   certificate: offlineCertificate,
                   xmlHashBase64: hashBase64
               ) {
                certificateImage = QRCodeRenderer.image(for: url)
            }
            if certificateImage == nil {
                certificateNote = "Brak certyfikatu offline (typ 2) — dokument offline wymaga KODU II. Uzyskaj certyfikat w Ustawieniach i wygeneruj PDF ponownie."
            }
        }

        return InvoiceQRCodes(
            verification: verification,
            verificationLabel: invoice.ksefId ?? "OFFLINE",
            certificate: certificateImage,
            certificateNote: certificateNote
        )
    }
}

// MARK: - Układ wydruku (pojedyncza strona)

/// Jedna strona wydruku faktury.
struct InvoicePrintPageView: View {
    let invoice: Invoice
    let lines: [InvoiceLine]
    let isFirstPage: Bool
    let isLastPage: Bool
    let pageNumber: Int
    let pageCount: Int
    /// Kody QR wizualizacji KSeF — tylko na ostatniej stronie.
    var qrCodes: InvoicePDFGenerator.InvoiceQRCodes?

    private var dateText: String {
        FA2Format.dateFormatter.string(from: invoice.issueDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isFirstPage {
                fullHeader
                // Strony
                HStack(alignment: .top, spacing: 24) {
                    partyBox(title: "Sprzedawca", name: invoice.sellerName, nip: invoice.sellerNIP, address: invoice.sellerAddress)
                    partyBox(title: "Nabywca", name: invoice.buyerName, nip: invoice.buyerNIP, address: invoice.buyerAddress)
                }
            } else {
                continuationHeader
            }

            // Pozycje (fragment przypadający na tę stronę)
            if !lines.isEmpty {
                linesTable
            }

            if isLastPage {
                summarySection
            } else {
                Spacer(minLength: 0)
                Text("ciąg dalszy na następnej stronie…")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if pageCount > 1 {
                Text("Strona \(pageNumber) z \(pageCount)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
    }

    // MARK: Nagłówki

    private var fullHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Faktura VAT")
                    .font(.system(size: 22, weight: .bold))
                Text("Nr \(invoice.invoiceNumber)")
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Data wystawienia: \(dateText)")
                if let ksefId = invoice.ksefId {
                    Text("Nr KSeF: \(ksefId)")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }

    /// Skrócony nagłówek stron kontynuacji.
    private var continuationHeader: some View {
        HStack {
            Text("Faktura VAT nr \(invoice.invoiceNumber) — ciąg dalszy")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text("Data wystawienia: \(dateText)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Sekcje

    /// Podsumowanie kwot, kwota słownie, płatność i uwagi — ostatnia strona.
    @ViewBuilder
    private var summarySection: some View {
        HStack {
            Spacer()
            Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    Text("Razem netto:")
                    Text(invoice.netAmount, format: .currency(code: invoice.currency))
                }
                GridRow {
                    Text("Razem VAT:")
                    Text(invoice.vatAmount, format: .currency(code: invoice.currency))
                }
                GridRow {
                    Text("Do zapłaty:").fontWeight(.bold)
                    Text(invoice.grossAmount, format: .currency(code: invoice.currency)).fontWeight(.bold)
                }
            }
            .font(.system(size: 11))
        }

        // Kwota słownie — standardowy element polskiej faktury.
        Text("Słownie: \(AmountInWords.polishCurrency(invoice.grossAmount))")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

        // Uwagi (stopka faktury) — dopisek użytkownika.
        if !invoice.notes.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Uwagi").font(.system(size: 10, weight: .semibold))
                Text(invoice.notes)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }

        // Płatność
        VStack(alignment: .leading, spacing: 3) {
            Text("Płatność").font(.system(size: 10, weight: .semibold))
            if let form = invoice.paymentForm {
                Text("Forma płatności: \(form.displayName)")
            }
            if let due = invoice.paymentDueDate {
                Text("Termin płatności: \(FA2Format.dateFormatter.string(from: due))")
            }
            if let account = invoice.paymentBankAccount, !account.isEmpty {
                Text("Rachunek bankowy: \(account)")
            }
            Text(invoice.isPaid ? "Status: opłacona" : "Status: do opłacenia")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)

        // Kody QR wizualizacji KSeF: KOD I (weryfikacja) na każdej fakturze
        // z numerem KSeF lub offline; KOD II (CERTYFIKAT) na dokumentach offline.
        if let qrCodes {
            HStack(alignment: .top, spacing: 24) {
                qrBox(image: qrCodes.verification, label: qrCodes.verificationLabel)
                if let certificate = qrCodes.certificate {
                    qrBox(image: certificate, label: "CERTYFIKAT")
                }
                if let note = qrCodes.certificateNote {
                    Text(note)
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .frame(maxWidth: 200, alignment: .leading)
                }
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    /// Pojedynczy kod QR z podpisem pod spodem.
    private func qrBox(image: CGImage, label: String) -> some View {
        VStack(spacing: 3) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: 84, height: 84)
            Text(label)
                .font(.system(size: 7, weight: .semibold).monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 110)
        }
    }

    private func partyBox(title: String, name: String, nip: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(name).font(.system(size: 11, weight: .semibold))
            if !address.isEmpty {
                Text(address).font(.system(size: 9))
            }
            Text("NIP: \(nip)").font(.system(size: 9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var linesTable: some View {
        let columns = ["Lp.", "Nazwa", "Ilość", "J.m.", "Cena netto", "Wartość netto", "VAT"]
        return VStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    ForEach(columns, id: \.self) { column in
                        Text(column).font(.system(size: 8, weight: .semibold))
                    }
                }
                Divider()
                ForEach(lines, id: \.persistentModelID) { line in
                    GridRow {
                        Text("\(line.index)")
                        Text(line.name).gridColumnAlignment(.leading)
                        Text(FA2Format.quantity(line.quantity))
                        Text(line.unit)
                        Text(FA2Format.amount(line.unitNetPrice))
                        Text(FA2Format.amount(line.netAmount))
                        Text(VATRate(rawValue: line.vatRate)?.displayName ?? line.vatRate)
                    }
                    .font(.system(size: 9))
                }
            }
        }
        .padding(8)
        .overlay(Rectangle().strokeBorder(.gray.opacity(0.4), lineWidth: 0.5))
    }
}

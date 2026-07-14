import SwiftUI
import AppKit

/// Dane dokumentu windykacyjnego (wezwanie do zapłaty / nota odsetkowa).
public struct PaymentDemandDocument {
    public var kind: PaymentDemandKind
    /// Numer własny dokumentu (opcjonalny, drukowany przy tytule).
    public var number: String
    public var date: Date
    public var sellerName: String
    public var sellerAddress: String
    public var sellerNIP: String
    public var bankAccount: String
    public var buyerName: String
    public var buyerNIP: String
    public var buyerAddress: String
    public var items: [PaymentDemandItem]
    public var annualRatePercent: Double
    /// Termin zapłaty z wezwania (dni od otrzymania).
    public var paymentDays: Int

    public init(
        kind: PaymentDemandKind,
        number: String = "",
        date: Date = .now,
        sellerName: String,
        sellerAddress: String,
        sellerNIP: String,
        bankAccount: String,
        buyerName: String,
        buyerNIP: String,
        buyerAddress: String,
        items: [PaymentDemandItem],
        annualRatePercent: Double,
        paymentDays: Int
    ) {
        self.kind = kind
        self.number = number
        self.date = date
        self.sellerName = sellerName
        self.sellerAddress = sellerAddress
        self.sellerNIP = sellerNIP
        self.bankAccount = bankAccount
        self.buyerName = buyerName
        self.buyerNIP = buyerNIP
        self.buyerAddress = buyerAddress
        self.items = items
        self.annualRatePercent = annualRatePercent
        self.paymentDays = paymentDays
    }
}

/// Generator PDF wezwania do zapłaty / noty odsetkowej — jedna strona A4
/// (przy większej liczbie pozycji tabela dzielona na kolejne strony).
@MainActor
public enum PaymentDemandPDFGenerator {

    private static let pageSize = CGSize(width: 595, height: 842)
    /// Pozycji tabeli na stronę (zachowawczo — strona mieści też nagłówek i sumy).
    private static let itemsPerPage = 16

    public static func pdfData(for document: PaymentDemandDocument) -> Data? {
        // Dane do EPU nie są pismem do dłużnika — nie mają wydruku PDF.
        guard document.kind != .epu else { return nil }
        var chunks: [[PaymentDemandItem]] = []
        var remaining = document.items[...]
        repeat {
            chunks.append(Array(remaining.prefix(itemsPerPage)))
            remaining = remaining.dropFirst(min(itemsPerPage, remaining.count))
        } while !remaining.isEmpty

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for (index, chunk) in chunks.enumerated() {
            let page = PaymentDemandPageView(
                document: document,
                items: chunk,
                isFirstPage: index == 0,
                isLastPage: index == chunks.count - 1,
                pageNumber: index + 1,
                pageCount: chunks.count
            )
            .frame(width: pageSize.width - 80)
            .padding(40)
            .background(Color.white)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
            renderer.render { size, render in
                context.beginPDFPage(nil)
                context.translateBy(x: 0, y: pageSize.height - size.height)
                render(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }
}

// MARK: - Strona dokumentu

private struct PaymentDemandPageView: View {
    let document: PaymentDemandDocument
    let items: [PaymentDemandItem]
    let isFirstPage: Bool
    let isLastPage: Bool
    let pageNumber: Int
    let pageCount: Int

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter
    }()

    private var title: String {
        let base = document.kind.displayName.uppercased()
        return document.number.isEmpty ? base : "\(base) NR \(document.number)"
    }

    private var introText: String {
        switch document.kind {
        case .reminder:
            return "Uprzejmie przypominamy, że upłynął termin płatności niżej wymienionych "
                + "faktur. Prosimy o uregulowanie należności w najbliższym możliwym terminie. "
                + "Jeżeli płatność została już zrealizowana, prosimy o zignorowanie "
                + "niniejszego pisma."
        case .demand:
            return "Wzywamy do zapłaty niżej wymienionych, przeterminowanych należności "
                + "wraz z odsetkami za opóźnienie, w terminie \(document.paymentDays) dni "
                + "od dnia otrzymania niniejszego wezwania."
        case .interestNote:
            return "Na podstawie art. 481 Kodeksu cywilnego oraz ustawy o przeciwdziałaniu "
                + "nadmiernym opóźnieniom w transakcjach handlowych naliczamy odsetki "
                + "za opóźnienie w zapłacie niżej wymienionych faktur."
        case .epu:
            return ""
        }
    }

    /// Przypomnienie nie nalicza odsetek — kolumna i sumy odsetek znikają.
    private var showsInterest: Bool { document.kind.includesInterest }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isFirstPage {
                header
                Text(title)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(introText)
                    .font(.system(size: 10))
            } else {
                Text("\(title) — strona \(pageNumber)/\(pageCount)")
                    .font(.caption.weight(.semibold))
            }

            itemsTable

            if isLastPage {
                totals
                footer
            }
            if pageCount > 1 {
                Text("Strona \(pageNumber) z \(pageCount)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(.black)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wierzyciel:").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(document.sellerName).font(.system(size: 10, weight: .semibold))
                if !document.sellerAddress.isEmpty {
                    Text(document.sellerAddress).font(.system(size: 9))
                }
                Text("NIP: \(document.sellerNIP)").font(.system(size: 9))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.dateFormatter.string(from: document.date)).font(.system(size: 9))
                Spacer().frame(height: 8)
                Text("Dłużnik:").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(document.buyerName).font(.system(size: 10, weight: .semibold))
                if !document.buyerAddress.isEmpty {
                    Text(document.buyerAddress).font(.system(size: 9))
                }
                if !document.buyerNIP.isEmpty {
                    Text("NIP: \(document.buyerNIP)").font(.system(size: 9))
                }
            }
        }
    }

    private var itemsTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Lp.")
                Text("Faktura").gridColumnAlignment(.leading)
                Text("Wystawiona")
                Text("Termin")
                Text("Dni zwłoki")
                Text("Należność")
                if showsInterest {
                    Text("Odsetki")
                }
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                GridRow {
                    Text("\((pageNumber - 1) * 16 + offset + 1)")
                    Text(item.invoiceNumber).gridColumnAlignment(.leading)
                    Text(item.issueDate, format: .dateTime.day().month().year())
                    Text(item.dueDate, format: .dateTime.day().month().year())
                    Text("\(item.daysOverdue)")
                    Text(item.outstanding, format: .currency(code: item.currency)).monospacedDigit()
                    if showsInterest {
                        Text(item.interest, format: .currency(code: item.currency)).monospacedDigit()
                    }
                }
                .font(.system(size: 9))
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Divider()
            ForEach(PaymentDemandEngine.totals(of: document.items), id: \.currency) { total in
                let toPay: Double = switch document.kind {
                case .interestNote: total.interest
                case .reminder: total.outstanding
                default: total.outstanding + total.interest
                }
                HStack {
                    Spacer()
                    if document.kind == .demand {
                        Text("Należność główna: ")
                            + Text(total.outstanding, format: .currency(code: total.currency))
                        Text("Odsetki: ")
                            + Text(total.interest, format: .currency(code: total.currency))
                    }
                    (Text("Razem do zapłaty: ")
                        + Text(toPay, format: .currency(code: total.currency)))
                        .fontWeight(.bold)
                }
                .font(.system(size: 10))
                .monospacedDigit()
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsInterest {
                Text("Odsetki naliczono według stopy \(document.annualRatePercent.formatted(.number.precision(.fractionLength(0...2))))% w skali roku, na dzień \(Self.dateFormatter.string(from: document.date)).")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            if !document.bankAccount.isEmpty {
                Text("Wpłaty prosimy kierować na rachunek: \(document.bankAccount)")
                    .font(.system(size: 9, weight: .semibold))
            }
            if document.kind == .demand {
                Text("W przypadku braku zapłaty w wyznaczonym terminie sprawa może zostać skierowana na drogę postępowania sądowego bez ponownego wezwania.")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Spacer().frame(height: 24)
                    Text("………………………………………").font(.system(size: 9))
                    Text("podpis wierzyciela").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

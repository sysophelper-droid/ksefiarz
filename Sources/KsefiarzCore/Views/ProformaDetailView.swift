import SwiftUI
import SwiftData

/// Widok szczegółów faktury proforma — prezentacja danych, eksport PDF,
/// wysyłka e-mailem oraz konwersja do właściwej faktury VAT.
public struct ProformaDetailView: View {

    @Bindable var proforma: Proforma

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditForm = false
    @State private var showingEmailSheet = false
    @State private var showingConvertForm = false
    @State private var showingDeleteConfirmation = false

    public init(proforma: Proforma) {
        self.proforma = proforma
    }

    public var body: some View {
        Form {
            Section("Proforma") {
                LabeledContent("Numer", value: proforma.proformaNumber)
                LabeledContent("Data wystawienia") {
                    Text(proforma.issueDate, style: .date)
                }
                if let validUntil = proforma.validUntil {
                    LabeledContent("Ważna do") {
                        Text(validUntil, style: .date)
                            .foregroundStyle(proforma.isExpired() ? .red : .primary)
                    }
                }
                LabeledContent("Status") {
                    ProformaPaymentBadge(proforma: proforma)
                }
                LabeledContent("Rozliczenie") {
                    if proforma.isConverted {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label("Rozliczona fakturą \(proforma.convertedInvoiceNumber)", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            if let at = proforma.convertedAt {
                                Text(at, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Nierozliczona — dokument handlowy poza KSeF", systemImage: "doc.plaintext")
                            .foregroundStyle(.secondary)
                    }
                }
                if proforma.currency != "PLN" {
                    LabeledContent("Waluta", value: proforma.currency)
                    if proforma.exchangeRate > 0 {
                        LabeledContent(
                            "Kurs PLN",
                            value: proforma.exchangeRate.formatted(.number.precision(.fractionLength(4)))
                        )
                    }
                }
                if let sentAt = proforma.emailSentAt {
                    LabeledContent("Wysłano e-mailem") {
                        Text(sentAt, style: .date)
                            + Text(proforma.emailSentTo.isEmpty ? "" : " → \(proforma.emailSentTo)")
                    }
                }
            }

            Section("Sprzedawca") {
                LabeledContent("Nazwa", value: proforma.sellerName)
                LabeledContent("NIP", value: proforma.sellerNIP)
                if !proforma.sellerAddress.isEmpty {
                    LabeledContent("Adres", value: proforma.sellerAddress)
                }
            }

            Section("Nabywca") {
                LabeledContent("Nazwa", value: proforma.buyerName)
                if !proforma.buyerNIP.isEmpty {
                    LabeledContent("NIP", value: proforma.buyerNIP)
                }
                if !proforma.buyerAddress.isEmpty {
                    LabeledContent("Adres", value: proforma.buyerAddress)
                }
            }

            if !proforma.lines.isEmpty {
                Section("Pozycje") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("Lp.").gridColumnAlignment(.trailing)
                            Text("Nazwa")
                            Text("Ilość").gridColumnAlignment(.trailing)
                            Text("Cena netto").gridColumnAlignment(.trailing)
                            Text("Wartość netto").gridColumnAlignment(.trailing)
                            Text("VAT").gridColumnAlignment(.trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(proforma.sortedLines, id: \.persistentModelID) { line in
                            GridRow {
                                Text("\(line.index)")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if !line.cnPkwiu.isEmpty {
                                        Text("CN/PKWiU: \(line.cnPkwiu)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text("\(FA2Format.quantity(line.quantity)) \(line.unit)")
                                Text(line.unitNetPrice, format: .currency(code: proforma.currency)).monospacedDigit()
                                Text(line.netAmount, format: .currency(code: proforma.currency)).monospacedDigit()
                                Text(VATRate(rawValue: line.vatRate)?.displayName ?? line.vatRate)
                            }
                            .font(.callout)
                        }
                    }
                }
            }

            if !proforma.notes.isEmpty {
                Section("Uwagi") {
                    Text(proforma.notes)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            Section("Kwoty") {
                LabeledContent("Netto") {
                    Text(proforma.netAmount, format: .currency(code: proforma.currency)).monospacedDigit()
                }
                LabeledContent("VAT") {
                    Text(proforma.vatAmount, format: .currency(code: proforma.currency)).monospacedDigit()
                }
                LabeledContent("Brutto") {
                    Text(proforma.grossAmount, format: .currency(code: proforma.currency))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            }

            Section("Płatność") {
                if let form = proforma.paymentForm {
                    LabeledContent("Forma płatności", value: form.displayName)
                }
                if let due = proforma.paymentDueDate {
                    LabeledContent("Termin płatności") {
                        Text(due, style: .date)
                            .foregroundStyle(proforma.isOverdue ? .red : .primary)
                    }
                }
                if let account = proforma.paymentBankAccount, !account.isEmpty {
                    LabeledContent("Rachunek do przelewu") {
                        HStack(spacing: 8) {
                            Text(account)
                                .monospaced()
                                .textSelection(.enabled)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(account, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Skopiuj numer rachunku")
                        }
                    }
                }
            }

            Section("Akcje") {
                HStack(spacing: 12) {
                    Button {
                        proforma.isPaid.toggle()
                    } label: {
                        Label(
                            proforma.isPaid ? "Oznacz jako nieopłaconą" : "Oznacz jako opłaconą",
                            systemImage: proforma.isPaid ? "xmark.circle" : "checkmark.circle"
                        )
                    }
                    Button {
                        showingEmailSheet = true
                    } label: {
                        Label("Wyślij e-mailem", systemImage: "envelope")
                    }
                    .help("Otwórz wiadomość z proformą (PDF) w aplikacji Mail")
                }

                if !proforma.isConverted {
                    HStack(spacing: 12) {
                        Button {
                            showingConvertForm = true
                        } label: {
                            Label("Konwertuj na fakturę VAT", systemImage: "arrow.right.doc.on.clipboard")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Otwiera formularz faktury VAT wypełniony danymi proformy — numer nadany z serii faktur. Po zapisie proforma zostanie oznaczona jako rozliczona.")

                        Button {
                            showingEditForm = true
                        } label: {
                            Label("Edytuj", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                    }
                } else {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Usuń", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(proforma.proformaNumber)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("PDF (polski)") {
                        FileExportService.exportPDF(of: proforma.transientInvoice())
                    }
                    Button("PDF dwujęzyczny (PL/EN)") {
                        FileExportService.exportPDF(of: proforma.transientInvoice(), bilingual: true)
                    }
                } label: {
                    Label("Eksportuj PDF", systemImage: "doc.richtext")
                }
                .help("Zapisz proformę jako PDF — wariant polski albo dwujęzyczny (PL/EN)")
            }
        }
        .sheet(isPresented: $showingEditForm) {
            NewProformaView(editing: proforma)
        }
        .sheet(isPresented: $showingEmailSheet) {
            ProformaEmailView(proforma: proforma)
        }
        .sheet(isPresented: $showingConvertForm) {
            NewInvoiceView(
                initialDraft: proforma.invoiceDraft(),
                sourceTitle: "Faktura z proformy \(proforma.proformaNumber)",
                onCreatedInvoice: { invoice in
                    proforma.markConverted(to: invoice)
                    try? modelContext.save()
                }
            )
        }
        .confirmationDialog(
            "Usunąć proformę \(proforma.proformaNumber)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Usuń", role: .destructive) {
                modelContext.delete(proforma)
                dismiss()
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Proforma to dokument lokalny — usunięcie jest nieodwracalne.")
        }
    }
}

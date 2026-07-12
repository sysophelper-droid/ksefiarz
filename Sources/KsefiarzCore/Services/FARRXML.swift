import Foundation

/// Parametry struktury logicznej używane przy otwieraniu sesji KSeF.
public struct KSeFInvoiceSchema: Equatable, Sendable {
    public var systemCode: String
    public var schemaVersion: String
    public var value: String

    public static let fa3 = KSeFInvoiceSchema(
        systemCode: "FA (3)", schemaVersion: "1-0E", value: "FA"
    )
    public static let faRR = KSeFInvoiceSchema(
        systemCode: "FA_RR (1)", schemaVersion: "1-1E", value: "FA_RR"
    )

    /// Rozpoznaje schemę po nagłówku XML. Jest używane także dla dokumentów
    /// offline, których nie wolno ponownie generować przed dosłaniem.
    public static func detect(in xmlData: Data) -> KSeFInvoiceSchema {
        let xml = String(decoding: xmlData.prefix(8_192), as: UTF8.self)
        if xml.contains("FA_RR (1)")
            || xml.contains(FARRXMLGenerator.namespace) {
            return .faRR
        }
        return .fa3
    }
}

/// Generator osobnej struktury logicznej FA_RR(1) dla faktur VAT RR.
/// Podmiot1 jest dostawcą (rolnikiem ryczałtowym), a Podmiot2 nabywcą,
/// który wystawia dokument w imieniu dostawcy.
public enum FARRXMLGenerator {
    public static let namespace = "http://crd.gov.pl/wzor/2026/03/06/14189/"

    public static func generateXML(for draft: InvoiceDraft, generatedAt: Date = .now) -> String {
        let issueDate = FA2Format.dateFormatter.string(from: draft.issueDate)
        let createdAt = FA2Format.timestampFormatter.string(from: generatedAt)
        let foreign = draft.currency == "PLN" || draft.exchangeRate <= 0
            ? nil : draft.exchangeRate

        func converted(_ value: Double, element: String) -> String {
            guard let rate = foreign else { return "" }
            return "    <\(element)>\(FA2Format.amount(value * rate))</\(element)>\n"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Faktura xmlns="\(namespace)">
          <Naglowek>
            <KodFormularza kodSystemowy="FA_RR (1)" wersjaSchemy="1-1E">FA_RR</KodFormularza>
            <WariantFormularza>1</WariantFormularza>
            <DataWytworzeniaFa>\(createdAt)</DataWytworzeniaFa>
            <SystemInfo>Ksefiarz macOS</SystemInfo>
          </Naglowek>
          <Podmiot1>
            <DaneIdentyfikacyjne>
              <NIP>\(escape(draft.sellerNIP))</NIP>
              <Nazwa>\(escape(draft.sellerName))</Nazwa>
            </DaneIdentyfikacyjne>
            <Adres>
              <KodKraju>PL</KodKraju>
              <AdresL1>\(escape(draft.sellerAddress))</AdresL1>
            </Adres>
          </Podmiot1>
          <Podmiot2>
            <DaneIdentyfikacyjne>
              <NIP>\(escape(draft.buyerNIP))</NIP>
              <Nazwa>\(escape(draft.buyerName))</Nazwa>
            </DaneIdentyfikacyjne>
            <Adres>
              <KodKraju>PL</KodKraju>
              <AdresL1>\(escape(draft.buyerAddress))</AdresL1>
            </Adres>
          </Podmiot2>
          <FakturaRR>
            <KodWaluty>\(escape(draft.currency))</KodWaluty>
        \(acquisitionDate(draft))    <P_4B>\(issueDate)</P_4B>
            <P_4C>\(escape(draft.invoiceNumber))</P_4C>
            <P_11_1>\(FA2Format.amount(draft.netAmount))</P_11_1>
        \(converted(draft.netAmount, element: "P_11_1W"))    <P_11_2>\(FA2Format.amount(draft.vatAmount))</P_11_2>
        \(converted(draft.vatAmount, element: "P_11_2W"))    <P_12_1>\(FA2Format.amount(draft.grossAmount))</P_12_1>
        \(converted(draft.grossAmount, element: "P_12_1W"))    <P_12_2>\(escape(AmountInWords.polishAmount(draft.grossAmount, currencyCode: draft.currency)))</P_12_2>
            <RodzajFaktury>\(draft.correction == nil ? "VAT_RR" : "KOR_VAT_RR")</RodzajFaktury>
        \(correctionBlock(draft))\(linesBlock(draft))\(paymentBlock(draft))  </FakturaRR>
        \(stopkaBlock(draft))</Faktura>
        """
    }

    private static func acquisitionDate(_ draft: InvoiceDraft) -> String {
        guard let date = draft.saleDate else { return "" }
        return "    <P_4A>\(FA2Format.dateFormatter.string(from: date))</P_4A>\n"
    }

    private static func correctionBlock(_ draft: InvoiceDraft) -> String {
        guard let correction = draft.correction else { return "" }
        let originalDate = FA2Format.dateFormatter.string(from: correction.originalIssueDate)
        let numberBlock: String
        if let ksef = correction.originalKsefNumber, !ksef.isEmpty {
            numberBlock = """
                  <NrKSeF>1</NrKSeF>
                  <NrKSeFFaKorygowanej>\(escape(ksef))</NrKSeFFaKorygowanej>
            """
        } else {
            numberBlock = "      <NrKSeFN>1</NrKSeFN>"
        }
        var xml = ""
        if let reason = correction.reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty {
            xml += "    <PrzyczynaKorekty>\(escape(reason))</PrzyczynaKorekty>\n"
        }
        // TypKorekty 2 — korekta ujmowana zgodnie z datą wystawienia korekty
        // (spójnie z generatorem FA(3); pole niesie moment ujęcia w ewidencji).
        xml += "    <TypKorekty>2</TypKorekty>\n"
        xml += """
            <DaneFaKorygowanej>
              <DataWystFaKorygowanej>\(originalDate)</DataWystFaKorygowanej>
              <NrFaKorygowanej>\(escape(correction.originalNumber))</NrFaKorygowanej>
        \(numberBlock)
            </DaneFaKorygowanej>

        """
        return xml
    }

    private static func linesBlock(_ draft: InvoiceDraft) -> String {
        draft.lines.enumerated().map { offset, line in
            let classification = classificationElement(line.cnPkwiu)
            return """
                <FakturaRRWiersz>
                  <NrWierszaFa>\(offset + 1)</NrWierszaFa>
                  <P_5>\(escape(line.name))</P_5>
            \(classification)      <P_6A>\(escape(line.unit))</P_6A>
                  <P_6B>\(FA2Format.decimal(line.quantity, fractionDigits: 6))</P_6B>
                  <P_6C>\(escape(line.rrQuality))</P_6C>
                  <P_7>\(FA2Format.decimal(line.unitNetPrice, fractionDigits: 8))</P_7>
                  <P_8>\(FA2Format.amount(line.netAmount))</P_8>
                  <P_9>\(line.vatRate.rawValue)</P_9>
                  <P_10>\(FA2Format.amount(line.vatAmount))</P_10>
                  <P_11>\(FA2Format.amount(line.grossAmount))</P_11>
            \(exchangeRateElement(draft))    </FakturaRRWiersz>

            """
        }.joined()
    }

    private static func classificationElement(_ code: String) -> String {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let element = value.contains(".") ? "PKWiU" : "CN"
        return "      <\(element)>\(escape(value))</\(element)>\n"
    }

    private static func exchangeRateElement(_ draft: InvoiceDraft) -> String {
        guard draft.currency != "PLN", draft.exchangeRate > 0 else { return "" }
        return "      <KursWaluty>\(FA2Format.decimal(draft.exchangeRate, fractionDigits: 6))</KursWaluty>\n"
    }

    private static func paymentBlock(_ draft: InvoiceDraft) -> String {
        let account = draft.paymentBankAccount.filter(\.isNumber)
        var inner = draft.paymentForm == .transfer
            ? "      <FormaPlatnosci>1</FormaPlatnosci>\n"
            : "      <PlatnoscInna>1</PlatnoscInna>\n      <OpisPlatnosci>\(escape(draft.paymentForm?.displayName ?? "Inna"))</OpisPlatnosci>\n"
        if !account.isEmpty {
            inner += """
                  <RachunekBankowy1>
                    <NrRB>\(escape(account))</NrRB>
                  </RachunekBankowy1>

            """
        }
        return "    <Platnosc>\n\(inner)    </Platnosc>\n"
    }

    private static func stopkaBlock(_ draft: InvoiceDraft) -> String {
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return "" }
        return """
          <Stopka>
            <Informacje>
              <StopkaFaktury>\(escape(notes))</StopkaFaktury>
            </Informacje>
          </Stopka>

        """
    }

    private static func escape(_ value: String) -> String {
        FA2XMLGenerator.escape(value)
    }
}

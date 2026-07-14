import Foundation
import SwiftData

public enum AnonymousInvoiceImportResult: Equatable, Sendable {
    case inserted
    case alreadyExists
}

/// Materializacja faktury pobranej z publicznej bramki anonimowej.
/// Korzysta ze wspólnego scalania synchronizacji, więc deduplikacja obejmuje
/// również faktury ukryte, a ręczny status płatności nie jest cofany.
@MainActor
public enum AnonymousInvoiceImportEngine {
    @discardableResult
    public static func importInvoice(
        xmlData: Data,
        ksefNumber: String,
        prepaidForms: Set<String>,
        context: ModelContext
    ) throws -> AnonymousInvoiceImportResult {
        var invoice = try FA2XMLParser.parse(data: xmlData)
        invoice.ksefId = ksefNumber
        let inserted = try InvoiceSyncEngine.merge(
            [invoice],
            kind: .purchase,
            prepaidForms: prepaidForms,
            context: context
        )
        return inserted == 0 ? .alreadyExists : .inserted
    }
}

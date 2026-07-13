import SwiftData

/// Zatwierdzenie przygotowanego planu importu do SwiftData. Walidacja i
/// mapowanie pozostają w `BulkImportEngine`; serwis odpowiada wyłącznie za
/// materializację modeli i jeden zapis transakcji.
@MainActor
public enum BulkImportService {
    public static func existingKeys(
        contractors: [Contractor],
        products: [Product],
        invoices: [Invoice]
    ) -> BulkImportExistingKeys {
        var productKeys = Set<String>()
        products.forEach {
            productKeys.formUnion(BulkImportEngine.productKeys(sku: $0.sku, ean: $0.ean, name: $0.name))
        }
        var invoiceKeys = Set<String>()
        invoices.forEach {
            invoiceKeys.formUnion(BulkImportEngine.invoiceKeys(
                ksefId: $0.ksefId, kind: $0.kind, number: $0.invoiceNumber,
                sellerNIP: $0.sellerNIP, buyerNIP: $0.buyerNIP
            ))
        }
        return BulkImportExistingKeys(
            contractors: Set(contractors.map {
                BulkImportEngine.contractorKey(nip: $0.nip, name: $0.displayName)
            }),
            products: productKeys,
            invoices: invoiceKeys
        )
    }

    @discardableResult
    public static func apply(_ plan: BulkImportPlan, to context: ModelContext) throws -> Int {
        for item in plan.contractors {
            let contractor = Contractor()
            contractor.name = item.name
            contractor.nameLine2 = item.nameLine2
            contractor.nip = item.nip
            contractor.uePrefix = item.uePrefix
            contractor.isSupplier = item.isSupplier
            contractor.isRecipient = item.isRecipient
            contractor.street = item.street
            contractor.houseNumber = item.houseNumber
            contractor.apartmentNumber = item.apartmentNumber
            contractor.postalCode = item.postalCode
            contractor.city = item.city
            contractor.countryName = item.countryName
            contractor.countryCode = item.countryCode
            contractor.phone1 = item.phone
            contractor.email = item.email
            contractor.invoiceEmail = item.invoiceEmail
            contractor.website = item.website
            contractor.notes = item.notes
            contractor.prefersBilingualDocuments = item.prefersBilingualDocuments
            context.insert(contractor)
        }
        for item in plan.products {
            let product = Product()
            product.name = item.name
            product.type = item.type
            product.unit = item.unit
            product.category = item.category
            product.sku = item.sku
            product.brand = item.brand
            product.ean = item.ean
            product.cnPkwiu = item.cnPkwiu
            product.gtu = item.gtu
            product.isAttachment15 = item.isAttachment15
            product.basePriceNet = item.basePriceNet
            product.basePriceVatRate = item.basePriceVAT
            product.purchasePriceNet = item.purchasePriceNet
            product.purchasePriceVatRate = item.purchasePriceVAT
            context.insert(product)
        }
        for item in plan.invoices {
            let invoice = Invoice(
                ksefId: item.ksefId,
                invoiceNumber: item.invoiceNumber,
                issueDate: item.issueDate,
                sellerName: item.sellerName,
                sellerNIP: item.sellerNIP,
                sellerAddress: item.sellerAddress,
                buyerName: item.buyerName,
                buyerNIP: item.buyerNIP,
                buyerAddress: item.buyerAddress,
                netAmount: item.netAmount,
                vatAmount: item.vatAmount,
                grossAmount: item.grossAmount,
                isPaid: item.isPaid,
                paymentDueDate: item.paymentDueDate,
                paymentForm: item.paymentForm,
                paymentBankAccount: item.paymentBankAccount,
                paymentDate: item.paymentDate,
                documentType: item.documentType,
                ksefSubmissionStatus: item.ksefId == nil ? .local : .accepted,
                notes: item.notes,
                currency: item.currency,
                exchangeRate: item.exchangeRate,
                splitPayment: item.splitPayment,
                kind: item.kind
            )
            invoice.costCategory = item.costCategory
            context.insert(invoice)
            // Relacja po insert — wymagane dla stabilnego zapisu SwiftData.
            invoice.lines = item.lines.enumerated().map { index, line in
                InvoiceLine(
                    index: index + 1,
                    name: line.name,
                    unit: line.unit,
                    quantity: line.quantity,
                    unitNetPrice: line.unitNetPrice,
                    netAmount: line.netAmount,
                    vatRate: line.vatRate,
                    vatAmount: line.vatAmount,
                    cnPkwiu: line.cnPkwiu,
                    gtu: line.gtu
                )
            }
        }
        do {
            try context.save()
            return plan.importCount
        } catch {
            context.rollback()
            throw error
        }
    }
}

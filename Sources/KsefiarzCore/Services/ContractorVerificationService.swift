import Foundation

/// Orkiestruje weryfikację kontrahenta z dwóch niezależnych źródeł:
/// Wykazu podatników VAT („Biała lista”, `ContractorLookupService`) oraz
/// KSeF (uprawnienia podmiotowe otrzymane od kontrahenta). Składa je czystą
/// logiką `ContractorVerification.build`. Awarie źródeł są izolowane — błąd
/// jednego nie przekreśla wyniku drugiego.
public struct ContractorVerificationService {

    private let whiteList: ContractorLookupService
    private let ksef: KSeFService?

    /// - Parameter ksef: klient KSeF albo `nil`, gdy brak poświadczeń
    ///   (wtedy karta pokazuje tylko dane z wykazu VAT).
    public init(
        whiteList: ContractorLookupService = ContractorLookupService(),
        ksef: KSeFService?
    ) {
        self.whiteList = whiteList
        self.ksef = ksef
    }

    /// Weryfikuje kontrahenta po NIP. Nie rzuca — wszystkie błędy źródeł są
    /// odwzorowane w polach wyniku, żeby UI mogło pokazać kartę częściową.
    public func verify(nip rawNIP: String, date: Date = .now) async -> ContractorVerificationResult {
        let nip = rawNIP.filter(\.isNumber)

        // Nieprawidłowy NIP — nie odpytujemy usług; build() zwróci wynik
        // minimalny (ignoruje poniższe wartości dla błędnego NIP).
        guard InvoiceValidator.isValidNIP(nip) else {
            return ContractorVerification.build(nip: nip, whiteList: .notRegistered, ksef: .notChecked)
        }

        let whiteListOutcome = await lookupWhiteList(nip: nip, date: date)
        let ksefOutcome = await queryKSeF(nip: nip)
        return ContractorVerification.build(nip: nip, whiteList: whiteListOutcome, ksef: ksefOutcome)
    }

    private func lookupWhiteList(nip: String, date: Date) async -> ContractorVerification.WhiteListOutcome {
        do {
            let result = try await whiteList.lookup(nip: nip, date: date)
            return .found(statusRaw: result.vatStatus, name: result.name)
        } catch ContractorLookupService.LookupError.notFound {
            return .notRegistered
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func queryKSeF(nip: String) async -> ContractorVerification.KSeFOutcome {
        guard let ksef else { return .notChecked }
        do {
            let grants = try await ksef.receivedAuthorizations(fromNIP: nip)
            return .authorizations(grants)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

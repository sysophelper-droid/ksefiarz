import Foundation

/// Orkiestruje weryfikację kontrahenta unijnego w VIES: odpytuje
/// `VIESLookupService` i składa wynik czystą logiką `VIESVerification.build`.
/// Nie rzuca — błąd usługi jest odwzorowany w polu `error` wyniku, żeby UI
/// mogło pokazać kartę częściową. Odpowiednik `ContractorVerificationService`
/// dla kontrahentów spoza Polski (jedno źródło zamiast dwóch).
public struct VIESVerificationService {

    private let vies: VIESLookupService

    public init(vies: VIESLookupService = VIESLookupService()) {
        self.vies = vies
    }

    /// Weryfikuje kontrahenta UE po kodzie kraju i numerze VAT.
    /// - Parameter requesterNIP: opcjonalny NIP naszej firmy — gdy podany,
    ///   VIES zwraca numer potwierdzenia zapytania (dowód sprawdzenia).
    public func verify(
        countryCode: String,
        vatNumber: String,
        requesterNIP: String? = nil
    ) async -> VIESVerificationResult {
        let cc = VIESVerification.normalizedCountry(countryCode)
        let number = vatNumber.uppercased().filter { $0.isLetter || $0.isNumber }

        // Błędne dane wejściowe — nie odpytujemy VIES; build() zwróci wynik
        // minimalny (ignoruje `outcome` dla niepoprawnych danych).
        guard VIESVerification.viesCountryCodes.contains(cc), !number.isEmpty else {
            return VIESVerification.build(countryCode: cc, vatNumber: number, outcome: .notChecked)
        }

        let outcome: VIESVerification.Outcome
        do {
            let result = try await vies.lookup(countryCode: cc, vatNumber: number, requesterNIP: requesterNIP)
            outcome = result.isValid
                ? .active(
                    name: result.name,
                    address: result.address,
                    consultationNumber: result.consultationNumber,
                    requestDate: result.requestDate
                )
                : .inactive(
                    consultationNumber: result.consultationNumber,
                    requestDate: result.requestDate
                )
        } catch {
            outcome = .error(error.localizedDescription)
        }
        return VIESVerification.build(countryCode: cc, vatNumber: number, outcome: outcome)
    }
}

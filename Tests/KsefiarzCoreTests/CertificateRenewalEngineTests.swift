import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Planowanie odnowień (czysta logika)

@Suite("CertificateRenewalEngine — plan odnowień certyfikatów")
struct CertificateRenewalEngineTests {

    /// Stały punkt w czasie — testy deterministyczne bez zależności od zegara.
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Buduje pola certyfikatu ważnego przez `days` dni od `now` (ujemne =
    /// wygasł tyle dni temu).
    private func info(days: Double, serial: String) -> KSeFCertificate.CertificateInfo {
        KSeFCertificate.CertificateInfo(
            subjectSummary: "Podmiot \(serial)",
            issuerName: "CN=KSeF",
            serialNumberDecimal: "1",
            serialNumberHex: serial,
            validFrom: now.addingTimeInterval(-400 * 86_400),
            validTo: now.addingTimeInterval(days * 86_400)
        )
    }

    @Test("Certyfikaty ważne długo — brak kandydatów")
    func brakKandydatowGdyWazneDlugo() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: 200, serial: "A1"),
            offline: info(days: 300, serial: "B1"),
            now: now
        )
        #expect(candidates.isEmpty)
    }

    @Test("Typ 1 wygasa w progu — kandydat uwierzytelniający")
    func typ1WProgu() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: 20.5, serial: "A1"),
            offline: info(days: 300, serial: "B1"),
            now: now
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.type == .authentication)
        #expect(candidates.first?.reason == .expiringSoon(days: 20))
    }

    @Test("Oba w progu — dwaj kandydaci, typ 1 przed typem 2")
    func obaWProguKolejnosc() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: 25.5, serial: "A1"),
            offline: info(days: 10.5, serial: "B1"),
            now: now
        )
        #expect(candidates.map(\.type) == [.authentication, .offline])
    }

    @Test("Typ 1 wygasł — nic nie da się odnowić (brak podpisującego)")
    func typ1WygaslBlokujeWszystko() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: -1.5, serial: "A1"),
            offline: info(days: 5.5, serial: "B1"),
            now: now
        )
        #expect(candidates.isEmpty)
    }

    @Test("Typ 1 ważny, typ 2 przeterminowany — odnawiamy tylko typ 2")
    func typ2PoTerminieAleTyp1Wazny() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: 200, serial: "A1"),
            offline: info(days: -5.5, serial: "B1"),
            now: now
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.type == .offline)
        #expect(candidates.first?.reason == .expired(days: 5))
    }

    @Test("Brak certyfikatu typu 1 — brak kandydatów (nawet gdy typ 2 wygasa)")
    func brakTyp1BrakKandydatow() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: nil,
            offline: info(days: 5.5, serial: "B1"),
            now: now
        )
        #expect(candidates.isEmpty)
    }

    @Test("Brak jakichkolwiek certyfikatów — brak kandydatów")
    func brakCertyfikatow() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: nil, offline: nil, now: now
        )
        #expect(candidates.isEmpty)
    }

    @Test("Typ 2 nieustawiony — odnawiamy sam typ 1")
    func brakTyp2OdnawiamySamTyp1() {
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: 15.5, serial: "A1"),
            offline: nil,
            now: now
        )
        #expect(candidates.map(\.type) == [.authentication])
    }

    @Test("Podjęta już dziś próba jest pomijana (deduplikacja)")
    func dedupPomijaProbe() {
        let authInfo = info(days: 20.5, serial: "A1")
        let key = CertificateRenewalEngine.dedupKey(type: .authentication, serial: "A1", now: now)
        let candidates = CertificateRenewalEngine.candidates(
            authentication: authInfo,
            offline: info(days: 10.5, serial: "B1"),
            now: now,
            alreadyAttempted: [key]
        )
        // Typ 1 pominięty, zostaje tylko typ 2.
        #expect(candidates.map(\.type) == [.offline])
    }

    @Test("Granica progu jest domknięta — dokładnie tyle dni ile próg to kandydat")
    func granicaProgu() {
        // daysToExpiry == thresholdDays musi kwalifikować (porównanie „<=”).
        let candidates = CertificateRenewalEngine.candidates(
            authentication: info(days: 30, serial: "A1"),
            offline: nil,
            thresholdDays: 30,
            now: now
        )
        #expect(candidates.map(\.type) == [.authentication])
        #expect(candidates.first?.reason == .expiringSoon(days: 30))
        // Dzień powyżej progu (31) już nie kwalifikuje.
        #expect(CertificateRenewalEngine.candidates(
            authentication: info(days: 31, serial: "A1"), offline: nil, thresholdDays: 30, now: now
        ).isEmpty)
    }

    @Test("Własny próg dni jest respektowany")
    func wlasnyProg() {
        let authInfo = info(days: 40.5, serial: "A1")
        #expect(CertificateRenewalEngine.candidates(
            authentication: authInfo, offline: nil, thresholdDays: 30, now: now
        ).isEmpty)
        #expect(CertificateRenewalEngine.candidates(
            authentication: authInfo, offline: nil, thresholdDays: 60, now: now
        ).map(\.type) == [.authentication])
    }

    @Test("Klucz deduplikacji zawiera typ, numer seryjny i dzień")
    func formatKluczaDedup() {
        let key = CertificateRenewalEngine.dedupKey(type: .offline, serial: "DEAD01", now: now)
        #expect(key.hasPrefix("renew|offline|DEAD01|"))
        // Kandydat niesie ten sam klucz, którym potem zapamiętujemy próbę.
        let candidate = CertificateRenewalEngine.candidates(
            authentication: info(days: 100, serial: "A1"),
            offline: info(days: 5.5, serial: "DEAD01"),
            now: now
        ).first
        #expect(candidate?.dedupKey == key)
    }

    @Test("Przycinanie pamięci prób: stare klucze znikają, świeże zostają")
    func przycinaniePamieci() {
        let fresh = CertificateRenewalEngine.dedupKey(type: .authentication, serial: "A1", now: now)
        let old = CertificateRenewalEngine.dedupKey(
            type: .authentication, serial: "A1",
            now: now.addingTimeInterval(-30 * 86_400)
        )
        let pruned = CertificateRenewalEngine.prune(attempted: [fresh, old], now: now)
        #expect(pruned.contains(fresh))
        #expect(!pruned.contains(old))
    }
}

// MARK: - Wykonanie planu (koordynator)

@Suite("CertificateRenewalCoordinator — wykonanie planu odnowień")
@MainActor
struct CertificateRenewalCoordinatorTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Zbiera wywołania zapisu do pęku kluczy (atrapa).
    private final class SaveRecorder {
        var saved: [(certificate: KSeFCertificate, type: KSeFCertificateType)] = []
    }

    private func makeCertificate(serial: String) throws -> KSeFCertificate {
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Odnowiony \(serial)"), .countryName("PL")],
            privateKey: key,
            validTo: now.addingTimeInterval(2 * 365 * 86_400)
        )
        return KSeFCertificate(certificateDER: der, privateKeyDER: try X509Builder.exportPrivateKey(key))
    }

    private func candidate(_ type: KSeFCertificateType, serial: String = "OLD") -> CertificateRenewalEngine.Candidate {
        CertificateRenewalEngine.Candidate(
            type: type,
            reason: .expiringSoon(days: 10),
            dedupKey: CertificateRenewalEngine.dedupKey(type: type, serial: serial, now: now)
        )
    }

    @Test("Sukces zapisuje nowy certyfikat i zwraca wynik pozytywny")
    func sukcesZapisuje() async throws {
        let recorder = SaveRecorder()
        let outcomes = await CertificateRenewalCoordinator.run(
            candidates: [candidate(.authentication), candidate(.offline)],
            renew: { try self.makeCertificate(serial: $0.rawValue) },
            save: { recorder.saved.append(($0, $1)) }
        )
        #expect(outcomes.map(\.type) == [.authentication, .offline])
        #expect(outcomes.map(\.success) == [true, true])
        #expect(recorder.saved.map(\.type) == [.authentication, .offline])
        // Treść powiadomienia niesie datę ważności nowego certyfikatu.
        #expect(outcomes.first?.notificationTitle == "Odnowiono certyfikat KSeF")
    }

    @Test("Niepowodzenie NIE narusza dotychczasowego certyfikatu")
    func niepowodzenieNieZapisuje() async throws {
        struct Zerwane: Error {}
        let recorder = SaveRecorder()
        let outcomes = await CertificateRenewalCoordinator.run(
            candidates: [candidate(.authentication)],
            renew: { _ in throw Zerwane() },
            save: { recorder.saved.append(($0, $1)) }
        )
        #expect(recorder.saved.isEmpty)
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.success == false)
        #expect(outcomes.first?.notificationTitle == "Nie udało się odnowić certyfikatu KSeF")
    }

    @Test("Niepowodzenie wcześniejszego kandydata nie przerywa kolejnych")
    func czescioweNiepowodzenieNiePrzerywa() async throws {
        struct Zerwane: Error {}
        let recorder = SaveRecorder()
        // Typ 1 zawodzi (np. chwilowy błąd sieci), typ 2 musi mimo to zostać
        // odnowiony — logujemy się nadal ważnym STARYM typem 1.
        let outcomes = await CertificateRenewalCoordinator.run(
            candidates: [candidate(.authentication), candidate(.offline)],
            renew: { type in
                if type == .authentication { throw Zerwane() }
                return try self.makeCertificate(serial: type.rawValue)
            },
            save: { recorder.saved.append(($0, $1)) }
        )
        #expect(outcomes.map(\.type) == [.authentication, .offline])
        #expect(outcomes.map(\.success) == [false, true])
        // Zapisany tylko udany typ 2 — nieudany typ 1 niczego nie nadpisał.
        #expect(recorder.saved.map(\.type) == [.offline])
    }

    @Test("Wynik niesie klucz deduplikacji kandydata (zapamiętanie próby)")
    func wynikNiesieKluczDedup() async throws {
        struct Zerwane: Error {}
        let planned = candidate(.offline, serial: "SN1")
        // Nawet po niepowodzeniu klucz wraca, żeby nie ponawiać w tej samej dobie.
        let outcomes = await CertificateRenewalCoordinator.run(
            candidates: [planned],
            renew: { _ in throw Zerwane() },
            save: { _, _ in }
        )
        #expect(outcomes.first?.dedupKey == planned.dedupKey)
    }
}

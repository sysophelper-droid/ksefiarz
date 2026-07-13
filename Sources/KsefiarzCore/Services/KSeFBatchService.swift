import Foundation

// MARK: - Modele sesji wsadowej (API 2.0)

/// Pojedynczy plik faktury przekazywany do wysyłki wsadowej.
public struct KSeFBatchFile: Equatable, Sendable {
    /// Nazwa pliku wewnątrz paczki ZIP (np. `faktura_00001.xml`).
    public let fileName: String
    /// Dokument XML faktury — dokładnie te bajty wchodzą do paczki,
    /// a ich skrót SHA-256 służy do korelacji statusów po przetworzeniu.
    public let content: Data

    public init(fileName: String, content: Data) {
        self.fileName = fileName
        self.content = content
    }
}

/// Status sesji wsadowej (GET /sessions/{referenceNumber}).
/// Kody z OpenAPI: 100 rozpoczęta, 150 w przetwarzaniu, 200 przetworzona
/// pomyślnie, 405–500 błędy paczki (weryfikacja, deszyfrowanie, dekompresja,
/// limit faktur, anulowanie, brak poprawnych faktur).
public struct KSeFBatchSessionStatus: Equatable, Sendable {
    public let code: Int?
    public let description: String
    public let invoiceCount: Int?
    public let successfulInvoiceCount: Int?
    public let failedInvoiceCount: Int?

    /// Sesja zakończona (sukcesem lub błędem) — statusy nie zmienią się same.
    public var isTerminal: Bool { (code ?? 0) >= 200 }
    /// Paczka przetworzona pomyślnie (część faktur nadal mogła zostać odrzucona).
    public var isProcessed: Bool { code == 200 }
    /// Błąd na poziomie całej paczki (faktury nie zostały przyjęte).
    public var isFailed: Bool { (code ?? 0) >= 400 }
}

/// Wynik przetworzenia pojedynczej faktury z sesji wsadowej
/// (GET /sessions/{referenceNumber}/invoices). Korelacja z dokumentem
/// lokalnym odbywa się po `invoiceHash` (zalecenie ksef-docs).
public struct KSeFBatchInvoiceOutcome: Equatable, Sendable {
    /// Numer referencyjny faktury w sesji (do odpytywania o status i UPO).
    public let referenceNumber: String?
    /// Numer własny dokumentu (jeśli KSeF go zwrócił).
    public let invoiceNumber: String?
    /// Skrót SHA-256 (Base64) oryginalnego XML — klucz korelacji.
    public let invoiceHash: String
    /// Nazwa pliku wewnątrz paczki (zwracana dla wysyłki wsadowej).
    public let invoiceFileName: String?
    /// Zinterpretowany wynik przetwarzania (status, kod, numer KSeF, UPO).
    public let result: KSeFInvoiceProcessingResult
}

/// Wynik pełnego przebiegu wysyłki wsadowej.
public struct KSeFBatchSendResult: Sendable {
    /// Numer referencyjny sesji wsadowej — wspólny dla wszystkich faktur paczki.
    public let sessionReferenceNumber: String
    /// Ostatni znany status sesji (może nie być końcowy — przetwarzanie
    /// dużych paczek bywa dłuższe niż budżet odpytywania).
    public let sessionStatus: KSeFBatchSessionStatus
    /// Wyniki per faktura — puste, dopóki sesja nie została przetworzona.
    public let invoiceOutcomes: [KSeFBatchInvoiceOutcome]
}

/// Etapy wysyłki wsadowej — do prezentacji postępu w UI.
public enum KSeFBatchPhase: Equatable, Sendable {
    case openingSession
    case uploadingPart(index: Int, count: Int)
    case closingSession
    case waitingForProcessing(attempt: Int)
    case fetchingResults
}

// MARK: - Kontrakty (testy podstawiają atrapy)

/// Minimalny kontrakt wysyłki wsadowej — widok i silnik logiki nie muszą
/// znać całej usługi KSeF.
public protocol KSeFBatchSending: AnyObject {
    func sendInvoicesBatch(
        files: [KSeFBatchFile],
        schema: KSeFInvoiceSchema,
        offlineMode: Bool,
        onPhase: (@MainActor (KSeFBatchPhase) -> Void)?
    ) async throws -> KSeFBatchSendResult
}

/// Kontrakt odpytywania o stan sesji wsadowej — do domykania wysyłek,
/// których przetwarzanie trwało dłużej niż budżet odpytywania.
public protocol KSeFBatchStatusProviding: AnyObject {
    func fetchBatchSessionStatus(referenceNumber: String) async throws -> KSeFBatchSessionStatus
    func fetchBatchSessionInvoices(referenceNumber: String) async throws -> [KSeFBatchInvoiceOutcome]
}

extension KSeFService: KSeFBatchSending {}
extension KSeFService: KSeFBatchStatusProviding {}

// MARK: - DTO żądań/odpowiedzi

struct OpenBatchSessionRequestDTO: Encodable {
    struct BatchFilePart: Encodable {
        let ordinalNumber: Int
        /// Rozmiar ZASZYFROWANEJ części w bajtach.
        let fileSize: Int
        /// Skrót SHA-256 (Base64) ZASZYFROWANEJ części.
        let fileHash: String
    }
    struct BatchFileInfo: Encodable {
        /// Rozmiar surowego (niezaszyfrowanego) pliku ZIP.
        let fileSize: Int
        /// Skrót SHA-256 (Base64) surowego pliku ZIP.
        let fileHash: String
        let fileParts: [BatchFilePart]
    }
    let formCode: FormCodeDTO
    let batchFile: BatchFileInfo
    let encryption: OpenOnlineSessionRequestDTO.EncryptionInfo
    let offlineMode: Bool
}

struct BatchPartUploadRequestDTO: Decodable {
    let ordinalNumber: Int
    let method: String
    let url: String
    let headers: [String: String]?
}

struct OpenBatchSessionResponseDTO: Decodable {
    let referenceNumber: String
    let partUploadRequests: [BatchPartUploadRequestDTO]
}

struct SessionStatusResponseDTO: Decodable {
    let status: StatusInfoDTO
    let invoiceCount: Int?
    let successfulInvoiceCount: Int?
    let failedInvoiceCount: Int?
}

struct SessionInvoiceItemDTO: Decodable {
    let invoiceNumber: String?
    let ksefNumber: String?
    /// Pola wymagane przez OpenAPI. Dekodowanie ma się nie udać, jeśli
    /// odpowiedź jest niekompletna — pominięcie takiego rekordu mogłoby
    /// fałszywie uznać listę wyników za pełną i dopuścić ponowną wysyłkę.
    let referenceNumber: String
    let invoiceHash: String
    let invoiceFileName: String?
    let acquisitionDate: String?
    let status: StatusInfoDTO
}

struct SessionInvoicesResponseDTO: Decodable {
    let continuationToken: String?
    let invoices: [SessionInvoiceItemDTO]
}

// MARK: - Sesja wsadowa

/// Wysyłka wsadowa (sesja batch/ZIP) zgodnie z ksef-docs `sesja-wsadowa.md`:
/// 1. paczka ZIP ze wszystkimi fakturami (skrót/rozmiar liczone PRZED szyfrowaniem),
/// 2. podział binarny na części ≤100 MB (maks. 50 części, paczka ≤5 GB),
/// 3. szyfrowanie KAŻDEJ części AES-256-CBC (PKCS#7) wspólnym kluczem sesji
///    (IV przekazywany osobno w `encryption.initializationVector` — tak samo
///    jak w sesji interaktywnej; zweryfikowane z klientem referencyjnym CIRFMF),
/// 4. otwarcie sesji `POST /sessions/batch` (formCode, metadane paczki i części,
///    klucz zaszyfrowany RSA-OAEP), 5. upload części pod adresy z
///    `partUploadRequests` (bez tokenu dostępu!), 6. zamknięcie sesji,
/// 7. odpytywanie o status i pobranie wyników per faktura.
extension KSeFService {

    /// Maksymalny rozmiar części paczki PRZED zaszyfrowaniem (limit API: 100 MB).
    public static let batchMaxPartSize = 100_000_000
    /// Maksymalna liczba części paczki (limit API).
    public static let batchMaxPartCount = 50

    /// Pełny przebieg wysyłki wsadowej. Wszystkie dokumenty muszą należeć
    /// do JEDNEJ schemy (formCode sesji) — mieszanie FA(3) i FA_RR(1)
    /// wymaga osobnych sesji.
    public func sendInvoicesBatch(
        files: [KSeFBatchFile],
        schema: KSeFInvoiceSchema,
        offlineMode: Bool = false,
        onPhase: (@MainActor (KSeFBatchPhase) -> Void)? = nil
    ) async throws -> KSeFBatchSendResult {
        guard !files.isEmpty else { throw KSeFError.invalidResponse }
        try await ensureAuthenticated()

        // 1–2. Paczka ZIP i podział na części (czysta logika, testowana osobno).
        let package = try KSeFBatchPackage.build(
            files: files,
            maxPartSize: Self.batchMaxPartSize,
            maxPartCount: Self.batchMaxPartCount
        )

        // 3. Klucz symetryczny sesji + szyfrowanie części.
        let publicKey = try await fetchEncryptionKey(usage: "SymmetricKeyEncryption")
        let aesKey = try KSeFCrypto.randomBytes(32)
        let iv = try KSeFCrypto.randomBytes(16)
        let encryptedKey = try KSeFCrypto.rsaEncryptOAEPSHA256(aesKey, publicKey: publicKey)
        let encryptedParts = try package.parts.map {
            try KSeFCrypto.aesEncryptCBC($0, key: aesKey, iv: iv)
        }

        // 4. Otwarcie sesji wsadowej z deklaracją paczki i części.
        await notify(onPhase, .openingSession)
        let openRequest = OpenBatchSessionRequestDTO(
            formCode: FormCodeDTO(
                systemCode: schema.systemCode,
                schemaVersion: schema.schemaVersion,
                value: schema.value
            ),
            batchFile: .init(
                fileSize: package.zipData.count,
                fileHash: package.zipHashBase64,
                fileParts: encryptedParts.enumerated().map { index, part in
                    .init(
                        ordinalNumber: index + 1,
                        fileSize: part.count,
                        fileHash: KSeFCrypto.sha256Base64(part)
                    )
                }
            ),
            encryption: .init(
                encryptedSymmetricKey: encryptedKey.base64EncodedString(),
                initializationVector: iv.base64EncodedString()
            ),
            offlineMode: offlineMode
        )
        let openData = try await perform(
            path: "sessions/batch",
            method: "POST",
            body: try JSONEncoder().encode(openRequest),
            bearer: try requireAccessToken()
        )
        let session: OpenBatchSessionResponseDTO = try decode(openData)

        // 5. Upload części pod adresy magazynu (łącznik: ordinalNumber).
        let uploads = session.partUploadRequests.sorted { $0.ordinalNumber < $1.ordinalNumber }
        guard uploads.count == encryptedParts.count else {
            throw KSeFError.invalidResponse
        }
        for (index, upload) in uploads.enumerated() {
            await notify(onPhase, .uploadingPart(index: index + 1, count: uploads.count))
            guard upload.ordinalNumber >= 1, upload.ordinalNumber <= encryptedParts.count else {
                throw KSeFError.invalidResponse
            }
            try await uploadBatchPart(upload, data: encryptedParts[upload.ordinalNumber - 1])
        }

        // 6. Zamknięcie sesji — start przetwarzania i generowania UPO.
        await notify(onPhase, .closingSession)
        var closeWasConfirmed = true
        do {
            _ = try await perform(
                path: "sessions/batch/\(session.referenceNumber)/close",
                method: "POST",
                body: nil,
                bearer: try requireAccessToken()
            )
        } catch {
            // Po wysłaniu wszystkich części odpowiedź na POST /close jest
            // transakcyjnie niejednoznaczna: serwer mógł przyjąć zamknięcie,
            // a połączenie zerwać przed odpowiedzią. Nie wolno zgubić numeru
            // sesji i zostawić dokumentów jako lokalnych, bo ponowna wysyłka
            // mogłaby utworzyć duplikaty. Status sesji rozstrzygnie to teraz
            // albo podczas późniejszej synchronizacji; pewny błąd paczki
            // przywróci dokumenty do stanu lokalnego.
            closeWasConfirmed = false
        }

        // 7. Oczekiwanie na koniec przetwarzania. Od chwili zamknięcia sesji
        // paczka jest już przekazana do KSeF, więc błąd sieci przy odpytywaniu
        // NIE może wywrócić wysyłki wyjątkiem — dokumenty muszą zostać
        // oznaczone jako „w toku” z numerem sesji (inaczej ponowna wysyłka
        // groziłaby duplikatami); domknięciem zajmie się synchronizacja.
        var status = KSeFBatchSessionStatus(
            code: nil,
            description: closeWasConfirmed
                ? "Paczka przekazana do przetworzenia."
                : "Nie udało się potwierdzić zamknięcia sesji — status zostanie sprawdzony ponownie.",
            invoiceCount: nil,
            successfulInvoiceCount: nil,
            failedInvoiceCount: nil
        )
        for attempt in 0..<maxPollAttempts {
            await notify(onPhase, .waitingForProcessing(attempt: attempt + 1))
            if let fresh = try? await fetchBatchSessionStatus(
                referenceNumber: session.referenceNumber
            ) {
                status = fresh
            }
            if status.isTerminal { break }
            if attempt < maxPollAttempts - 1, pollInterval > 0 {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }

        // 8. Wyniki per faktura — tylko dla sesji zakończonej. Błąd pobrania
        // listy nie unieważnia wysyłki (statusy można pobrać później).
        var outcomes: [KSeFBatchInvoiceOutcome] = []
        if status.isTerminal {
            await notify(onPhase, .fetchingResults)
            outcomes = (try? await fetchBatchSessionInvoices(
                referenceNumber: session.referenceNumber
            )) ?? []
        }

        return KSeFBatchSendResult(
            sessionReferenceNumber: session.referenceNumber,
            sessionStatus: status,
            invoiceOutcomes: outcomes
        )
    }

    /// Przesyła jedną zaszyfrowaną część paczki pod adres z `partUploadRequests`.
    /// Żądanie idzie wprost do magazynu danych: dokładnie wskazana metoda,
    /// adres i nagłówki, treścią są surowe bajty części — BEZ tokenu dostępu.
    func uploadBatchPart(_ upload: BatchPartUploadRequestDTO, data: Data) async throws {
        guard let url = URL(string: upload.url) else {
            throw KSeFError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = upload.method
        request.httpBody = data
        for (header, value) in upload.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let (body, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            let details = String(decoding: body.prefix(300), as: UTF8.self)
            throw KSeFError.badStatus(code: response.statusCode, message: details)
        }
    }

    /// Bieżący status sesji (wsadowej lub interaktywnej) z licznikami faktur.
    public func fetchBatchSessionStatus(
        referenceNumber: String
    ) async throws -> KSeFBatchSessionStatus {
        try await ensureAuthenticated()
        let data = try await perform(
            path: "sessions/\(referenceNumber)",
            method: "GET",
            body: nil,
            bearer: try requireAccessToken()
        )
        let response: SessionStatusResponseDTO = try decode(data)
        let details = ([response.status.description] + (response.status.details ?? []))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return KSeFBatchSessionStatus(
            code: response.status.code,
            description: details.isEmpty ? "Sesja w przetwarzaniu." : details,
            invoiceCount: response.invoiceCount,
            successfulInvoiceCount: response.successfulInvoiceCount,
            failedInvoiceCount: response.failedInvoiceCount
        )
    }

    /// Pobiera wyniki wszystkich faktur sesji (stronicowanie: nagłówek
    /// `x-continuation-token` w żądaniu, token kolejnej strony w treści).
    public func fetchBatchSessionInvoices(
        referenceNumber: String
    ) async throws -> [KSeFBatchInvoiceOutcome] {
        try await ensureAuthenticated()
        var outcomes: [KSeFBatchInvoiceOutcome] = []
        var continuationToken: String?
        var seenContinuationTokens = Set<String>()
        // Twardy limit stron — obrona przed zapętleniem na wadliwym tokenie.
        for _ in 0..<200 {
            var headers: [String: String] = [:]
            if let continuationToken {
                headers["x-continuation-token"] = continuationToken
            }
            let data = try await perform(
                path: "sessions/\(referenceNumber)/invoices?pageSize=1000",
                method: "GET",
                body: nil,
                bearer: try requireAccessToken(),
                extraHeaders: headers
            )
            let page: SessionInvoicesResponseDTO = try decode(data)
            guard page.invoices.allSatisfy({
                !$0.referenceNumber.isEmpty && !$0.invoiceHash.isEmpty
            }) else {
                throw KSeFError.invalidResponse
            }
            outcomes.append(contentsOf: page.invoices.map(Self.outcome(from:)))
            guard let next = page.continuationToken, !next.isEmpty else { return outcomes }
            guard seenContinuationTokens.insert(next).inserted else {
                throw KSeFError.invalidResponse
            }
            continuationToken = next
        }
        // Lista nie została domknięta w bezpiecznym budżecie stron. Zwrócenie
        // częściowych danych mogłoby cofnąć brakujące dokumenty do lokalnych.
        throw KSeFError.invalidResponse
    }

    /// Mapuje wpis sesji na wynik domenowy — te same reguły co przy sesji
    /// interaktywnej: numer KSeF = przyjęta, kod ≥ 400 = odrzucona,
    /// pozostałe = w przetwarzaniu. Pola wymagane przez OpenAPI (w tym skrót,
    /// referencja i status) są dekodowane rygorystycznie, bo bez nich nie ma
    /// bezpiecznej korelacji z dokumentem lokalnym.
    static func outcome(from item: SessionInvoiceItemDTO) -> KSeFBatchInvoiceOutcome {
        let code = item.status.code
        let details = ([item.status.description] + (item.status.details ?? []))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let description = details.isEmpty
            ? "Faktura oczekuje na przetworzenie przez KSeF."
            : details
        let acquisitionDate = item.acquisitionDate.flatMap(Self.parseKSeFTimestamp)

        let result: KSeFInvoiceProcessingResult
        if let number = item.ksefNumber {
            result = KSeFInvoiceProcessingResult(
                status: .accepted,
                statusCode: code,
                description: description,
                ksefNumber: number,
                acquisitionDate: acquisitionDate
            )
        } else if code >= 400 {
            result = KSeFInvoiceProcessingResult(
                status: .rejected,
                statusCode: code,
                description: description
            )
        } else {
            result = KSeFInvoiceProcessingResult(
                status: .processing,
                statusCode: code,
                description: description
            )
        }
        return KSeFBatchInvoiceOutcome(
            referenceNumber: item.referenceNumber,
            invoiceNumber: item.invoiceNumber,
            invoiceHash: item.invoiceHash,
            invoiceFileName: item.invoiceFileName,
            result: result
        )
    }

    /// Parsuje znacznik czasu KSeF. API zwraca daty ISO 8601 z ułamkami
    /// sekund o zmiennej liczbie cyfr (np. `12:24:16.0154302+00:00`), których
    /// systemowy parser nie akceptuje — ułamek jest wtedy przycinany do 3 cyfr.
    static func parseKSeFTimestamp(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: raw) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        guard let dotIndex = raw.firstIndex(of: ".") else { return nil }
        let fractionStart = raw.index(after: dotIndex)
        guard let fractionEnd = raw[fractionStart...].firstIndex(where: { !$0.isNumber }),
              raw.distance(from: fractionStart, to: fractionEnd) > 3 else {
            return nil
        }
        let trimmed = String(raw[..<raw.index(fractionStart, offsetBy: 3)])
            + String(raw[fractionEnd...])
        return ISO8601DateFormatter.withFractionalSeconds.date(from: trimmed)
    }

    /// Przekazuje etap przepływu do obserwatora postępu (jeśli podano).
    private func notify(
        _ onPhase: (@MainActor (KSeFBatchPhase) -> Void)?,
        _ phase: KSeFBatchPhase
    ) async {
        guard let onPhase else { return }
        await MainActor.run { onPhase(phase) }
    }
}

extension ISO8601DateFormatter {
    /// KSeF zwraca daty z ułamkami sekund (`2025-09-18T12:24:16.0154302+00:00`),
    /// których domyślny ISO8601DateFormatter nie akceptuje.
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

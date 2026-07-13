import Foundation

/// Paczka faktur dla sesji wsadowej KSeF: pojedynczy plik ZIP z dokumentami
/// XML, podzielony binarnie na części. Czysta logika (bez sieci i krypto):
/// skrót i rozmiar całej paczki liczy się PRZED szyfrowaniem, a szyfrowane są
/// dopiero poszczególne części (w `KSeFBatchService`).
///
/// Limity API (OpenAPI KSeF 2.0): paczka ≤ 5 GB, część ≤ 100 MB przed
/// zaszyfrowaniem, maks. 50 części. Zapis ZIP metodą „store" (`ZipWriter`)
/// jest poprawnym archiwum ZIP; dokumenty XML są małe, a KSeF wymaga
/// jedynie zgodności z formatem, nie kompresji.
public struct KSeFBatchPackage: Equatable, Sendable {

    /// Surowe (niezaszyfrowane) archiwum ZIP z fakturami.
    public let zipData: Data
    /// Skrót SHA-256 (Base64) surowego archiwum — pole `batchFile.fileHash`.
    public let zipHashBase64: String
    /// Części archiwum po podziale binarnym (przed zaszyfrowaniem).
    public let parts: [Data]

    /// Buduje paczkę z plików faktur i dzieli ją na części.
    /// - Throws: `KSeFError.batchPackageFailed` przy pustej liście plików
    ///   albo przekroczeniu limitów paczki.
    public static func build(
        files: [KSeFBatchFile],
        maxPartSize: Int = 100_000_000,
        maxPartCount: Int = 50,
        now: Date = .now
    ) throws -> KSeFBatchPackage {
        guard !files.isEmpty else {
            throw KSeFError.batchPackageFailed("paczka nie zawiera żadnych dokumentów.")
        }

        var writer = ZipWriter()
        for file in files {
            writer.addFile(path: file.fileName, data: file.content, date: now)
        }
        let zipData = writer.finalized()

        // Limit API to 5 GB, ale `ZipWriter` używa 32-bitowych offsetów
        // (klasyczny ZIP bez rozszerzenia ZIP64) — powyżej 4 GB archiwum
        // byłoby uszkodzone, więc granica jest niższa i jawna.
        let maxZipSize = 4_000_000_000
        guard zipData.count <= maxZipSize else {
            throw KSeFError.batchPackageFailed(
                "paczka przekracza 4 GB — podziel wysyłkę na mniejsze partie."
            )
        }

        let parts = splitParts(zipData, maxPartSize: maxPartSize)
        guard parts.count <= maxPartCount else {
            throw KSeFError.batchPackageFailed(
                "paczka wymaga \(parts.count) części — limit KSeF to \(maxPartCount). Podziel wysyłkę na mniejsze partie."
            )
        }

        return KSeFBatchPackage(
            zipData: zipData,
            zipHashBase64: KSeFCrypto.sha256Base64(zipData),
            parts: parts
        )
    }

    /// Podział binarny na możliwie równe części nie większe niż `maxPartSize`
    /// — ta sama arytmetyka co w kliencie referencyjnym CIRFMF
    /// (`partCount = ⌈size/max⌉`, `partSize = ⌈size/partCount⌉`).
    static func splitParts(_ data: Data, maxPartSize: Int) -> [Data] {
        guard !data.isEmpty, maxPartSize > 0 else { return data.isEmpty ? [] : [data] }
        guard data.count > maxPartSize else { return [data] }

        let partCount = (data.count + maxPartSize - 1) / maxPartSize
        let partSize = (data.count + partCount - 1) / partCount

        var parts: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data.index(start, offsetBy: partSize, limitedBy: data.endIndex)
                ?? data.endIndex
            // Kopia bajtów (nie slice) — indeksy części zaczynają się od zera,
            // a dalsze operacje (szyfrowanie, skróty) zakładają pełny bufor.
            parts.append(Data(data[start..<end]))
            start = end
        }
        return parts
    }
}

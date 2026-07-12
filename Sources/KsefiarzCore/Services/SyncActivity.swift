import Foundation
import Combine
import SwiftData

/// Współdzielony stan synchronizacji — obserwowany przez pasek boczny
/// głównego okna i ikonę w pasku menu (obie strony pokazują ten sam
/// przebieg, niezależnie od tego, kto go uruchomił).
@MainActor
public final class SyncActivity: ObservableObject {

    public static let shared = SyncActivity()

    /// Czy trwa synchronizacja (automatyczna albo ręczna z paska menu).
    @Published public var isSyncing = false
    /// Ostatni błąd synchronizacji uruchomionej z paska menu.
    @Published public var lastError: String?
    /// Liczniki dla ikony paska menu — odświeżane przy przebiegach
    /// synchronizacji i przy otwarciu menu (nil przed pierwszym odczytem).
    @Published public var menuBarStatus: MenuBarStatus?

    private init() {}

    /// Przelicza liczniki paska menu z aktualnego stanu bazy.
    public func refreshMenuBarStatus(invoices: [Invoice]) {
        menuBarStatus = MenuBarStatus(invoices: invoices)
    }
}

/// Ręczna synchronizacja „wszystko naraz” dla paska menu: domknięcie
/// wysyłek (kolejka offline + statusy + UPO) oraz pobranie faktur
/// sprzedażowych i zakupowych z zakresu dat z Ustawień. Działa jak przycisk
/// „Pobierz z KSeF” na listach — na dowolnym środowisku, wyzwalacz ręczny.
@MainActor
public enum QuickSyncRunner {

    public static func syncAll(context: ModelContext) async {
        let activity = SyncActivity.shared
        guard !activity.isSyncing else { return }

        let defaults = UserDefaults.standard
        let nip = defaults.string(forKey: AppSettingsKeys.nip) ?? ""
        let environmentRaw = defaults.string(forKey: AppSettingsKeys.environment)
            ?? KSeFEnvironment.test.rawValue
        let token = TokenStore.shared.token
        let certificate = KSeFCertificateStore.shared.authenticationCertificate
        guard !nip.isEmpty, !token.isEmpty || certificate != nil else {
            activity.lastError = KSeFError.missingCredentials.localizedDescription
            return
        }

        activity.isSyncing = true
        activity.lastError = nil
        defer { activity.isSyncing = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(
            environment: environment, nip: nip,
            authToken: token, certificate: certificate
        )

        let allInvoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        await SyncCenter.reconcileSubmissions(
            invoices: allInvoices,
            environmentRaw: environmentRaw,
            trigger: .manual,
            using: service,
            context: context
        )

        // Zakres importu z Ustawień; brak zapisanych granic własnego
        // zakresu → ostatnie 30 dni (jak wartości domyślne @AppStorage).
        let rangeMode = DateRangeMode(
            rawValue: defaults.string(forKey: AppSettingsKeys.rangeMode) ?? ""
        ) ?? .last3Months
        let fromInterval = defaults.double(forKey: AppSettingsKeys.rangeFrom)
        let toInterval = defaults.double(forKey: AppSettingsKeys.rangeTo)
        let range = DateRangeResolver.range(
            mode: rangeMode,
            customFrom: fromInterval > 0
                ? Date(timeIntervalSince1970: fromInterval)
                : Date.now.addingTimeInterval(-30 * 86_400),
            customTo: toInterval > 0 ? Date(timeIntervalSince1970: toInterval) : .now
        )
        let prepaidForms = PaymentFormPolicy.decode(
            defaults.string(forKey: AppSettingsKeys.prepaidForms)
                ?? PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)
        )

        do {
            for kind in [Invoice.Kind.sales, .purchase] {
                try await InvoiceSyncEngine.sync(
                    kind: kind,
                    service: service,
                    from: range.from,
                    to: range.to,
                    prepaidForms: prepaidForms,
                    context: context,
                    trigger: .manual,
                    environmentRaw: environmentRaw
                )
            }
        } catch {
            activity.lastError = error.localizedDescription
        }

        activity.refreshMenuBarStatus(
            invoices: (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        )
    }
}

import SwiftUI

/// Sekcja „Uprawnienia” — nadawanie i odbieranie uprawnień KSeF (np. biuru
/// rachunkowemu po NIP) oraz przegląd dostępów. Dane są pobierane na żywo
/// z API permissions (bez utrwalania lokalnie — źródłem prawdy jest KSeF).
public struct PermissionsView: View {

    @ObservedObject private var tokenStore = TokenStore.shared
    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue

    @State private var permissions: [KSeFPermissionGrant] = []
    @State private var authorizations: [KSeFAuthorizationGrant] = []
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var revokingIDs: Set<String> = []
    @State private var showGrantSheet = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var pendingRevoke: RevokeTarget?

    public init() {}

    private var environment: KSeFEnvironment {
        KSeFEnvironment(rawValue: environmentRaw) ?? .test
    }

    private var hasCredentials: Bool {
        !myNIP.isEmpty
            && (!tokenStore.token.isEmpty
                || KSeFCertificateStore.shared.authenticationCertificate != nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Uprawnienia KSeF")
        .toolbar {
            ToolbarItem {
                Button {
                    showGrantSheet = true
                } label: {
                    Label("Nadaj uprawnienie", systemImage: "person.badge.plus")
                }
                .disabled(!hasCredentials)
                .help("Nadaj uprawnienie osobie lub podmiotowi (np. biuru rachunkowemu)")
            }
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Odśwież", systemImage: "arrow.clockwise")
                }
                // Blokada także w trakcie odbierania — ręczne odświeżenie
                // w oknie revoke pobrałoby listę sprzed usunięcia i wygrało
                // ze strażnikiem reentrancji w load() wywołanym z revoke().
                .disabled(!hasCredentials || isLoading || !revokingIDs.isEmpty)
            }
        }
        .sheet(isPresented: $showGrantSheet) {
            GrantPermissionSheet { draft in
                try await grant(draft)
            }
        }
        .task {
            if hasCredentials, !didLoad { await load() }
        }
        .alert(
            "Błąd uprawnień KSeF",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            pendingRevoke?.confirmationTitle ?? "",
            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
            titleVisibility: .visible
        ) {
            Button("Odbierz uprawnienie", role: .destructive) {
                if let target = pendingRevoke {
                    Task { await revoke(target) }
                }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Ta operacja odbierze dostęp w KSeF. Można go później nadać ponownie.")
        }
    }

    // MARK: Nagłówek

    private var header: some View {
        HStack(spacing: 8) {
            Label("Środowisko: \(environment.displayName)", systemImage: "server.rack")
            if isLoading {
                Text("•")
                ProgressView().controlSize(.small)
                Text("Wczytuję…")
            } else if let info = infoMessage {
                Text("•")
                Text(info)
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding()
    }

    // MARK: Zawartość

    @ViewBuilder
    private var content: some View {
        if !hasCredentials {
            ContentUnavailableView(
                "Brak poświadczeń KSeF",
                systemImage: "key.slash",
                description: Text("Uzupełnij NIP oraz token lub certyfikat KSeF w Ustawieniach, aby zarządzać uprawnieniami.")
            )
        } else if !didLoad {
            ContentUnavailableView(
                "Uprawnienia KSeF",
                systemImage: "person.2.badge.key",
                description: Text("Wczytywanie listy dostępów…")
            )
        } else {
            List {
                permissionsSection
                authorizationsSection
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section("Uprawnienia do pracy w KSeF") {
            if permissions.isEmpty {
                Text("Brak nadanych uprawnień do pracy w KSeF.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(permissions) { grant in
                    PermissionRow(
                        title: grant.subjectLabel,
                        scope: grant.scopeLabel,
                        description: grant.description,
                        startDate: grant.startDate,
                        badges: badges(for: grant),
                        isRevoking: revokingIDs.contains(grant.id)
                    ) {
                        pendingRevoke = .permission(grant)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authorizationsSection: some View {
        Section("Uprawnienia podmiotowe") {
            if authorizations.isEmpty {
                Text("Brak nadanych uprawnień podmiotowych.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(authorizations) { grant in
                    PermissionRow(
                        title: grant.subjectLabel,
                        scope: grant.scopeLabel,
                        description: grant.description,
                        startDate: grant.startDate,
                        badges: [],
                        isRevoking: revokingIDs.contains(grant.id)
                    ) {
                        pendingRevoke = .authorization(grant)
                    }
                }
            }
        }
    }

    private func badges(for grant: KSeFPermissionGrant) -> [PermissionRow.Badge] {
        var result: [PermissionRow.Badge] = []
        if !grant.isActive { result.append(.init(text: "Nieaktywne", color: .orange)) }
        if grant.canDelegate { result.append(.init(text: "Może delegować", color: .blue)) }
        return result
    }

    // MARK: Operacje

    @MainActor
    private func load() async {
        guard hasCredentials, !isLoading else { return }
        isLoading = true
        infoMessage = nil
        defer { isLoading = false; didLoad = true }

        let service = makeService()
        do {
            // Sekwencyjnie, nie równolegle: KSeFService nie jest aktorem —
            // dwa jednoczesne wywołania ścigałyby się o `accessToken`
            // i uruchamiały dwa uwierzytelnienia. Pierwsze zapytanie loguje,
            // drugie korzysta z gotowego tokenu.
            permissions = try await service.queryGrantedPermissions()
            authorizations = try await service.queryAuthorizationGrants()
            let total = permissions.count + authorizations.count
            // „Wpisów”, nie „aktywnych” — lista zawiera też uprawnienia
            // nieaktywne (permissionState=Inactive), oznaczone plakietką.
            infoMessage = total == 0
                ? "Nie nadano jeszcze żadnych uprawnień."
                : "Wpisów: \(total)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func grant(_ draft: PermissionGrantDraft) async throws {
        let service = makeService()
        try await service.grantPermission(draft)
        await load()
    }

    @MainActor
    private func revoke(_ target: RevokeTarget) async {
        let id = target.id
        guard !revokingIDs.contains(id) else { return }
        revokingIDs.insert(id)
        defer { revokingIDs.remove(id) }

        let service = makeService()
        do {
            switch target {
            case .permission:
                try await service.revokePermission(id: id)
            case .authorization:
                try await service.revokeAuthorizationPermission(id: id)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeService() -> KSeFService {
        KSeFService(
            environment: environment,
            nip: myNIP,
            authToken: tokenStore.token,
            certificate: KSeFCertificateStore.shared.authenticationCertificate
        )
    }

    /// Cel operacji odebrania — rozróżnia listę uprawnień (revoke „common”)
    /// od uprawnień podmiotowych (revoke „authorizations”).
    enum RevokeTarget {
        case permission(KSeFPermissionGrant)
        case authorization(KSeFAuthorizationGrant)

        var id: String {
            switch self {
            case .permission(let grant): return grant.id
            case .authorization(let grant): return grant.id
            }
        }

        var confirmationTitle: String {
            switch self {
            case .permission(let grant): return "Odebrać uprawnienie: \(grant.subjectLabel)?"
            case .authorization(let grant): return "Odebrać uprawnienie podmiotowe: \(grant.subjectLabel)?"
            }
        }
    }
}

// MARK: - Wiersz uprawnienia

/// Wiersz listy uprawnień: podmiot, zakres, opis i przycisk odebrania.
private struct PermissionRow: View {
    struct Badge: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
    }

    let title: String
    let scope: String
    let description: String
    let startDate: Date?
    let badges: [Badge]
    let isRevoking: Bool
    let revoke: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    ForEach(badges) { badge in
                        Text(badge.text)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(badge.color.opacity(0.2), in: Capsule())
                            .foregroundStyle(badge.color)
                    }
                }
                Text(scope)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let startDate {
                    Text("Od \(Self.dateFormatter.string(from: startDate))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                revoke()
            } label: {
                if isRevoking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Odbierz", systemImage: "person.badge.minus")
                }
            }
            .disabled(isRevoking)
            .help("Odbierz to uprawnienie w KSeF")
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    PermissionsView()
}

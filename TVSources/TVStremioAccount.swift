import SwiftUI
import Security

@MainActor final class TVStremioAccount: ObservableObject {
    static let shared = TVStremioAccount()
    @Published private(set) var credentials: StremioCredentials?
    @Published private(set) var busy = false
    @Published var message: String?
    private var revision = UUID()
    private let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.kairo.player.tvos.stremio", kSecAttrAccount as String: "account"]
    var api: StremioAPI {
        var value = StremioAPI()
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HARBOR_TEST_STREMIO_API"], let url = URL(string: raw), ["localhost", "127.0.0.1"].contains(url.host ?? "") { value.base = url }
        #endif
        return value
    }
    private init() {
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let data = result as? Data { credentials = try? JSONDecoder().decode(StremioCredentials.self, from: data) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["HARBOR_TEST_ACCOUNT"] == "fixture-only", api.base.host == "127.0.0.1" {
            credentials = StremioCredentials(authKey: "fixture-only", email: "fixture@example.invalid", addons: [])
        }
        #endif
    }
    private func store(_ value: StremioCredentials) throws {
        let data = try JSONEncoder().encode(value)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw StremioAPI.Failure.network }
        } else if update != errSecSuccess { throw StremioAPI.Failure.network }
    }
    func login(email: String, password: String) async {
        guard !busy else { return }; busy = true; message = nil
        let token = revision
        defer { busy = false }
        do {
            let value = try await api.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            guard token == revision, !Task.isCancelled else { return }
            try store(value); credentials = value
        } catch { if token == revision { message = error.localizedDescription } }
    }
    func refresh() async {
        guard !busy, var value = credentials else { return }; busy = true; message = nil
        let token = revision
        defer { busy = false }
        do {
            value.addons = try await api.addons(value.authKey)
            guard token == revision, !Task.isCancelled else { return }
            #if DEBUG
            if value.authKey != "fixture-only" { try store(value) }
            #else
            try store(value)
            #endif
            credentials = value
        } catch { if token == revision { message = error.localizedDescription } }
    }
    func logout() {
        revision = UUID(); SecItemDelete(query as CFDictionary)
        credentials = nil; message = nil
    }
    func save(_ request: PlaybackRequest, videoID: String, position: Double, duration: Double, completed: Bool) async {
        guard let value = credentials else { return }
        do { try await api.saveProgress(key: value.authKey, request: request, videoID: videoID, position: position, duration: duration, completed: completed) }
        catch { message = "Die Abspielposition konnte nicht mit Stremio synchronisiert werden." }
    }
}

struct TVStremioLogin: View {
    @ObservedObject private var account = TVStremioAccount.shared
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        TVSheet(title: "Stremio-Konto") {
            if let value = account.credentials {
                Text("Angemeldet als \(value.email)")
                Text("\(value.addons.count) installierte Addons übernommen").accessibilityIdentifier("stremioAddonCount")
                ForEach(Array(value.addons.enumerated()), id: \.offset) { _, addon in Text(addon.manifest.name).foregroundStyle(.secondary) }
                Button("Addons aktualisieren") { Task { await account.refresh() } }.disabled(account.busy)
                Button("Abmelden") { account.logout() }
            } else {
                TextField("E-Mail", text: $email).textContentType(.username).autocorrectionDisabled().accessibilityIdentifier("stremioEmail")
                SecureField("Passwort", text: $password).textContentType(.password).accessibilityIdentifier("stremioPassword")
                Button("Anmelden & Addons übernehmen") {
                    let secret = password; password = ""
                    Task { await account.login(email: email, password: secret) }
                }.disabled(account.busy || email.isEmpty || password.isEmpty).accessibilityIdentifier("stremioLogin")
            }
            if account.busy { ProgressView("Verbinden …") }
            if let message = account.message { Text(message).foregroundStyle(.secondary) }
            Text("Dein Passwort wird nicht gespeichert. Konto-Schlüssel und Addon-Konfigurationen liegen im Schlüsselbund. Für den Folgenwechsel benötigt ein Addon direkt abspielbare HTTP-Streams; reine Torrent-Links benötigen einen Streaming-Server.").font(.callout).foregroundStyle(.secondary)
        }.onDisappear { password = "" }
    }
}

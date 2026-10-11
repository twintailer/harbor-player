import SwiftUI
import Security

@MainActor final class IOSStremioAccount: ObservableObject {
    static let shared = IOSStremioAccount()
    @Published private(set) var credentials: StremioCredentials?
    @Published private(set) var busy = false
    @Published var message: String?
    private var revision = UUID()
    private let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.harbor.player.stremio", kSecAttrAccount as String: "account"]
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
    func resumed(_ request: PlaybackRequest) async -> PlaybackRequest {
        // An explicit link position (including a deliberate restart at zero) wins.
        guard !request.startSupplied, request.start == 0, request.progressVideoID != nil, let value = credentials else { return request }
        let token = revision
        do {
            guard let records = try await api.post("datastoreGet", ["authKey": value.authKey, "collection": "libraryItem", "ids": [request.contentID], "all": false]) as? [[String: Any]] else { throw StremioAPI.Failure.network }
            guard token == revision, !Task.isCancelled else { return request }
            var result = request
            if let position = records.compactMap({ StremioProgress.seconds(record: $0, request: request) }).first { result.start = position }
            return result
        } catch {
            if token == revision { message = "Der gespeicherte Stremio-Fortschritt konnte nicht geladen werden. Die Position im Startlink wird verwendet." }
            return request
        }
    }
    func save(_ request: PlaybackRequest, position: Double, duration: Double, completed: Bool) async {
        guard let value = credentials, let videoID = request.progressVideoID else { return }
        do { try await api.saveProgress(key: value.authKey, request: request, videoID: videoID, position: position, duration: duration, completed: completed) }
        catch { message = "Die Abspielposition konnte nicht mit Stremio synchronisiert werden." }
    }
}

struct IOSStremioLogin: View {
    @ObservedObject private var account = IOSStremioAccount.shared
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        Form {
            Section("Stremio-Fortschritt synchronisieren") {
                if let value = account.credentials {
                    Text("Angemeldet als \(value.email)")
                    Button("Abmelden") { account.logout() }
                } else {
                    TextField("E-Mail", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("stremioEmail")
                    SecureField("Passwort", text: $password).textContentType(.password).accessibilityIdentifier("stremioPassword")
                    Button("Anmelden") {
                        let secret = password; password = ""
                        Task { await account.login(email: email, password: secret) }
                    }.disabled(account.busy || email.isEmpty || password.isEmpty).accessibilityIdentifier("stremioLogin")
                }
                if account.busy { ProgressView("Verbinden …") }
                if let message = account.message { Text(message).foregroundStyle(.secondary) }
                Text("Wenn Stremio keine Position im Infuse-Link mitgibt, lädt Kairo den gespeicherten Fortschritt dieser Folge aus deinem Konto. Beim Schließen wird die Position dort gespeichert. Verwende dasselbe Konto wie in Stremio.").font(.footnote)
                Text("Dein Passwort wird nicht gespeichert. Der Konto-Schlüssel liegt im Schlüsselbund und wird beim Abmelden entfernt.").font(.footnote).foregroundStyle(.secondary)
            }
        }.onDisappear { password = "" }
    }
}

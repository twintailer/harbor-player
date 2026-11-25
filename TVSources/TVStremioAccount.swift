import SwiftUI
import Security

@MainActor final class TVStremioAccount: ObservableObject {
    static let shared = TVStremioAccount()
    @Published private(set) var credentials: StremioCredentials?
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var syncFailure: String?
    @Published private(set) var hasPendingSync = false
    private let outboxKey = "stremioProgressOutbox.v1"
    private var outbox: [String: [StremioPendingProgress]] = [:]
    private var revision = UUID()
    private var pendingSave: Task<Void, Never>?
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
        if let data = UserDefaults.standard.data(forKey: outboxKey), let saved = try? JSONDecoder().decode([String: [StremioPendingProgress]].self, from: data) { outbox = saved }
        #if DEBUG
        if ProcessInfo.processInfo.environment["HARBOR_TEST_ACCOUNT"] == "fixture-only", api.base.host == "127.0.0.1" {
            credentials = StremioCredentials(authKey: "fixture-only", email: "fixture@example.invalid", addons: [])
        }
        #endif
        hasPendingSync = !(outbox[credentials?.email ?? ""] ?? []).isEmpty
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
            hasPendingSync = !(outbox[value.email] ?? []).isEmpty
            if hasPendingSync { await retryPending() }
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
        credentials = nil; message = nil; syncFailure = nil; hasPendingSync = false
    }
    func resumed(_ request: PlaybackRequest) async -> PlaybackRequest {
        if hasPendingSync { await retryPending() }
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
    @discardableResult
    func save(_ request: PlaybackRequest, videoID: String, position: Double, duration: Double, completed: Bool) async -> Bool {
        // Without a Kairo account, retain the ordinary external-player callback.
        guard credentials != nil else { return true }
        guard !request.contentID.isEmpty, !videoID.isEmpty, position.isFinite, duration.isFinite, position >= 0, duration > 0 else {
            syncFailure = StremioAPI.Failure.invalidProgress.localizedDescription
            return false
        }
        return await synchronize(StremioPendingProgress(request, videoID: videoID, position: position, duration: duration, completed: completed))
    }
    @discardableResult
    func retryPending() async -> Bool { await synchronize(nil) }

    private func persistOutbox() {
        if let data = try? JSONEncoder().encode(outbox) { UserDefaults.standard.set(data, forKey: outboxKey) }
        hasPendingSync = !(outbox[credentials?.email ?? ""] ?? []).isEmpty
    }
    private func synchronize(_ update: StremioPendingProgress?) async -> Bool {
        guard let value = credentials else {
            syncFailure = "Bitte in Kairo mit deinem Stremio-Konto anmelden, damit der Fortschritt gespeichert werden kann."
            return false
        }
        let previous = pendingSave, token = revision
        let task = Task { @MainActor in
            await previous?.value
            guard token == revision else { return }
            if let update {
                var values = outbox[value.email] ?? []
                // Keep a failed completion even when playback has already moved on.
                values.removeAll { $0.contentID == update.contentID && $0.videoID == update.videoID && $0.completed == update.completed }
                values.append(update); outbox[value.email] = values; persistOutbox()
            }
            var failed: [StremioPendingProgress] = []
            var lastError: String?
            let queued = outbox[value.email] ?? []
            for (index, item) in queued.enumerated() {
                guard token == revision else { return }
                do {
                    try await api.saveProgress(key: value.authKey, request: item.request, videoID: item.videoID, position: item.position, duration: item.duration, completed: item.completed, addons: value.addons)
                } catch {
                    // Do not let a newer episode hide the failure or let a later
                    // retry move Continue Watching back to an older episode.
                    failed = Array(queued[index...])
                    lastError = "\(item.title) (\(item.videoID)): \(error.localizedDescription)"
                    break
                }
            }
            guard token == revision else { return }
            outbox[value.email] = failed; persistOutbox()
            syncFailure = lastError
        }
        pendingSave = task
        await task.value
        return token == revision && syncFailure == nil && !hasPendingSync
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
            if let failure = account.syncFailure { Text(failure).foregroundStyle(.orange) }
            if account.hasPendingSync { Button("Fortschritt erneut synchronisieren") { Task { await account.retryPending() } } }
            Text("Dein Passwort wird nicht gespeichert. Konto-Schlüssel und Addon-Konfigurationen liegen im Schlüsselbund. Für den Folgenwechsel benötigt ein Addon direkt abspielbare HTTP-Streams; reine Torrent-Links benötigen einen Streaming-Server.").font(.callout).foregroundStyle(.secondary)
        }.onDisappear { password = "" }
    }
}

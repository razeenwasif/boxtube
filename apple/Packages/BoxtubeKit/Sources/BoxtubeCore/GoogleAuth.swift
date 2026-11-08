import Foundation
import Network
import CryptoKit
import Security

/// The signed-in Google account, as shown in the app.
public struct GoogleAccount: Codable, Hashable, Sendable {
    public var name: String
    public var email: String?
    public var pictureURL: URL?
}

/// Google sign-in for a "Desktop app" OAuth client: authorization code + PKCE, with the redirect
/// caught on a loopback port. Tokens live in the Keychain. Read-only YouTube access.
public actor GoogleAuth {
    public static let scopes = ["openid", "profile", "https://www.googleapis.com/auth/youtube.readonly"]

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiry: Date
        var account: GoogleAccount?
    }

    public struct Pending: Sendable {
        public let url: URL
        fileprivate let verifier: String
        fileprivate let state: String
        fileprivate let redirect: String
        fileprivate let receiver: LoopbackReceiver
    }

    private let clientID: String?
    private let clientSecret: String?
    private let session: URLSession
    private var tokens: Tokens?
    private let keychain = Keychain(service: "com.razeenwasif.boxtube.google")

    public nonisolated let isConfigured: Bool

    public init(clientID: String?, clientSecret: String?, session: URLSession = .shared) {
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let t, !t.isEmpty, !t.hasPrefix("$("), !t.hasPrefix("paste-") else { return nil }
            return t
        }
        self.clientID = clean(clientID)
        self.clientSecret = clean(clientSecret)
        self.isConfigured = self.clientID != nil
        self.session = session
        if let data = keychain.read(), let saved = try? JSONDecoder().decode(Tokens.self, from: data) { tokens = saved }
    }

    public var account: GoogleAccount? { tokens?.account }

    // MARK: Sign in

    /// Starts a loopback listener and returns the Google consent URL to open in a browser session.
    public func begin() async throws -> Pending {
        guard let clientID else { throw BoxtubeError.notSignedIn("Add a Google OAuth client ID to apple/Config/Secrets.xcconfig.") }
        let receiver = try await LoopbackReceiver.start()
        let redirect = "http://127.0.0.1:\(receiver.port)"
        let verifier = Self.randomString(64)
        let state = Self.randomString(24)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        return Pending(url: c.url!, verifier: verifier, state: state, redirect: redirect, receiver: receiver)
    }

    /// Waits for Google to redirect back, then swaps the code for tokens and loads the profile.
    public func finish(_ pending: Pending) async throws -> GoogleAccount {
        let query = try await pending.receiver.waitForRedirect()
        guard query["state"] == pending.state else { throw BoxtubeError.notSignedIn("Sign-in was interrupted. Try again.") }
        if let error = query["error"] { throw BoxtubeError.notSignedIn(error == "access_denied" ? "Sign-in was cancelled." : "Google said: \(error)") }
        guard let code = query["code"] else { throw BoxtubeError.notSignedIn("Google didn't return a sign-in code.") }
        let token = try await tokenRequest([
            "code": code,
            "code_verifier": pending.verifier,
            "redirect_uri": pending.redirect,
            "grant_type": "authorization_code",
        ])
        var saved = Tokens(accessToken: token.access_token, refreshToken: token.refresh_token,
                           expiry: .now.addingTimeInterval(Double(token.expires_in ?? 3600) - 60))
        tokens = saved
        let account = (try? await profile(token: saved.accessToken)) ?? GoogleAccount(name: "Google account")
        saved.account = account
        tokens = saved
        persist()
        return account
    }

    public func cancel(_ pending: Pending) { pending.receiver.stop() }

    public func signOut() async {
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Self.form(["token": token])
            _ = try? await session.data(for: r)
        }
        tokens = nil
        keychain.delete()
    }

    /// A fresh access token, refreshing it if needed.
    public func accessToken() async throws -> String {
        guard var t = tokens else { throw BoxtubeError.notSignedIn("Sign in with Google first.") }
        if t.expiry > .now { return t.accessToken }
        guard let refresh = t.refreshToken else { throw BoxtubeError.notSignedIn("Your Google sign-in expired. Sign in again.") }
        do {
            let token = try await tokenRequest(["refresh_token": refresh, "grant_type": "refresh_token"])
            t.accessToken = token.access_token
            t.expiry = .now.addingTimeInterval(Double(token.expires_in ?? 3600) - 60)
            if let r = token.refresh_token { t.refreshToken = r }
            tokens = t
            persist()
            return t.accessToken
        } catch BoxtubeError.http(400, _) {
            // invalid_grant: revoked, or the 7-day limit for apps still in Google's "Testing" status.
            tokens = nil
            keychain.delete()
            throw BoxtubeError.notSignedIn("Your Google sign-in expired. Sign in again.")
        }
    }

    // MARK: Internals

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int?
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var all = fields
        all["client_id"] = clientID
        if let clientSecret { all["client_secret"] = clientSecret }
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Self.form(all)
        let (data, response) = try await session.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct E: Decodable { var error: String?; var error_description: String? }
            let e = try? JSONDecoder().decode(E.self, from: data)
            throw BoxtubeError.http(status, e?.error_description ?? e?.error ?? "token request failed")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func profile(token: String) async throws -> GoogleAccount {
        var r = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: r)
        struct Info: Decodable { var name: String?; var given_name: String?; var email: String?; var picture: URL? }
        let info = try JSONDecoder().decode(Info.self, from: data)
        return GoogleAccount(name: info.name ?? info.given_name ?? "Google account", email: info.email, pictureURL: info.picture)
    }

    private func persist() {
        if let tokens, let data = try? JSONEncoder().encode(tokens) { keychain.write(data) }
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
    }

    private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback redirect receiver

/// Listens on 127.0.0.1 for the one HTTP request Google's redirect makes, then answers with a short page.
final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "boxtube.oauth.loopback")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> LoopbackReceiver {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: params)
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let e): if once.take() { cont.resume(throwing: e) }
                default: break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: DispatchQueue(label: "boxtube.oauth.start"))
        }
        let receiver = LoopbackReceiver(listener: listener, port: port)
        listener.newConnectionHandler = { [weak receiver] conn in receiver?.handle(conn) }
        return receiver
    }

    func waitForRedirect() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    if let result = self.result { cont.resume(with: result) } else { self.continuation = cont }
                }
            }
        } onCancel: { self.stop() }
    }

    func stop() {
        queue.async { self.complete(.failure(CancellationError())) }
    }

    private func complete(_ r: Result<[String: String], Error>) {
        guard result == nil else { return }
        result = r
        listener.cancel()
        continuation?.resume(with: r)
        continuation = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // "GET /?code=…&state=… HTTP/1.1"
            let target = text.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let items = URLComponents(string: "http://127.0.0.1" + target)?.queryItems ?? []
            let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            let isRedirect = query["code"] != nil || query["error"] != nil
            let body = isRedirect
                ? "<!doctype html><meta charset=utf-8><title>Boxtube</title><body style=\"font:16px -apple-system;background:#0B0B0D;color:#F4F4F5;display:grid;place-items:center;height:90vh\"><div><h2>You're signed in to Boxtube.</h2><p style=\"color:#A1A1AA\">You can close this window.</p></div>"
                : "Not found"
            let head = "HTTP/1.1 \(isRedirect ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
            if isRedirect { self.complete(.success(query)) }
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

// MARK: - Keychain

struct Keychain: Sendable {
    var service: String
    private var base: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "tokens"] }

    func read() -> Data? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    func write(_ data: Data) {
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(base as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(base.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    func delete() { SecItemDelete(base as CFDictionary) }
}

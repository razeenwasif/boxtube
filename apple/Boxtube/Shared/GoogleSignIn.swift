import SwiftUI
import AuthenticationServices
import BoxtubeCore
import BoxtubeUI

/// Shows Google's consent page in the system browser sheet. The redirect lands on Boxtube's
/// loopback listener (see GoogleAuth), so the sheet is closed from here once that happens.
@MainActor
final class BrowserSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func open(_ url: URL, onUserCancel: @escaping @MainActor @Sendable () -> Void) {
        // AuthenticationServices calls this on a background queue, so it must not be main-actor isolated.
        let handler: @Sendable (URL?, Error?) -> Void = { _, error in
            guard (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin else { return }
            Task { @MainActor in onUserCancel() }
        }
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme("boxtube-oauth"), completionHandler: handler)
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func close() {
        session?.cancel()
        session = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
            #else
            return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
            #endif
        }
    }
}

extension AppModel {
    func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        let browser = BrowserSignIn()
        do {
            let pending = try await google.begin()
            browser.open(pending.url) { [google] in Task { await google.cancel(pending) } }
            let signedIn = try await google.finish(pending)
            browser.close()
            account = signedIn
            displayName = signedIn.name
            await importFromYouTube()
        } catch is CancellationError {
            browser.close()
        } catch {
            browser.close()
            flash(error.localizedDescription, seconds: 5)
        }
    }

    func importFromYouTube() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let token = try await google.accessToken()
            let r = try await feed.importAccount(token: token)
            lastImport = .now
            flash("Imported \(r.subscriptions) subscriptions, \(r.playlists) playlists and \(r.liked) liked videos", seconds: 4)
            await refresh(force: true)
        } catch BoxtubeError.notSignedIn(let message) {
            account = nil
            flash(message, seconds: 5)
        } catch {
            flash(error.localizedDescription, seconds: 6)
        }
    }

    func signOutOfGoogle() async {
        await google.signOut()
        account = nil
        flash("Signed out of Google")
    }

    var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "JD" : letters.uppercased()
    }
}

/// Your avatar: the Google profile photo when signed in, otherwise initials.
struct MyAvatar: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 32
    var ring: Color? = nil
    var body: some View {
        ProfileAvatar(size: size, ring: ring, initials: model.initials, photo: model.account?.pictureURL)
    }
}

/// Sign-in / import controls, used in Settings on both platforms.
struct GoogleAccountSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if !model.googleConfigured {
            LabeledContent("Google account", value: "Add a client ID in apple/Config/Secrets.xcconfig")
        } else if let account = model.account {
            HStack(spacing: 12) {
                MyAvatar(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).font(.system(size: 14, weight: .semibold))
                    if let email = account.email { Text(email).font(.system(size: 12)).foregroundStyle(BX.muted) }
                }
            }
            Button {
                Task { await model.importFromYouTube() }
            } label: {
                HStack {
                    Text(model.isImporting ? "Importing…" : "Import from YouTube again")
                    if model.isImporting { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(model.isImporting)
            Button("Sign out", role: .destructive) { Task { await model.signOutOfGoogle() } }
        } else {
            Button {
                Task { await model.signInWithGoogle() }
            } label: {
                HStack {
                    Text(model.isSigningIn ? "Waiting for Google…" : "Sign in with Google")
                    if model.isSigningIn { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(model.isSigningIn)
        }
    }
}

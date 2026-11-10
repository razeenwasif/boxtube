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
    func signInWithGoogle(write: Bool = false) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        let browser = BrowserSignIn()
        do {
            let pending = try await google.begin(write: write)
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

    func importFromYouTube(quiet: Bool = false) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let token = try await google.accessToken()
            // With sync on, YouTube is the record for subscriptions.
            let r = try await feed.importAccount(token: token, mirrorSubscriptions: syncEnabled)
            lastImport = .now
            await recordQuota()
            if !quiet { flash("Imported \(r.subscriptions) subscriptions, \(r.playlists) playlists and \(r.liked) liked videos", seconds: 4) }
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
        syncEnabled = false
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

/// Sign-in / import controls, used in Settings on both platforms (rows of a `BXCard`).
struct GoogleAccountSection: View {
    @Environment(AppModel.self) private var model
    /// YouTube playlists removed from Boxtube (observed by the parent, so these rows stay a flat list).
    var removedPlaylists = 0
    var body: some View {
        if !model.googleConfigured {
            BXRow("Google account", subtitle: "Add a client ID in apple/Config/Secrets.xcconfig")
        } else if let account = model.account {
            HStack(spacing: 12) {
                MyAvatar(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).font(.system(size: 14.5, weight: .semibold))
                    if let email = account.email { Text(email).font(.system(size: 12)).foregroundStyle(BX.muted) }
                }
            }
            Toggle(isOn: Binding(get: { model.syncEnabled }, set: { on in Task { await model.setSync(on) } })) {
                BXRowLabel(title: "Sync changes to YouTube", subtitle: "Likes, subscriptions and playlist edits")
            }
            .toggleStyle(.bx)
            .disabled(model.isSigningIn)
            if model.syncEnabled { SyncStatusRows() }
            if removedPlaylists > 0 {
                BXActionRow(title: "Bring back \(removedPlaylists) removed playlist\(removedPlaylists == 1 ? "" : "s")", icon: "arrow.uturn.backward", busy: model.isImporting) {
                    Task { await model.bringBackRemovedPlaylists() }
                }
            }
            BXActionRow(title: model.isImporting ? "Importing…" : "Import from YouTube again", icon: "arrow.down.circle", busy: model.isImporting) {
                Task { await model.importFromYouTube() }
            }
            BXActionRow(title: "Sign out", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                Task { await model.signOutOfGoogle() }
            }
        } else {
            BXActionRow(title: model.isSigningIn ? "Waiting for Google…" : "Sign in with Google",
                        subtitle: "Bring in your subscriptions, playlists and likes",
                        icon: "person.crop.circle.badge.plus", busy: model.isSigningIn) {
                Task { await model.signInWithGoogle() }
            }
        }
    }
}

/// Sync's state in Settings: what's waiting, any problem, today's quota, and Sync now.
private struct SyncStatusRows: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let sync = model.sync
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sync.problem != nil ? "exclamationmark.triangle.fill" : (sync.summary.waiting > 0 ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill"))
                .foregroundStyle(sync.problem != nil ? BX.amber : (sync.summary.waiting > 0 ? BX.muted : BX.sage))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.syncStatusText).font(.system(size: 13.5, weight: .semibold))
                if let problem = sync.problem { Text(problem).font(.system(size: 12)).foregroundStyle(BX.muted) }
                Text("\(model.quotaToday.formatted()) of 10,000 YouTube quota units used today")
                    .font(.system(size: 12)).foregroundStyle(BX.muted)
            }
            Spacer(minLength: 8)
            Button {
                Task { await model.syncNow(importAfter: true) }
            } label: {
                if sync.syncing { ProgressView().controlSize(.small) } else { Text("Sync now") }
            }
            .buttonStyle(.bx(.secondary, height: 32))
            .disabled(sync.syncing)
        }
        if sync.summary.failed > 0 {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YouTube refused \(sync.summary.failed) change\(sync.summary.failed == 1 ? "" : "s")").font(.system(size: 13.5, weight: .semibold))
                    if let e = sync.summary.lastError { Text(e).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(2) }
                }
                Spacer()
                Button("Discard") { Task { await model.retryFailedSync() } }
                    .buttonStyle(.bx(.destructive, height: 32))
            }
        }
    }
}

/// Everything in Settings, as Boxtube cards. The Mac's Settings window and the iPhone's Settings sheet both show it.
struct SettingsContent: View {
    @Environment(AppModel.self) private var model
    @Environment(BXMenuHost.self) private var host: BXMenuHost?
    @State private var removedPlaylists = 0

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 24) {
            #if os(macOS)
            BXCard("You") {
                BXRow("Your name") {
                    TextField("Name", text: $model.displayName)
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .font(.system(size: 14.5)).foregroundStyle(BX.text2)
                        .frame(maxWidth: 220)
                }
            }
            #endif
            BXCard("Watching") {
                Toggle(isOn: $model.calmMode) {
                    BXRowLabel(title: "Calm mode", subtitle: "Only channels you follow, newest first")
                }
                .toggleStyle(.bx(tint: BX.sage))
                BXRow("Watch later clears after") {
                    BXPicker(options: [1, 2, 4, 8], selection: $model.clearAfterWeeks, title: { "\($0) week\($0 == 1 ? "" : "s")" })
                }
                Toggle(isOn: $model.tintFromVideo) {
                    #if os(macOS)
                    BXRowLabel(title: "Tint the window from the video")
                    #else
                    BXRowLabel(title: "Tint from the video")
                    #endif
                }
                .toggleStyle(.bx)
                BXRow(previewTitle) {
                    BXPicker(options: PreviewMode.allCases, selection: $model.previewMode, title: \.title)
                }
                Toggle(isOn: $model.discoverChannels) {
                    BXRowLabel(title: "Recommend from channels you don't follow", subtitle: model.recommendationStats)
                }
                .toggleStyle(.bx)
            }
            BXCard("YouTube account", footer: model.syncEnabled
                   ? "Likes, subscriptions, playlist edits and new playlists go to YouTube; each change uses 50 of your 10,000 daily quota units. Deleting a playlist only removes it from Boxtube."
                   : "Boxtube copies your subscriptions, playlists and liked videos. Turn on sync to send changes you make here back to YouTube.") {
                GoogleAccountSection(removedPlaylists: removedPlaylists)
            }
            BXCard("Data", footer: model.hasAPIKey ? "Search, topics and video lengths are on." : "Subscriptions work without a key. Add one in apple/Config/Secrets.xcconfig for search, topics and video lengths.") {
                BXRow("YouTube API key") {
                    Text(model.hasAPIKey ? "Added" : "Missing").font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(model.hasAPIKey ? BX.sageText : BX.amber)
                }
                BXRow("Notes", subtitle: model.notesSyncLine)
                HiddenVideosRow()
                BXActionRow(title: "Clear watch history", icon: "trash", destructive: true) {
                    host?.show(.confirm("Clear watch history?", message: "Progress bars and History are emptied on this device. Recommendations start learning again.",
                                        actions: [.init(title: "Clear", kind: .destructive) { _ in Task { try? await model.store.clearHistory() } }]))
                }
            }
        }
        .observing(model.store, { db in try Q.hiddenPlaylistCount(db) }) { removedPlaylists = $0 }
    }

    private var previewTitle: String {
        #if os(macOS)
        "Preview videos on hover"
        #else
        "Preview videos"
        #endif
    }
}

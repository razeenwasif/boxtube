import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

struct PhoneRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var visited: Set<Tab> = [.home]
    @State private var live = LiveActivityController()

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            ForEach(Tab.allCases) { tab in
                if visited.contains(tab) {
                    NavigationStack(path: Binding(get: { model.paths[tab] ?? [] }, set: { model.paths[tab] = $0 })) {
                        root(for: tab)
                            .navigationDestination(for: Route.self) { RouteScreen(route: $0).toolbar(.hidden, for: .navigationBar) }
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .opacity(model.tab == tab ? 1 : 0)
                    .allowsHitTesting(model.tab == tab)
                    .accessibilityHidden(model.tab != tab)
                }
            }
            Island(onMedia: model.tab == .shorts)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(model.calmMode && model.tab == .home ? BX.calmGround : BX.ground)
        .onChange(of: model.tab) { _, tab in visited.insert(tab) }
        .fullScreenCover(item: $model.watching) { video in
            WatchScreen(video: video).environment(model).bxMenuHost()
        }
        .fullScreenCover(isPresented: $model.showMusicPlayer) {
            MusicPlayerScreen().environment(model).bxMenuHost()
        }
        .sheet(isPresented: $model.showTimeBox) {
            TimeBoxView().environment(model).presentationDragIndicator(.visible)
        }
        .overlay {
            if model.showChapterRing { ChapterRing().transition(.opacity) }
        }
        .overlay {
            if model.showCommandPanel { CommandPanel().transition(.opacity) }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast { Toast(text: toast).padding(.top, 8) }
        }
        .background { PlaybackTicker() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.preview.stop() } else { model.scheduleSync(); model.syncNotes(); model.refreshRecommendationsIfStale() } }
        .onAppear { live.attach(to: model) }
    }

    @ViewBuilder
    private func root(for tab: Tab) -> some View {
        switch tab {
        case .home:
            if model.mode == .music { MusicHomeScreen() } else if model.calmMode { CalmHomeScreen() } else { HomeScreen() }
        case .shorts: ShortsScreen()
        case .subs: SubscriptionsScreen()
        case .playlists:
            if model.mode == .music { MusicLibraryScreen() } else { PlaylistsScreen() }
        case .you: ProfileScreen()
        }
    }
}

struct RouteScreen: View {
    var route: Route
    var body: some View {
        switch route {
        case .channel(let id): ChannelScreen(channelId: id)
        case .playlist(let id): PlaylistDetailScreen(playlistId: id)
        case .watchLater: WatchLaterScreen()
        case .liked: VideoListScreen(title: "Liked", kind: .liked)
        case .history: VideoListScreen(title: "History", kind: .history)
        case .search(let q): SearchResultsScreen(query: q)
        case .musicLibrary: MusicLibraryScreen()
        case .notes: NotesScreen()
        }
    }
}

/// Bottom padding so content scrolls clear of the island.
extension View {
    func islandClearance(_ extra: CGFloat = 0) -> some View {
        contentMargins(.bottom, 150 + extra, for: .scrollContent)
    }
}

/// Standard large-title header row used by tab roots.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var trailing: Trailing
    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                LargeTitle(title)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(BX.muted) }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20).padding(.trailing, -4)
        .frame(height: 48)
        .padding(.top, 6)
    }
}

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold)).frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

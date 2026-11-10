import SwiftUI
import BoxtubeCore
import BoxtubeUI

// Movies you've bought, rented or saved for later on YouTube. YouTube's API can't read purchases, so
// you add them here (a link, or a movie search); paid movies only play in YouTube, so they open there.

extension AppModel {
    /// Files the movie at `link` (a YouTube link or video id).
    func addMovie(link: String, kind: Movie.Kind) {
        guard let id = YouTubeLink.videoId(from: link) else { flash("That doesn't look like a YouTube link"); return }
        Task {
            guard let video = await feed.lookUpVideo(id) else { flash("Couldn't find that movie on YouTube"); return }
            await addMovie(video, kind: kind)
        }
    }

    func addMovie(_ video: Video, kind: Movie.Kind) async {
        do {
            try await store.addMovie(video, kind: kind)
            flash("Added to \(kind.title)")
        } catch {
            flash("Couldn't add that movie")
        }
    }

    /// Opens the movie in YouTube; the first play of a rental starts its 48-hour clock.
    func playMovie(_ row: MovieRow) {
        if row.movie.kind == .rented, row.movie.startedAt == nil {
            Task { try? await store.setMovieStarted(row.id, true) }
        }
        openExternally(row.video.watchURL)
    }

    @BXMenuBuilder
    func movieMenu(_ row: MovieRow) -> [BXMenuSection] {
        let m = row.movie
        BXMenuSection {
            BXMenuItem("Watch on YouTube", icon: "play.fill", tint: BX.coralText) { self.playMovie(row) }
        }
        BXMenuSection("File under") {
            for kind in Movie.Kind.allCases {
                BXMenuItem(kind.title, icon: Self.movieIcon(kind), checked: m.kind == kind) {
                    Task { try? await self.store.setMovieKind(row.id, kind) }
                }
            }
        }
        if m.kind == .rented {
            BXMenuSection {
                if m.startedAt == nil {
                    BXMenuItem("I've started watching", icon: "hourglass") { Task { try? await self.store.setMovieStarted(row.id, true) } }
                } else {
                    BXMenuItem("I haven't started it", icon: "arrow.uturn.backward") { Task { try? await self.store.setMovieStarted(row.id, false) } }
                }
            }
        }
        BXMenuSection {
            BXMenuItem.share(row.video.watchURL)
            BXMenuItem("Copy link", icon: "link") { self.copyLink(row.video) }
            BXMenuItem("Remove from Movies", icon: "trash", destructive: true) { Task { try? await self.store.removeMovie(row.id) } }
        }
    }

    static func movieIcon(_ kind: Movie.Kind) -> String {
        switch kind {
        case .rented: "ticket"
        case .bought: "bag"
        case .saved: "bookmark"
        }
    }
}

struct MoviesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(BXMenuHost.self) private var host: BXMenuHost?
    @State private var rows: [MovieRow] = []
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        let groups = Movie.Kind.allCases.map { kind in (kind, rows.filter { $0.movie.kind == kind }) }.filter { !$0.1.isEmpty }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                #if os(iOS)
                HStack { BackButton(); Spacer() }.padding(.horizontal, 10)
                #endif
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        LargeTitle("Movies")
                        Text(summary).font(.system(size: 13)).foregroundStyle(BX.muted)
                    }
                    Spacer()
                    Button { addByLink() } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.bx(.primary, height: 36))
                        .accessibilityLabel("Add a movie by link")
                }
                .padding(.horizontal, sidePadding).padding(.top, topPadding)

                if model.hasAPIKey {
                    HStack(spacing: 10) {
                        BXTextField(placeholder: "Find a movie on YouTube", text: $query, onSubmit: search)
                            #if os(iOS)
                            .submitLabel(.search)
                            #endif
                        if !results.isEmpty || searching {
                            Button(searching ? "…" : "Clear") { results = []; query = "" }
                                .buttonStyle(.bx(.secondary, height: 40))
                        }
                    }
                    .padding(.horizontal, sidePadding).padding(.top, 16)
                    if let searchError {
                        Text(searchError).font(.system(size: 12.5)).foregroundStyle(BX.coralText).padding(.horizontal, sidePadding).padding(.top, 8)
                    }
                    if !results.isEmpty {
                        sectionHeader("Results", count: results.count)
                        grid(results.map { v in AnyView(ResultCard(video: v, filed: rows.first { $0.id == v.id }?.movie.kind)) })
                    }
                }

                if rows.isEmpty && results.isEmpty {
                    HintCard(icon: "film", title: "No movies yet",
                             message: "Add the movies you've bought or rented on YouTube, or ones to watch later: tap Add and paste a link\(model.hasAPIKey ? ", or search above" : ""). They play in the YouTube app.")
                        .padding(.horizontal, sidePadding).padding(.top, 22)
                }
                ForEach(groups, id: \.0) { kind, items in
                    sectionHeader(kind.title, count: items.count)
                    grid(items.map { AnyView(MovieCard(row: $0)) })
                }
                Text("YouTube doesn't share purchases with other apps, so Boxtube only knows the movies you add here. Bought and rented movies play in YouTube.")
                    .font(.system(size: 12)).foregroundStyle(BX.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, sidePadding).padding(.top, 28).padding(.bottom, 12)
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        .islandClearance()
        #endif
        .observing(model.store, { db in try Q.movies(db) }) { rows = $0 }
    }

    private var summary: String {
        let rented = rows.filter { $0.movie.kind == .rented }
        let live = rented.filter { r in
            guard let at = r.movie.rentedAt else { return false }
            return Rental.state(rentedAt: at, startedAt: r.movie.startedAt) != .expired
        }
        var parts = ["\(rows.count) movie\(rows.count == 1 ? "" : "s")"]
        if !live.isEmpty { parts.append("\(live.count) rental\(live.count == 1 ? "" : "s") running") }
        return parts.joined(separator: " · ")
    }

    private var sidePadding: CGFloat {
        #if os(macOS)
        28
        #else
        16
        #endif
    }

    private var topPadding: CGFloat {
        #if os(macOS)
        28
        #else
        6
        #endif
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 18, weight: .bold)).kerning(-0.18).accessibilityAddTraits(.isHeader)
            Text("\(count)").font(.system(size: 13)).foregroundStyle(BX.muted)
        }
        .padding(.horizontal, sidePadding + 4).padding(.top, 26).padding(.bottom, 12)
    }

    private func grid(_ cards: [AnyView]) -> some View {
        #if os(macOS)
        let columns = [GridItem(.adaptive(minimum: 230), spacing: 20)]
        #else
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        #endif
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
        }
        .padding(.horizontal, sidePadding)
    }

    private func addByLink() {
        let actions: [BXDialog.Action] = [
            .init(title: "Rented", kind: .secondary) { link in model.addMovie(link: link, kind: .rented) },
            .init(title: "Bought", kind: .secondary) { link in model.addMovie(link: link, kind: .bought) },
            .init(title: "Save for later", kind: .primary) { link in model.addMovie(link: link, kind: .saved) },
            .init(title: "Cancel"),
        ]
        host?.show(BXDialog(title: "Add a movie", message: "Paste its YouTube link (Share → Copy link in YouTube), then say how you have it.",
                            field: ("youtube.com/watch?v=…", ""), actions: actions))
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true; searchError = nil
        Task {
            do {
                results = try await model.feed.searchMovies(q)
                if results.isEmpty { searchError = "YouTube has no movies matching “\(q)”." }
            } catch {
                searchError = "Search didn't work: \(error.localizedDescription)"
            }
            searching = false
        }
    }
}

/// A movie you've filed: thumbnail with how long a rental has left, title, length, and its menu.
private struct MovieCard: View {
    @Environment(AppModel.self) private var model
    var row: MovieRow

    var body: some View {
        let state = row.movie.rentedAt.map { Rental.state(rentedAt: $0, startedAt: row.movie.startedAt) }
        let expired = state == .expired
        VStack(alignment: .leading, spacing: 9) {
            Button { model.playMovie(row) } label: {
                VideoThumbnail(row.video, radius: 14)
                    .saturation(expired ? 0.2 : 1)
                    .overlay(alignment: .topLeading) {
                        if let state {
                            Label(Rental.label(state), systemImage: "ticket")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(badgeInk(state))
                                .padding(.horizontal, 8).frame(height: 24)
                                .background(badgeFill(state), in: Capsule())
                                .padding(8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watch \(row.video.title) on YouTube")
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.video.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(meta).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                BXMenuButton(trailing: true) { model.movieMenu(row) } label: {
                    MoreDots(vertical: true, size: 16).foregroundStyle(BX.muted).frame(width: 26, height: 30).contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(row.video.title)")
            }
        }
        .opacity(expired ? 0.6 : 1)
        .bxContextMenu { model.movieMenu(row) }
    }

    private var meta: String {
        [row.video.durationSeconds.map { Format.minutes(Double($0)) }, row.video.channelTitle.isEmpty ? nil : row.video.channelTitle]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func badgeFill(_ s: Rental.State) -> Color {
        switch s {
        case .notStarted: Color(hex: 0x0C0C10, opacity: 0.72)
        case .watching: BX.coral
        case .expired: Color(hex: 0x2A2A30)
        }
    }

    private func badgeInk(_ s: Rental.State) -> Color {
        switch s {
        case .notStarted: BX.amber
        case .watching: BX.coralInk
        case .expired: BX.muted
        }
    }
}

/// A search result, with a menu to file it.
private struct ResultCard: View {
    @Environment(AppModel.self) private var model
    var video: Video
    var filed: Movie.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { openExternally(video.watchURL) } label: { VideoThumbnail(video, radius: 14) }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(video.title) on YouTube")
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(filed.map { "In \($0.title)" } ?? (video.durationSeconds.map { Format.minutes(Double($0)) } ?? ""))
                        .font(.system(size: 12)).foregroundStyle(filed == nil ? BX.muted : BX.sageText).lineLimit(1)
                }
                Spacer(minLength: 0)
                BXMenuButton(trailing: true) {
                    BXMenuSection("Add to Movies") {
                        for kind in Movie.Kind.allCases {
                            BXMenuItem(kind.title, icon: AppModel.movieIcon(kind), checked: filed == kind) {
                                Task { await model.addMovie(video, kind: kind) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: filed == nil ? "plus" : "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(filed == nil ? BX.coralInk : BX.sageText)
                        .frame(width: 30, height: 30)
                        .background(filed == nil ? BX.coral : BX.sage.opacity(0.2), in: Circle())
                }
                .accessibilityLabel(filed == nil ? "Add \(video.title) to Movies" : "Move \(video.title) in Movies")
            }
        }
    }
}

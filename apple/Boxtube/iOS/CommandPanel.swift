import SwiftUI
import BoxtubeCore
import BoxtubeUI

/// Idea 04c: swipe up on the island (or tap the search orb) → search and commands in one panel.
struct CommandPanel: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var resume: [HistoryRow] = []

    struct Command: Identifiable {
        var id: String
        var title: String
        var hint: String
        var glyph: String
        var tint: Color
        var run: () -> Void
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.5)).background(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color(hex: 0x45454C)).frame(width: 36, height: 4).frame(maxWidth: .infinity).padding(.bottom, 8)
                let filtered = commands.filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) }
                if !filtered.isEmpty {
                    Text("DO SOMETHING").font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(BX.dim).padding(.horizontal, 8).padding(.top, 4)
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, c in
                        Button { close(); c.run() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: c.glyph).font(.system(size: 14, weight: .bold)).foregroundStyle(c.tint)
                                    .frame(width: 32, height: 32).background(c.tint.opacity(0.18), in: .rect(cornerRadius: 10))
                                Text(c.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                                Spacer()
                                Text(c.hint).font(.system(size: 12)).foregroundStyle(BX.dim)
                            }
                            .padding(.horizontal, 8).frame(height: 48)
                            .background(i == 0 ? .white.opacity(0.07) : .clear, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !model.recentSearches.isEmpty {
                    Text("RECENT").font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(BX.dim).padding(.horizontal, 8).padding(.top, 10)
                    FlowRow(items: model.recentSearches) { q in
                        Button { search(q) } label: {
                            Text(q).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(height: 30).background(Color(hex: 0x2A2A30), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(BX.coralText)
                    TextField("Search or type a command", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { search(text) }
                        .textInputAutocapitalization(.never)
                    if !text.isEmpty {
                        Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(BX.dim) }.buttonStyle(.plain)
                            .accessibilityLabel("Clear")
                    }
                }
                .padding(.leading, 18).padding(.trailing, 12)
                .frame(height: 56)
                .background(Color(hex: 0x0F0F12), in: Capsule())
                .overlay(Capsule().strokeBorder(BX.coral.opacity(0.6), lineWidth: 1.5))
            }
            .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 10)
            .boxGlass(.rect(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 14).padding(.bottom, 8)
            .gesture(DragGesture().onEnded { if $0.translation.height > 80 { close() } })
        }
        .onAppear { focused = true }
        .observing(model.store, { db in try Q.history(db, limit: 1, unfinishedOnly: true) }) { resume = $0 }
    }

    private var commands: [Command] {
        var list: [Command] = [
            Command(id: "timebox", title: "Start a time box", hint: "25 min", glyph: "timer", tint: BX.coralText) { model.showTimeBox = true },
        ]
        if let r = resume.first {
            list.append(Command(id: "resume", title: "Resume “\(r.video.title)”", hint: "\(Format.minutes(r.entry.remainingSeconds)) left", glyph: "play.fill", tint: Color(hex: 0x8FB0F2)) { model.open(r.video) })
        }
        list += [
            Command(id: "calm", title: model.calmMode ? "Turn off Calm mode" : "Turn on Calm mode", hint: "", glyph: "leaf.fill", tint: BX.sageText) { model.calmMode.toggle(); model.tab = .home },
            Command(id: "mode", title: model.mode == .music ? "Switch to Videos" : "Switch to Music", hint: "", glyph: "music.note", tint: BX.amber) { model.mode = model.mode == .music ? .videos : .music; model.tab = .home },
            Command(id: "later", title: "Open Watch later", hint: "", glyph: "clock", tint: BX.teal) { model.tab = .playlists; model.paths[.playlists] = [.watchLater] },
            Command(id: "movies", title: "Open movies", hint: "", glyph: "film", tint: Color(hex: 0xB3A1FF)) { model.tab = .playlists; model.paths[.playlists] = [.movies] },
            Command(id: "notes", title: "Open notes", hint: "", glyph: "note.text", tint: BX.amber) { model.tab = .you; model.paths[.you] = [.notes] },
        ]
        if model.player.video != nil {
            list.append(Command(id: "chapters", title: "Jump to a chapter", hint: "", glyph: "list.bullet", tint: BX.coralText) { model.showChapterRing = true })
        }
        return list
    }

    private func search(_ q: String) {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        model.rememberSearch(query)
        close()
        model.paths[model.tab, default: []].append(.search(query))
    }

    private func close() {
        focused = false
        withAnimation(.smooth) { model.showCommandPanel = false }
    }
}

/// Simple wrapping row for chips.
struct FlowRow<Item: Hashable, Content: View>: View {
    var items: [Item]
    var content: (Item) -> Content
    var body: some View {
        FlowLayout(spacing: 8) { ForEach(items, id: \.self) { content($0) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

import SwiftUI
import BoxtubeCore
import BoxtubeUI

/// Every note on iPhone, grouped by video (the Mac's Notes page). Tap a time to play from there.
/// Reached from You → Notes, the Notes count on You, and the command panel.
struct NotesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var groups: [NoteGroup] = []
    @State private var query = ""

    var body: some View {
        let shown = filtered
        let count = groups.reduce(0) { $0 + $1.notes.count }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack { BackButton(); Spacer() }.padding(.horizontal, 10)
                LargeTitle("Notes").padding(.horizontal, 20).padding(.top, 6)
                Text(count == 0 ? model.notesSyncLine : "\(count) note\(count == 1 ? "" : "s") on \(groups.count) video\(groups.count == 1 ? "" : "s") · \(model.notesSyncLine)")
                    .font(.system(size: 13)).foregroundStyle(BX.muted)
                    .padding(.horizontal, 20).padding(.top, 4)

                if groups.isEmpty {
                    HintCard(icon: "note.text", title: "No notes yet",
                             message: "While a video plays, open Notes under it and write one. It's pinned to that moment.")
                        .padding(.horizontal, 16).padding(.top, 22)
                } else {
                    searchField.padding(.horizontal, 16).padding(.top, 16)
                    if shown.isEmpty {
                        Text("No notes match “\(query)”.").font(.system(size: 14)).foregroundStyle(BX.muted)
                            .padding(.horizontal, 20).padding(.top, 22)
                    }
                    ForEach(shown) { group in
                        NoteGroupCard(group: group).padding(.horizontal, 16).padding(.top, 14)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .islandClearance()
        .observing(model.store, { db in try Q.noteGroups(db) }) { groups = $0 }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(BX.muted)
            TextField("Search notes", text: $query)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(BX.dim) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(BX.surface2, in: Capsule())
    }

    /// Matches note text, the video's title or its channel.
    private var filtered: [NoteGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            if g.video.title.localizedCaseInsensitiveContains(q) || g.video.channelTitle.localizedCaseInsensitiveContains(q) { return g }
            let notes = g.notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
            return notes.isEmpty ? nil : NoteGroup(video: g.video, notes: notes)
        }
    }
}

/// One video and its notes.
private struct NoteGroupCard: View {
    @Environment(AppModel.self) private var model
    var group: NoteGroup

    var body: some View {
        let v = group.video
        VStack(alignment: .leading, spacing: 12) {
            Button { model.open(v) } label: {
                HStack(alignment: .top, spacing: 12) {
                    VideoThumbnail(v, radius: 10, showDuration: false, progress: model.progressById[v.id]).frame(width: 112)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(v.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(v.channelTitle).font(.system(size: 12)).foregroundStyle(BX.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(v.title)")

            ForEach(group.notes) { n in
                HStack(alignment: .top, spacing: 12) {
                    Button { model.open(v, at: n.time) } label: {
                        Text(Format.clock(n.time)).font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(BX.amber).padding(.horizontal, 8).frame(height: 24)
                            .background(BX.amber.opacity(0.14), in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play from \(Format.clock(n.time))")
                    Text(n.text).font(.system(size: 14)).foregroundStyle(BX.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
                .bxContextMenu {
                    BXMenuSection {
                        BXMenuItem("Play from \(Format.clock(n.time))", icon: "play.fill", tint: BX.amber) { model.open(v, at: n.time) }
                        BXMenuItem("Copy note", icon: "doc.on.doc") { UIPasteboard.general.string = n.text; model.flash("Note copied") }
                    }
                    BXMenuSection {
                        BXMenuItem("Delete note", icon: "trash", destructive: true) { model.deleteNote(n) }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: 0x151518), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

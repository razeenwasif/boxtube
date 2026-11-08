import SwiftUI
import BoxtubeCore
import BoxtubeUI
import BoxtubePlayer

/// Interactive chapter scrubber: drag (or hover on Mac) to preview, release to seek.
struct ChapterScrubber: View {
    @Environment(AppModel.self) private var model
    var chapters: [Chapter]
    var tint: Color = BX.coral
    var showsPreview = true

    @State private var scrubTime: Double?
    @State private var hoverTime: Double?

    var body: some View {
        let state = model.player.state
        let duration = max(state.duration, 1)
        GeometryReader { geo in
            let shown = scrubTime ?? state.time
            ZStack(alignment: .leading) {
                ChapterBar(chapters: chapters, position: shown, duration: duration, height: 4, tint: tint)
                Circle().fill(.white)
                    .frame(width: scrubTime == nil ? 12 : 18, height: scrubTime == nil ? 12 : 18)
                    .shadow(color: tint.opacity(0.5), radius: scrubTime == nil ? 0 : 6)
                    .offset(x: geo.size.width * CGFloat(shown / duration) - (scrubTime == nil ? 6 : 9))
                    .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in scrubTime = max(0, min(duration, Double(v.location.x / geo.size.width) * duration)) }
                    .onEnded { _ in
                        if let t = scrubTime { model.player.seek(to: t) }
                        scrubTime = nil
                    }
            )
            #if os(macOS)
            .onContinuousHover { phase in
                if case .active(let p) = phase { hoverTime = Double(p.x / geo.size.width) * duration } else { hoverTime = nil }
            }
            #endif
            .overlay(alignment: .topLeading) {
                if showsPreview, let t = scrubTime ?? hoverTime, let video = model.player.video {
                    ScrubPreview(video: video, time: t, chapter: Chapter.current(in: chapters, at: t))
                        .fixedSize()
                        .alignmentGuide(.leading) { d in d.width / 2 - geo.size.width * CGFloat(t / duration) }
                        .alignmentGuide(.top) { d in d.height + 14 }
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Format.clock(state.time)) of \(Format.clock(state.duration))")
        .accessibilityAdjustableAction { direction in
            model.player.skip(direction == .increment ? 10 : -10)
        }
    }
}

struct ScrubPreview: View {
    var video: Video
    var time: Double
    var chapter: Chapter?
    var body: some View {
        VStack(spacing: 6) {
            VideoThumbnail(video, radius: 10, showDuration: false)
                .frame(width: 156)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 2))
            Text([chapter?.title, Format.clock(time)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
        }
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

/// Glass control bar laid over the player.
struct PlayerControlBar: View {
    @Environment(AppModel.self) private var model
    var chapters: [Chapter]
    var compact = false
    var tint: Color = BX.coral
    var extra: AnyView? = nil

    var body: some View {
        let s = model.player.state
        VStack(spacing: 8) {
            ChapterScrubber(chapters: chapters, tint: tint)
            HStack(spacing: compact ? 6 : 10) {
                Button { model.player.toggle() } label: {
                    Image(systemName: s.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 34, height: 34)
                }
                .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
                Button { model.player.skip(-10) } label: { Image(systemName: "gobackward.10").frame(width: 30, height: 30) }
                    .accessibilityLabel("Back 10 seconds")
                Button { model.player.skip(10) } label: { Image(systemName: "goforward.10").frame(width: 30, height: 30) }
                    .accessibilityLabel("Forward 10 seconds")
                Text("\(Format.clock(s.time)) / \(Format.clock(s.duration))")
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                if !compact, let c = Chapter.current(in: chapters, at: s.time) {
                    Text("· \(c.title)").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let extra { extra }
                Menu {
                    ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { r in
                        Button { model.player.setRate(r) } label: {
                            if r == s.rate { Label("\(r.formatted())×", systemImage: "checkmark") } else { Text("\(r.formatted())×") }
                        }
                    }
                } label: {
                    Text("\(s.rate.formatted())×").font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(.white.opacity(0.14), in: .rect(cornerRadius: 7))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .boxGlass(.rect(cornerRadius: 16, style: .continuous), tint: .black.opacity(0.25))
    }
}

/// Idea 06: the video as a grid of chapters.
struct SkimView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var video: Video
    @State private var notes: [Note] = []

    var body: some View {
        let chapters = video.chapters
        let time = model.player.state.time
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        LargeTitle("Skim", size: 26)
                        Text(chapters.isEmpty ? "No chapters in this video's description" : "\(chapters.count) chapters · \(Format.minutes(model.player.state.duration)) · pinch in to go back")
                            .font(.system(size: 12.5)).foregroundStyle(BX.muted)
                    }
                    Spacer()
                    CircleIconButton("arrow.down.right.and.arrow.up.left", label: "Close skim", size: 44) { dismiss() }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 14) {
                    ForEach(chapters) { c in
                        let watched = min(1, max(0, (time - c.start) / max(c.length, 1)))
                        let current = time >= c.start && time < c.end
                        Button { model.player.seek(to: c.start); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtView(seed: video.id + "\(c.index)", title: c.title, word: ArtWord.from(c.title), palette: ArtPalette.forSeed(video.id))
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .topLeading) { Badge(text: String(format: "%02d", c.index + 1)).padding(8) }
                                    .overlay(alignment: .bottom) { ProgressLine(value: watched, height: 3).clipShape(.rect(cornerRadius: 14)) }
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(current ? BX.coral : .clear, lineWidth: 2).padding(-3))
                                Text(c.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(current ? BX.coralText : BX.text).lineLimit(1)
                                Text("\(Format.clock(c.start)) – \(Format.clock(c.end)) · \(Format.minutes(c.length))")
                                    .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(BX.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(notes) { n in
                        Button { model.player.seek(to: n.time); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtView(seed: "note\(n.id ?? 0)", title: n.text, word: Format.clock(n.time), palette: ArtPalette.all[4])
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .topLeading) { Badge(text: "NOTE", fill: BX.amber, ink: BX.coralInk).padding(8) }
                                Text("Your note").font(.system(size: 13.5, weight: .semibold))
                                Text(n.text).font(.system(size: 11.5)).foregroundStyle(BX.muted).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(BX.ground)
        .observing(model.store, id: video.id, { [id = video.id] db in try Q.notes(db, videoId: id) }) { notes = $0 }
    }
}

/// Idea 07: timestamped notes for the current video.
struct NotesPanel: View {
    @Environment(AppModel.self) private var model
    var video: Video
    @State private var notes: [Note] = []
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes").font(.system(size: 16, weight: .bold))
                    Text("Tap a time to jump there").font(.system(size: 12)).foregroundStyle(BX.muted)
                }
                Spacer()
                ShareLink(item: markdown, preview: SharePreview("\(video.title) notes.md")) {
                    Label("Export .md", systemImage: "square.and.arrow.down").font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 32).background(BX.surface3, in: .rect(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(notes.isEmpty)
            }
            .padding(16)
            Divider().overlay(BX.line)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if notes.isEmpty {
                        Text("Press N (or the note button) to pin a thought to this moment.")
                            .font(.system(size: 13)).foregroundStyle(BX.muted).padding(.top, 8)
                    }
                    ForEach(notes) { n in
                        HStack(alignment: .top, spacing: 12) {
                            Button { model.player.seek(to: n.time) } label: {
                                Text(Format.clock(n.time)).font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .foregroundStyle(BX.amber).padding(.horizontal, 8).frame(height: 24)
                                    .background(BX.amber.opacity(0.14), in: .rect(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Jump to \(Format.clock(n.time))")
                            Text(n.text).font(.system(size: 13.5)).foregroundStyle(BX.text2).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .contextMenu {
                            Button(role: .destructive) { if let id = n.id { Task { try? await model.store.deleteNote(id) } } } label: { Label("Delete note", systemImage: "trash") }
                        }
                    }
                }
                .padding(16)
            }
            Divider().overlay(BX.line)
            HStack(alignment: .top, spacing: 10) {
                Text(Format.clock(model.player.state.time)).font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(BX.coralText).padding(.horizontal, 7).frame(height: 22)
                    .background(BX.coral.opacity(0.16), in: .rect(cornerRadius: 6))
                TextField("Write a note for this moment", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(save)
                Button(action: save) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(BX.coral) }
                    .buttonStyle(.plain).disabled(draft.isEmpty).accessibilityLabel("Save note")
            }
            .padding(12)
            .background(BX.ground, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BX.coral.opacity(focused ? 0.6 : 0.25), lineWidth: 1.5))
            .padding(12)
        }
        .observing(model.store, id: video.id, { [id = video.id] db in try Q.notes(db, videoId: id) }) { notes = $0 }
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let time = model.player.state.time
        draft = ""
        Task { try? await model.store.addNote(videoId: video.id, time: time, text: text) }
    }

    private var markdown: String {
        var out = "# \(video.title)\n\n\(video.channelTitle) · \(video.watchURL.absoluteString)\n\n"
        for n in notes {
            out += "- [\(Format.clock(n.time))](\(video.watchURL.absoluteString)&t=\(Int(n.time))s) \(n.text)\n"
        }
        return out
    }
}

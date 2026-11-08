import SwiftUI
import GroupActivities
import BoxtubeCore
import BoxtubeUI

/// Idea 10: SharePlay. Everyone in the FaceTime call stays in sync, sends reactions and votes on what's next.
struct WatchTogetherActivity: GroupActivity {
    var videoId: String
    var title: String

    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = title
        m.subtitle = "Boxtube"
        m.type = .watchTogether
        m.fallbackURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)")
        return m
    }
}

enum TogetherMessage: Codable, Sendable {
    case load(videoId: String, time: Double)
    case play(time: Double)
    case pause(time: Double)
    case seek(time: Double)
    case react(kind: String)
    case vote(videoId: String)
}

@MainActor
@Observable
final class WatchTogether {
    static let shared = WatchTogether()

    struct Reaction: Identifiable, Hashable {
        let id = UUID()
        var kind: String
        var x: CGFloat
        var mine: Bool
    }

    var isActive = false
    var participantCount = 1
    var reactions: [Reaction] = []
    var lastEvent: String?
    var votes: [String: Int] = [:]
    var myVote: String?

    private weak var model: AppModel?
    private var session: GroupSession<WatchTogetherActivity>?
    private var messenger: GroupSessionMessenger?
    private var tasks: [Task<Void, Never>] = []
    private var applyingRemote = false
    private var lastSentPlaying: Bool?
    private var lastTime: Double = 0

    func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        Task { [weak self] in
            for await session in WatchTogetherActivity.sessions() { self?.join(session) }
        }
        if ProcessInfo.processInfo.arguments.contains("-togetherDemo") { startDemo() }
    }

    func start(with video: Video) {
        guard !isActive else { return }
        Task {
            let activity = WatchTogetherActivity(videoId: video.id, title: video.title)
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                _ = try? await activity.activate()
            case .activationDisabled:
                model?.flash("Start a FaceTime call to watch together")
            default:
                break
            }
        }
    }

    func leave() {
        session?.leave()
        reset()
    }

    func react(_ kind: String) {
        addReaction(kind, mine: true)
        send(.react(kind: kind))
    }

    func vote(_ videoId: String) {
        guard myVote != videoId else { return }
        if let previous = myVote { votes[previous, default: 1] -= 1 }
        myVote = videoId
        votes[videoId, default: 0] += 1
        send(.vote(videoId: videoId))
    }

    /// Called by views whenever local playback state changes, to mirror it to others.
    func localStateChanged(isPlaying: Bool, time: Double) {
        guard isActive, !applyingRemote else { lastTime = time; return }
        if lastSentPlaying != isPlaying {
            lastSentPlaying = isPlaying
            send(isPlaying ? .play(time: time) : .pause(time: time))
        } else if abs(time - lastTime) > 3 {
            send(.seek(time: time))
        }
        lastTime = time
    }

    // MARK: Session

    private func join(_ session: GroupSession<WatchTogetherActivity>) {
        reset()
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger
        session.join()
        isActive = true

        tasks.append(Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                self?.participantCount = participants.count
            }
        })
        tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state { self?.reset() }
            }
        })
        tasks.append(Task { [weak self] in
            for await (message, _) in messenger.messages(of: TogetherMessage.self) {
                self?.apply(message)
            }
        })
        // Everyone opens the session's video.
        let videoId = session.activity.videoId
        Task { [weak self] in
            guard let model = self?.model, let video = await model.feed.ensureVideo(videoId) else { return }
            if model.player.video?.id != videoId { model.open(video) }
        }
    }

    private func apply(_ message: TogetherMessage) {
        guard let model else { return }
        applyingRemote = true
        defer { Task { @MainActor in try? await Task.sleep(for: .milliseconds(600)); self.applyingRemote = false } }
        switch message {
        case .load(let id, let t):
            Task { if let v = await model.feed.ensureVideo(id) { model.open(v, at: t) } }
            lastEvent = "Someone picked the next video"
        case .play(let t):
            if abs(model.player.state.time - t) > 1.5 { model.player.seek(to: t) }
            model.player.play(); lastSentPlaying = true
            lastEvent = "Someone pressed play"
        case .pause(let t):
            model.player.seek(to: t); model.player.pause(); lastSentPlaying = false
            lastEvent = "Someone paused for everyone"
        case .seek(let t):
            model.player.seek(to: t)
            lastEvent = "Someone jumped to \(Format.clock(t))"
        case .react(let kind):
            addReaction(kind, mine: false)
        case .vote(let id):
            votes[id, default: 0] += 1
        }
    }

    private func send(_ message: TogetherMessage) {
        guard let messenger else { return }
        Task { try? await messenger.send(message) }
    }

    private func addReaction(_ kind: String, mine: Bool) {
        let r = Reaction(kind: kind, x: .random(in: 0.55...0.92), mine: mine)
        reactions.append(r)
        Task { try? await Task.sleep(for: .seconds(2.4)); reactions.removeAll { $0.id == r.id } }
    }

    private func reset() {
        tasks.forEach { $0.cancel() }
        tasks = []
        session = nil
        messenger = nil
        isActive = false
        participantCount = 1
        votes = [:]
        myVote = nil
        lastEvent = nil
    }

    /// Launch with -togetherDemo to preview the UI without a FaceTime call.
    private func startDemo() {
        isActive = true
        participantCount = 3
        lastEvent = "Priya rewound 30s for everyone"
        votes = [:]
    }
}

// MARK: - UI

struct TogetherBanner: View {
    var together: WatchTogether
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(0..<min(together.participantCount, 3), id: \.self) { i in
                    Circle().fill([BX.violet, Color(hex: 0x2F8F83), Color(hex: 0xD97706)][i])
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Color(hex: 0x18181C), lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(together.participantCount > 1 ? "Watching with \(together.participantCount - 1) other\(together.participantCount == 2 ? "" : "s")" : "Waiting for others to join")
                    .font(.system(size: 13.5, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0x4ADE80)).frame(width: 6, height: 6)
                    Text(together.lastEvent ?? "In sync over FaceTime").font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x4ADE80))
                }
            }
            Spacer()
            Button("Leave") { together.leave() }
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 32)
                .background(BX.surface3, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(height: 52)
        .background(Color(hex: 0x18181C), in: Capsule())
        .overlay(Capsule().strokeBorder(BX.line))
    }
}

struct ReactionBar: View {
    var together: WatchTogether
    var body: some View {
        HStack {
            reaction("heart", label: "Send heart") { Image(systemName: "heart.fill").foregroundStyle(BX.coral) }
            reaction("ha", label: "Send laugh") { Text("HA").foregroundStyle(BX.amber) }
            reaction("wow", label: "Send wow") { Text("!?").foregroundStyle(Color(hex: 0x8FB0F2)) }
            reaction("plus", label: "Send plus one") { Text("+1").foregroundStyle(Color(hex: 0x4ADE80)) }
        }
        .font(.system(size: 16, weight: .heavy))
        .padding(.horizontal, 8)
        .frame(height: 64)
        .boxGlass(Capsule())
        .overlay(alignment: .bottom) {
            ZStack {
                ForEach(together.reactions) { r in FloatingReaction(reaction: r) }
            }
            .allowsHitTesting(false)
        }
    }

    private func reaction<L: View>(_ kind: String, label: String, @ViewBuilder content: () -> L) -> some View {
        Button { together.react(kind) } label: {
            content().frame(maxWidth: .infinity).frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FloatingReaction: View {
    var reaction: WatchTogether.Reaction
    @State private var rise = false
    var body: some View {
        GeometryReader { geo in
            Group {
                switch reaction.kind {
                case "heart": Image(systemName: "heart.fill").foregroundStyle(BX.coral)
                case "ha": Text("HA").foregroundStyle(BX.amber)
                case "wow": Text("!?").foregroundStyle(Color(hex: 0x8FB0F2))
                default: Text("+1").foregroundStyle(Color(hex: 0x4ADE80))
                }
            }
            .font(.system(size: 22, weight: .heavy))
            .position(x: geo.size.width * reaction.x, y: rise ? -260 : -20)
            .opacity(rise ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 2.2)) { rise = true } }
        }
    }
}

struct VoteCard: View {
    var together: WatchTogether
    var candidates: [Video]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vote: what's next?").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("Plays when this ends").font(.system(size: 12)).foregroundStyle(BX.muted)
            }
            let total = max(1, together.votes.values.reduce(0, +))
            ForEach(candidates) { v in
                let count = together.votes[v.id] ?? 0
                let mine = together.myVote == v.id
                Button { together.vote(v.id) } label: {
                    HStack(spacing: 10) {
                        VideoThumbnail(v, radius: 7, showDuration: false).frame(width: 64)
                        Text(v.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(count) vote\(count == 1 ? "" : "s")").font(.system(size: 12, weight: .bold)).foregroundStyle(mine ? BX.coralText : BX.muted)
                    }
                    .padding(8)
                    .background(alignment: .leading) {
                        GeometryReader { g in (mine ? BX.coral.opacity(0.12) : .white.opacity(0.05)).frame(width: g.size.width * CGFloat(count) / CGFloat(total)) }
                    }
                    .background(Color(hex: 0x1E1E23), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(mine ? BX.coral.opacity(0.5) : .clear, lineWidth: 1.5))
                    .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .boxCard(18)
    }
}

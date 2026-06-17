import SwiftUI
import Charts

struct MemberListView: View {
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var pointStore:    PointStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var purchaseStore: PurchaseStore

    @State private var selectedTab = 0
    @State private var selectedEntry: RankedEntry?

    private var rankedEntries: [RankedEntry] {
        let me = Friend(id: profileStore.myId, name: profileStore.name, emoji: profileStore.emoji, photoURL: profileStore.photoURL)
        let all = [me] + friendStore.friends

        let sorted = all
            .map { RankedEntry(rank: 0, friend: $0,
                               avgSpeed: pointStore.averageSpeed(for: $0.id),
                               isMe: $0.id == profileStore.myId) }
            .filter { $0.avgSpeed != nil }
            .sorted {
                switch ($0.avgSpeed, $1.avgSpeed) {
                case (.some(let a), .some(let b)): return a < b
                case (.some, .none):               return true
                default:                           return false
                }
            }

        return sorted.enumerated().map { i, entry in
            RankedEntry(rank: i + 1, friend: entry.friend,
                        avgSpeed: entry.avgSpeed, isMe: entry.isMe)
        }
    }

    private var maxSpeed: Double {
        let speeds = rankedEntries.compactMap(\.avgSpeed)
        return max(speeds.max() ?? 60, 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("ランキング").tag(0)
                Text("インサイト").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))

            if selectedTab == 0 {
                NavigationStack {
                    List {
                        reportHeaderSection
                        rankingSection
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("シゴできランキング")
                    .navigationBarTitleDisplayMode(.inline)
                    .task { await friendStore.fetchProStatuses() }
                    .sheet(item: $selectedEntry) { entry in
                        FriendProfileSheet(entry: entry, outOf: rankedEntries.count)
                            .environmentObject(pointStore)
                            .environmentObject(friendStore)
                            .environmentObject(purchaseStore)
                    }
                }
            } else {
                InsightView()
                    .environmentObject(questionStore)
                    .environmentObject(friendStore)
                    .environmentObject(profileStore)
                    .environmentObject(purchaseStore)
            }
        }
    }

    // MARK: - レポートヘッダー

    private var reportHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.secondary)
                    Text("週次シゴでき評価")
                        .font(.headline)
                    Spacer()
                    Text(periodLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("評価指標：直近7日間の平均回答速度")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - ランキング

    private var rankingSection: some View {
        Section {
            columnHeader
            ForEach(rankedEntries) { entry in
                RankingRow(entry: entry, maxSpeed: maxSpeed,
                           title: pointStore.title(rank: entry.rank,
                                                   outOf: rankedEntries.count,
                                                   isPro: entry.isMe ? purchaseStore.isPro : friendStore.isPro(entry.friend)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !entry.isMe else { return }
                        selectedEntry = entry
                    }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("位")
                .frame(width: 36, alignment: .center)
            Text("氏名・称号")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            Text("平均速度")
                .frame(width: 120, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }

    // MARK: - ヘルパー

    private var periodLabel: String {
        let end   = Date()
        let start = end.addingTimeInterval(-7 * 24 * 60 * 60)
        let fmt   = DateFormatter()
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: start))〜\(fmt.string(from: end))"
    }
}

// MARK: - データモデル

private struct RankedEntry: Identifiable {
    var id: UUID { friend.id }
    let rank:     Int
    let friend:   Friend
    let avgSpeed: Double?
    let isMe:     Bool
}

// MARK: - ランキング行

private struct RankingRow: View {
    let entry:    RankedEntry
    let maxSpeed: Double
    let title:    PointTitle

    var body: some View {
        HStack(spacing: 0) {
            rankBadge
                .frame(width: 36, alignment: .center)

            HStack(spacing: 8) {
                UserAvatarView(emoji: entry.friend.emoji, photoURL: entry.friend.photoURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.friend.name)
                            .font(.subheadline)
                            .fontWeight(entry.isMe ? .semibold : .regular)
                        if entry.isMe {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(title.display)
                        .font(.caption2)
                        .foregroundStyle(titleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            speedBar
                .frame(width: 120)
        }
        .padding(.vertical, 4)
        .listRowBackground(entry.isMe ? Color.blue.opacity(0.06) : Color.clear)
    }

    private var speedBar: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                let ratio  = entry.avgSpeed.map { min($0 / maxSpeed, 1.0) } ?? 1.0
                let filled = geo.size.width * ratio
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(UIColor.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(filled, 6), height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)

            Text(speedLabel)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(barColor)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var rankBadge: some View {
        Group {
            switch entry.rank {
            case 1: Text("🥇").font(.title3)
            case 2: Text("🥈").font(.title3)
            case 3: Text("🥉").font(.title3)
            default:
                Text("\(entry.rank)")
                    .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
            }
        }
    }

    private var speedLabel: String {
        guard let s = entry.avgSpeed else { return "–" }
        return formatAverageSpeed(s)
    }

    private var barColor: Color {
        guard let s = entry.avgSpeed else { return .secondary }
        if s < 60  { return .orange }
        if s < 180 { return .blue   }
        return .secondary
    }

    private var titleColor: Color {
        switch title.color {
        case "orange": return .orange
        case "blue":   return .blue
        case "yellow": return Color(red: 0.8, green: 0.6, blue: 0.0)
        case "purple": return .purple
        default:       return .secondary
        }
    }
}

// MARK: - 友達プロフィールシート

private struct FriendProfileSheet: View {
    let entry: RankedEntry
    let outOf: Int

    @EnvironmentObject private var pointStore:    PointStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .frame(width: 36, height: 5)
                .foregroundStyle(Color(UIColor.systemGray4))
                .padding(.top, 12)

            ProfileIDCard(
                name:         entry.friend.name,
                emoji:        entry.friend.emoji,
                profileImage: nil,
                username:     entry.friend.username,
                rank:         entry.rank,
                outOf:        outOf,
                avgSpeed:     entry.avgSpeed,
                answerCount:  pointStore.history(for: entry.friend.id).count,
                isPro:        entry.isMe ? purchaseStore.isPro : friendStore.isPro(entry.friend)
            )
            .padding(.horizontal)

            Spacer()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    MemberListView()
        .environmentObject(FriendStore())
        .environmentObject(PointStore())
        .environmentObject(ProfileStore())
        .environmentObject(QuestionStore())
        .environmentObject(PurchaseStore())
}

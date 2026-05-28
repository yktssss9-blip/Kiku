import SwiftUI

struct MemberListView: View {
    @EnvironmentObject private var friendStore:  FriendStore
    @EnvironmentObject private var pointStore:   PointStore
    @EnvironmentObject private var profileStore: ProfileStore

    /// 自分 + 友達をポイント降順でランク付け
    private var rankedEntries: [(rank: Int, friend: Friend, total: Int, isMe: Bool)] {
        let me = Friend(id: profileStore.myId, name: profileStore.name, emoji: profileStore.emoji)
        let all = [me] + friendStore.friends

        let sorted = all
            .map { ($0, pointStore.total(for: $0.id)) }
            .sorted { $0.1 > $1.1 }

        var result: [(rank: Int, friend: Friend, total: Int, isMe: Bool)] = []
        var currentRank = 1
        for (i, item) in sorted.enumerated() {
            if i > 0 && item.1 < sorted[i - 1].1 { currentRank = i + 1 }
            result.append((rank: currentRank, friend: item.0, total: item.1,
                           isMe: item.0.id == profileStore.myId))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            rankingList
                .navigationTitle("ランキング")
        }
    }

    // MARK: - ランキング表

    private var rankingList: some View {
        List {
            Section {
                rankingHeader
            }
            Section {
                ForEach(rankedEntries, id: \.friend.id) { item in
                    RankingRow(rank:         item.rank,
                               friend:       item.friend,
                               total:        item.total,
                               history:      pointStore.history(for: item.friend.id),
                               title:        pointStore.title(rank: item.rank,
                                                              outOf: rankedEntries.count),
                               isMe:         item.isMe,
                               profileImage: item.isMe ? profileStore.profileImage : nil)
                }
            }
        }
    }

    private var rankingHeader: some View {
        HStack(spacing: 0) {
            Text("順位")
                .frame(width: 44, alignment: .center)
            Text("名前")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("合計")
                .frame(width: 72, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

// MARK: - ランキング行

private struct RankingRow: View {
    let rank:         Int
    let friend:       Friend
    let total:        Int
    let history:      [PointRecord]
    let title:        PointTitle
    var isMe:         Bool   = false
    var profileImage: Image? = nil

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // メイン行
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    // 順位バッジ
                    rankBadge
                        .frame(width: 44, alignment: .center)

                    // アイコン + 名前 + 称号
                    HStack(spacing: 8) {
                        Group {
                            if let image = profileImage {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Text(friend.emoji)
                                    .font(.title3)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(friend.name).font(.body)
                                if isMe {
                                    Text("あなた")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(title.display)
                                .font(.caption2)
                                .foregroundStyle(titleColor(title))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(titleColor(title).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 合計ポイント
                    HStack(spacing: 2) {
                        Text("🏆")
                        Text("\(total)pt")
                            .fontWeight(.semibold)
                            .foregroundStyle(total > 0 ? .primary : .secondary)
                    }
                    .font(.subheadline)
                    .frame(width: 72, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展開：獲得履歴
            if isExpanded {
                Divider().padding(.leading, 44)

                if history.isEmpty {
                    Text("まだ回答履歴がありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 44)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(history.prefix(5)) { record in
                            HStack {
                                Text(record.tier.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                Text(record.questionText)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("+\(record.points)pt")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(tierColor(record.tier))
                            }
                            .padding(.leading, 44)
                            .padding(.vertical, 5)
                            Divider().padding(.leading, 44)
                        }
                        if history.count > 5 {
                            Text("他 \(history.count - 5) 件")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 4)
                                .padding(.bottom, 4)
                        }
                    }
                }
            }
        }
    }

    private var rankBadge: some View {
        Group {
            switch rank {
            case 1:
                Text("🥇").font(.title3)
            case 2:
                Text("🥈").font(.title3)
            case 3:
                Text("🥉").font(.title3)
            default:
                Text("\(rank)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tierColor(_ tier: PointTier) -> Color {
        switch tier {
        case .fast:                    return .orange
        case .normal:                  return .blue
        case .late, .senderFast, .senderNormal: return .secondary
        }
    }

    private func titleColor(_ title: PointTitle) -> Color {
        switch title.color {
        case "orange": return .orange
        case "blue":   return .blue
        case "yellow": return Color(red: 0.8, green: 0.6, blue: 0.0)
        case "purple": return .purple
        default:       return .secondary
        }
    }
}

#Preview {
    MemberListView()
        .environmentObject(FriendStore())
        .environmentObject(PointStore())
        .environmentObject(ProfileStore())
}

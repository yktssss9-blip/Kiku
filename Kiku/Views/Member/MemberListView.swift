import SwiftUI

struct MemberListView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var pointStore:  PointStore
    @State private var isShowingAddSheet = false

    /// ポイント降順でソートした友達一覧
    private var rankedFriends: [(rank: Int, friend: Friend, total: Int)] {
        let sorted = friendStore.friends
            .map { ($0, pointStore.total(for: $0.id)) }
            .sorted { $0.1 > $1.1 }

        var result: [(rank: Int, friend: Friend, total: Int)] = []
        var currentRank = 1
        for (i, item) in sorted.enumerated() {
            if i > 0 && item.1 < sorted[i - 1].1 { currentRank = i + 1 }
            result.append((rank: currentRank, friend: item.0, total: item.1))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if friendStore.friends.isEmpty {
                    emptyState
                } else {
                    friendList
                }
            }
            .navigationTitle("友達")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isShowingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                MemberAddView { newFriend in
                    friendStore.add(newFriend)
                }
            }
        }
    }

    // MARK: - ランキング表

    private var friendList: some View {
        List {
            // ── ランキングヘッダー ──
            Section {
                rankingHeader
            }

            // ── ランキング行 ──
            Section {
                ForEach(rankedFriends, id: \.friend.id) { item in
                    RankingRow(rank: item.rank, friend: item.friend, total: item.total,
                               history: pointStore.history(for: item.friend.id))
                }
                .onDelete { indexSet in
                    // 元の friendStore インデックスに変換して削除
                    let ids = indexSet.map { rankedFriends[$0].friend.id }
                    friendStore.friends.removeAll { ids.contains($0.id) }
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

    // MARK: - 空状態

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("友達がいません")
                .font(.headline)
            Text("＋ボタンから追加してください")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - ランキング行

private struct RankingRow: View {
    let rank:    Int
    let friend:  Friend
    let total:   Int
    let history: [PointRecord]

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

                    // 絵文字 + 名前
                    HStack(spacing: 8) {
                        Text(friend.emoji).font(.title3)
                        Text(friend.name).font(.body)
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
        case .fast:   return .orange
        case .normal: return .blue
        case .late:   return .secondary
        }
    }
}

#Preview {
    MemberListView()
        .environmentObject(FriendStore())
        .environmentObject(PointStore())
}

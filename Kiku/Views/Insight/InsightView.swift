import SwiftUI
import UserNotifications

// MARK: - Data Model

private struct FriendInsight: Identifiable {
    var id: UUID { friend.id }
    let friend:          Friend
    let bestPreset:      (label: String, emoji: String, start: Int, end: Int)
    let fastRate:        Double?   // nil = データ不足（自己申告を使用中）
    let normalRate:      Double?
    let lateRate:        Double?
    let dataCount:       Int
    let isFromDeclared:  Bool
}

// MARK: - InsightView

struct InsightView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var purchaseStore: PurchaseStore

    @State private var currentHour    = Calendar.current.component(.hour, from: Date())
    @State private var schedulingFor: FriendInsight? = nil
    @State private var showPaywall    = false

    private let clockTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var insights: [FriendInsight] {
        friendStore.friends
            .filter { !friendStore.isBlocked($0.id) }
            .map { buildInsight(for: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    currentTimeBanner
                        .padding(.horizontal, 16)

                    if insights.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(insights) { insight in
                                FriendInsightCard(insight: insight) {
                                    if purchaseStore.isPro {
                                        schedulingFor = insight
                                    } else {
                                        showPaywall = true
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("インサイト")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { currentHour = Calendar.current.component(.hour, from: Date()) }
            .onReceive(clockTimer) { _ in
                currentHour = Calendar.current.component(.hour, from: Date())
            }
            .sheet(item: $schedulingFor) { insight in
                ScheduledSendSheet(insight: insight)
                    .environmentObject(questionStore)
                    .environmentObject(friendStore)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(purchaseStore)
            }
        }
    }

    // MARK: - Current Time Banner

    private var currentTimeBanner: some View {
        let isBadTime = currentHour >= 22 || currentHour < 7
        let accent: Color = isBadTime ? .purple : .blue
        let icon   = isBadTime ? "moon.stars.fill" : "chart.line.uptrend.xyaxis"
        let message = isBadTime
            ? "深夜・早朝は返信が遅くなりがちです。翌朝に予約送信するとシゴできを引き出せます。"
            : "今は返信が来やすい時間帯です。すぐに質問を送ってみましょう。"

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("現在 \(currentHour)時台")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("友達を追加するとインサイトが表示されます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Insight Calculation

    private func buildInsight(for friend: Friend) -> FriendInsight {
        var data: [(sendHour: Int, tier: PointTier)] = []

        for q in questionStore.questions {
            guard let ans = q.answers.first(where: { $0.memberId == friend.id }),
                  ans.value != "pending",
                  let answeredAt = ans.answeredAt else { continue }
            let sendHour = Calendar.current.component(.hour, from: q.createdAt)
            let elapsed  = answeredAt.timeIntervalSince(q.createdAt)
            data.append((sendHour, PointTier.tier(for: elapsed)))
        }

        let total = data.count

        // データ不足 → 自己申告にフォールバック
        if total < 3 {
            let declaredPreset = ProfileStore.activeHourPresets.first {
                $0.start == (friend.activeHourStart ?? 9)
            } ?? ProfileStore.activeHourPresets[1]
            return FriendInsight(friend: friend, bestPreset: declaredPreset,
                                 fastRate: nil, normalRate: nil, lateRate: nil,
                                 dataCount: total, isFromDeclared: true)
        }

        // 送信時間帯別 ⚡️超速率が最も高いプリセットを探す
        var bestPreset = ProfileStore.activeHourPresets[1]
        var bestRate   = -1.0
        for preset in ProfileStore.activeHourPresets {
            let bucket = data.filter {
                preset.end == 24 ? $0.sendHour >= preset.start
                                 : $0.sendHour >= preset.start && $0.sendHour < preset.end
            }
            guard !bucket.isEmpty else { continue }
            let rate = Double(bucket.filter { $0.tier == .fast }.count) / Double(bucket.count)
            if rate > bestRate { bestRate = rate; bestPreset = preset }
        }

        let fastCount   = data.filter { $0.tier == .fast }.count
        let normalCount = data.filter { $0.tier == .normal }.count
        let lateCount   = data.filter { $0.tier == .late }.count

        return FriendInsight(
            friend: friend, bestPreset: bestPreset,
            fastRate:   Double(fastCount)   / Double(total),
            normalRate: Double(normalCount) / Double(total),
            lateRate:   Double(lateCount)   / Double(total),
            dataCount: total, isFromDeclared: false
        )
    }
}

// MARK: - FriendInsightCard

private struct FriendInsightCard: View {
    let insight:    FriendInsight
    let onSchedule: () -> Void

    private var endHourLabel: String {
        let end = insight.bestPreset.end
        return end == 24 ? "0" : "\(end)"
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── 友達情報 + ベストタイム ──
            HStack(spacing: 12) {
                Text(insight.friend.emoji)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.friend.name)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(insight.bestPreset.emoji)
                        Text(insight.isFromDeclared
                             ? "\(insight.bestPreset.start)〜\(endHourLabel)時（自己申告）"
                             : "\(insight.bestPreset.start)〜\(endHourLabel)時に送ると速い")
                            .font(.subheadline)
                            .foregroundStyle(insight.isFromDeclared ? .secondary : .primary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // ── ティア比率バー（実データあり）or データ不足表示 ──
            if let fast = insight.fastRate,
               let normal = insight.normalRate,
               let late = insight.lateRate {
                tierBar(fast: fast, normal: normal, late: late)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                dataInsufficientRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            Divider().padding(.horizontal, 14)

            // ── 予約送信ボタン ──
            Button(action: onSchedule) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.fill")
                        .font(.caption)
                    Text("明朝 \(insight.bestPreset.start):00 に予約送信")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.0))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tierBar(fast: Double, normal: Double, late: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if fast > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Color.orange)
                            .frame(width: max(geo.size.width * fast, 6))
                    }
                    if normal > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Color.blue)
                            .frame(width: max(geo.size.width * normal, 6))
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(UIColor.systemFill))
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                tierLabel("⚡️", pct: fast)
                tierLabel("🕐", pct: normal)
                tierLabel("💬", pct: late)
                Spacer()
                Text("\(insight.dataCount)件のデータより")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func tierLabel(_ icon: String, pct: Double) -> some View {
        HStack(spacing: 2) {
            Text(icon).font(.caption2)
            Text("\(Int(pct * 100))%")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    private var dataInsufficientRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(insight.dataCount == 0
                 ? "まだ質問を送っていません。送ってみましょう。"
                 : "データが少ないため自己申告を表示中（あと\(3 - insight.dataCount)件で更新）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - ScheduledSendSheet

private struct ScheduledSendSheet: View {
    let insight: FriendInsight
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText = ""
    @State private var showConfirm  = false

    private var canSchedule: Bool {
        !questionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var endHourLabel: String {
        let end = insight.bestPreset.end
        return end == 24 ? "0" : "\(end)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                // 送信先 + 予定時刻
                HStack(spacing: 14) {
                    Text(insight.friend.emoji)
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.friend.name)
                            .font(.headline)
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill").font(.caption2)
                            Text("明朝 \(insight.bestPreset.start):00 に送信予定")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                        Text("\(insight.bestPreset.emoji) \(insight.bestPreset.start)〜\(endHourLabel)時が狙い目")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 質問文入力
                VStack(alignment: .leading, spacing: 8) {
                    Text("質問文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("例: 今夜ご飯どうする？", text: $questionText, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                Spacer()

                // 予約ボタン
                Button { scheduleNotification() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark.fill")
                        Text("明朝 \(insight.bestPreset.start):00 に予約する")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSchedule ? Color.blue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSchedule)
            }
            .padding(20)
            .navigationTitle("予約送信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .alert("予約しました", isPresented: $showConfirm) {
                Button("OK") { dismiss() }
            } message: {
                Text("明朝 \(insight.bestPreset.start):00 に通知でお知らせします。通知をタップして送信してください。")
            }
        }
    }

    private func scheduleNotification() {
        let trimmed = questionText.trimmingCharacters(in: .whitespaces)
        let content = UNMutableNotificationContent()
        content.title = "\(insight.friend.name) への予約質問の時間です"
        content.body  = "「\(trimmed)」を送りましょう"
        content.sound = .default

        var comps        = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.day        = (comps.day ?? 0) + 1
        comps.hour       = insight.bestPreset.start
        comps.minute     = 0
        comps.second     = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "scheduled-\(insight.friend.id.uuidString)-\(Date().timeIntervalSince1970)",
            content:    content,
            trigger:    trigger
        )
        UNUserNotificationCenter.current().add(request)
        showConfirm = true
    }
}

// MARK: - Preview

#Preview {
    InsightView()
        .environmentObject(QuestionStore())
        .environmentObject(FriendStore())
        .environmentObject(ProfileStore())
        .environmentObject(PurchaseStore())
}

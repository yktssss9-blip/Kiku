import Foundation

class PointStore: ObservableObject {
    @Published var records: [PointRecord] = [] {
        didSet { save() }
    }

    private let key = "kiku.points"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PointRecord].self, from: data) {
            records = decoded
        }
    }

    // MARK: - 集計（直近7日間のみ有効）

    private static let retentionDays: Double = 7

    /// 有効期限内（7日以内）のレコード
    private var activeRecords: [PointRecord] {
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 24 * 60 * 60)
        return records.filter { $0.earnedAt >= cutoff }
    }

    /// メンバーの合計ポイント（直近7日間）
    func total(for memberId: UUID) -> Int {
        activeRecords.filter { $0.memberId == memberId }.reduce(0) { $0 + $1.points }
    }

    /// メンバーの獲得履歴（直近7日間・新しい順）
    func history(for memberId: UUID) -> [PointRecord] {
        activeRecords.filter { $0.memberId == memberId }
                     .sorted { $0.earnedAt > $1.earnedAt }
    }

    /// 順位ベースの称号（友達の総人数で均等割り）
    func title(rank: Int, outOf total: Int) -> PointTitle {
        PointTitle(rank: rank, outOf: total)
    }

    // MARK: - 追加

    func add(questionId: UUID, memberId: UUID, questionText: String, elapsed: TimeInterval) {
        let tier = PointTier.tier(for: elapsed)
        let record = PointRecord(
            questionId:   questionId,
            memberId:     memberId,
            questionText: questionText,
            tier:         tier
        )
        records.append(record)
    }

    // MARK: - リセット

    func reset() {
        records = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - 永続化

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

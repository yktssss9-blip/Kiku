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

    // MARK: - 集計

    /// メンバーの合計ポイント
    func total(for memberId: UUID) -> Int {
        records.filter { $0.memberId == memberId }.reduce(0) { $0 + $1.points }
    }

    /// メンバーの獲得履歴（新しい順）
    func history(for memberId: UUID) -> [PointRecord] {
        records.filter { $0.memberId == memberId }
               .sorted { $0.earnedAt > $1.earnedAt }
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

    // MARK: - 永続化

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

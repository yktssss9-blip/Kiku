import SwiftUI

struct KikuGroup: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var memberIds: [UUID]
    var createdAt: Date = Date()
}

class GroupStore: ObservableObject {
    @Published var groups: [KikuGroup] = [] {
        didSet { save() }
    }

    private let key = "kiku.groups"

    /// グループ削除時に呼ばれるコールバック（削除された groupId を渡す）
    var onGroupDeleted: ((UUID) -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KikuGroup].self, from: data) {
            groups = decoded
        }
    }

    func create(name: String, memberIds: [UUID]) {
        groups.append(KikuGroup(name: name, memberIds: memberIds))
    }

    func update(id: UUID, name: String, memberIds: [UUID]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        groups[index].memberIds = memberIds
    }

    /// スワイプ削除用（IndexSet 版）
    func delete(at offsets: IndexSet) {
        let deletedIds = offsets.map { groups[$0].id }
        groups.remove(atOffsets: offsets)
        deletedIds.forEach { onGroupDeleted?($0) }
    }

    /// ID 指定削除（EditView の削除ボタン用）
    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        onGroupDeleted?(id)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

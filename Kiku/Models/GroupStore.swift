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

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KikuGroup].self, from: data) {
            groups = decoded
        }
    }

    func create(name: String, memberIds: [UUID]) {
        groups.append(KikuGroup(name: name, memberIds: memberIds))
    }

    func delete(at offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

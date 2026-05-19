import SwiftUI

struct Friend: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
}

class FriendStore: ObservableObject {
    @Published var friends: [Friend] = [] {
        didSet { save() }
    }

    private let key = "kiku.friends"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
            friends = decoded
        }
    }

    func add(_ friend: Friend) {
        friends.append(friend)
    }

    func delete(at offsets: IndexSet) {
        friends.remove(atOffsets: offsets)
    }

    func friend(for id: UUID) -> Friend? {
        friends.first { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

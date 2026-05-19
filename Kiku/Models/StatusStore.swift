import SwiftUI

struct KikuStatus: Codable {
    var text: String
    var emoji: String
    var postedAt: Date
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}

class StatusStore: ObservableObject {
    @Published var current: KikuStatus? {
        didSet { save() }
    }

    private let key = "kiku.status"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(KikuStatus.self, from: data) {
            current = decoded.isExpired ? nil : decoded
        }
    }

    func post(text: String, emoji: String) {
        let now = Date()
        current = KikuStatus(
            text: text,
            emoji: emoji,
            postedAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )
    }

    func clear() {
        current = nil
    }

    // 表示用：有効なステータスのみ返す
    var active: KikuStatus? {
        guard let s = current, !s.isExpired else { return nil }
        return s
    }

    private func save() {
        if let s = current, let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

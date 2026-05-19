import Foundation

struct SharedStore {
    static let suiteName = "group.com.kiku.app"

    static func saveAnswer(questionId: String, memberId: String, value: String) {
        let key = "answer.\(questionId).\(memberId)"
        UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
    }
}

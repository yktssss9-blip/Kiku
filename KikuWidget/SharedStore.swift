import Foundation

struct SharedStore {
    static let suiteName = "group.com.yukichi.kiku"

    static func saveAnswer(questionId: String, memberId: String, value: String) {
        let key = "answer.\(questionId).\(memberId)"
        UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
    }
}

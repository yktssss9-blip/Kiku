import Foundation

public struct SharedStore {
    public static let suiteName = "group.com.kiku.app"

    public static func saveAnswer(questionId: String, memberId: String, value: String) {
        let key = "answer.\(questionId).\(memberId)"
        UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
    }

    public static func popPendingAnswers() -> [(questionId: String, memberId: String, value: String)] {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [] }
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("answer.") }
        let results: [(String, String, String)] = keys.compactMap { key in
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 3, let value = defaults.string(forKey: key) else { return nil }
            return (parts[1], parts[2], value)
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        return results
    }
}

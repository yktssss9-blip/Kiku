import Foundation

final class ReviewManager: ObservableObject {
    @Published var showPrompt = false

    private let defaults = UserDefaults.standard
    private let sentCountKey  = "kiku.review.sentCount"
    private let lastPromptKey = "kiku.review.lastPromptDate"
    private let isDoneKey     = "kiku.review.isDone"

    private var sentCount: Int {
        get { defaults.integer(forKey: sentCountKey) }
        set { defaults.set(newValue, forKey: sentCountKey) }
    }

    var isDone: Bool {
        get { defaults.bool(forKey: isDoneKey) }
        set { defaults.set(newValue, forKey: isDoneKey) }
    }

    private var lastPromptDate: Date? {
        get { defaults.object(forKey: lastPromptKey) as? Date }
        set { defaults.set(newValue, forKey: lastPromptKey) }
    }

    private var canShow: Bool {
        guard !isDone, !showPrompt else { return false }
        if let last = lastPromptDate {
            return Date().timeIntervalSince(last) >= 30 * 24 * 3600
        }
        return true
    }

    // 質問を送信したときに呼ぶ。2回目の送信で表示トリガー
    func onQuestionSent() {
        sentCount += 1
        guard sentCount == 2, canShow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.triggerIfNeeded()
        }
    }

    // 質問に回答したときに呼ぶ（AnswerView が自動閉じる2秒後より後に表示するため3秒遅延）
    func onAnswered() {
        guard canShow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.triggerIfNeeded()
        }
    }

    private func triggerIfNeeded() {
        guard canShow else { return }
        lastPromptDate = Date()
        showPrompt = true
    }

    // 高評価後: 二度と表示しない
    func markDone() {
        isDone = true
        showPrompt = false
    }

    // 「後で」または低評価フィードバック送信後: 30日後に再表示
    func dismissPrompt() {
        showPrompt = false
    }
}

import SwiftUI
import UserNotifications

@main
struct KikuApp: App {
    @StateObject private var profileStore  = ProfileStore()
    @StateObject private var friendStore   = FriendStore()
    @StateObject private var groupStore    = GroupStore()
    @StateObject private var questionStore = QuestionStore()
    @StateObject private var statusStore   = StatusStore()
    @StateObject private var chatStore     = ChatStore()

    @State private var answerTarget: AnswerTarget? = nil

    var body: some Scene {
        WindowGroup {
            if profileStore.isSetupComplete {
                ContentView()
                    .environmentObject(profileStore)
                    .environmentObject(friendStore)
                    .environmentObject(groupStore)
                    .environmentObject(questionStore)
                    .environmentObject(statusStore)
                    .environmentObject(chatStore)
                    .onAppear {
                        requestNotificationPermission()
                        setupNotificationHandler()
                        setupChatUnlock()
                    }
                    .onOpenURL { url in
                        resolveAnswerTarget(from: url)
                    }
                    .sheet(item: $answerTarget) { target in
                        AnswerView(
                            question:    target.question,
                            memberId:    target.memberId,
                            memberName:  target.memberName,
                            memberEmoji: target.memberEmoji
                        )
                        .environmentObject(questionStore)
                    }
            } else {
                ProfileSetupView(store: profileStore)
            }
        }
    }

    // MARK: - URL スキーム処理（Live Activityボタン → AnswerView表示）

    private func resolveAnswerTarget(from url: URL) {
        guard url.scheme == "kiku", url.host == "answer" else { return }
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard
            let qIdStr = params?.first(where: { $0.name == "questionId" })?.value,
            let mIdStr = params?.first(where: { $0.name == "memberId"   })?.value,
            let questionId = UUID(uuidString: qIdStr),
            let memberId   = UUID(uuidString: mIdStr),
            let question   = questionStore.questions.first(where: { $0.id == questionId })
        else { return }

        let friend = friendStore.friends.first { $0.id == memberId }
        answerTarget = AnswerTarget(
            question:    question,
            memberId:    memberId,
            memberName:  friend?.name  ?? "メンバー",
            memberEmoji: friend?.emoji ?? "👤"
        )
    }

    // MARK: - 通知アクション処理（長押しボタン → 直接記録）

    private func setupNotificationHandler() {
        // 長押しボタン → 直接記録
        NotificationManager.shared.onAnswer = { questionId, memberId, value in
            DispatchQueue.main.async {
                questionStore.submit(questionId: questionId, memberId: memberId, value: value)
                Task {
                    if let q = questionStore.questions.first(where: { $0.id == questionId }) {
                        await ActivityManager.shared.update(
                            questionId: questionId,
                            summary:    q.summary()
                        )
                    }
                }
            }
        }

        // 通知本文タップ → AnswerView を開く
        NotificationManager.shared.onOpenAnswer = { questionId, memberId in
            guard let question = questionStore.questions.first(where: { $0.id == questionId }) else { return }
            let friend = friendStore.friends.first { $0.id == memberId }
            answerTarget = AnswerTarget(
                question:    question,
                memberId:    memberId,
                memberName:  friend?.name  ?? "メンバー",
                memberEmoji: friend?.emoji ?? "👤"
            )
        }
    }

    private func setupChatUnlock() {
        questionStore.onAnswered = { questionId, memberId, questionText in
            DispatchQueue.main.async {
                chatStore.unlock(
                    questionId:   questionId,
                    memberId:     memberId,
                    questionText: questionText
                )
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }
}

// MARK: - AnswerTarget

struct AnswerTarget: Identifiable {
    let id = UUID()
    let question: Question
    let memberId: UUID
    let memberName: String
    let memberEmoji: String
}

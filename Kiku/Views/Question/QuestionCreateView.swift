import SwiftUI

struct QuestionCreateView: View {
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText = ""

    var canSend: Bool {
        !questionText.trimmingCharacters(in: .whitespaces).isEmpty
        && questionText.count <= 50
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("質問文") {
                    TextField("例: 今夜ご飯食べる？", text: $questionText)
                        .autocorrectionDisabled()
                }

                Section("選択肢（固定）") {
                    Label("はい", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("いいえ", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("質問を作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("送信する") {
                        let text = questionText.trimmingCharacters(in: .whitespaces)
                        questionStore.send(text: text, to: group, friends: friendStore.friends)

                        // 各メンバーの Live Activity を自動起動
                        Task { @MainActor in
                            if let question = questionStore.questions.last {
                                for memberId in group.memberIds {
                                    let friend = friendStore.friends.first { $0.id == memberId }
                                    ActivityManager.shared.start(
                                        question:   question,
                                        memberId:   memberId,
                                        memberName: friend?.name ?? "メンバー"
                                    )
                                    // 複数起動の間隔を空ける
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                }
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSend)
                }
            }
        }
    }
}

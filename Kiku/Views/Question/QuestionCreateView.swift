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
                        questionStore.send(
                            text: questionText.trimmingCharacters(in: .whitespaces),
                            to: group,
                            friends: friendStore.friends
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSend)
                }
            }
        }
    }
}

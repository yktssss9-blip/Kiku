import SwiftUI

struct BroadcastQuestionView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var questionStore: QuestionStore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText = ""
    @State private var didSend = false

    var canSend: Bool {
        !questionText.trimmingCharacters(in: .whitespaces).isEmpty
        && questionText.count <= 50
        && !friendStore.friends.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.wave.2.fill")
                            .foregroundStyle(.blue)
                        Text("友達 \(friendStore.friends.count) 人全員に送信します")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("質問文") {
                    TextField("例: 今日空いてる人いる？", text: $questionText)
                        .autocorrectionDisabled()
                }

                Section("選択肢（固定）") {
                    Label("はい", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("いいえ", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }

                if friendStore.friends.isEmpty {
                    Section {
                        Text("友達タブから友達を追加してください")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("全体に送る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("送信する") {
                        questionStore.sendBroadcast(
                            text: questionText.trimmingCharacters(in: .whitespaces),
                            to: friendStore.friends
                        )
                        didSend = true
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSend)
                }
            }
            .alert("送信しました", isPresented: $didSend) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(friendStore.friends.count)人に「\(questionText)」を送信しました")
            }
        }
    }
}

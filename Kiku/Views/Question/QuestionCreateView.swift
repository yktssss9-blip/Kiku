import SwiftUI

struct QuestionCreateView: View {
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var questionText = ""
    @State private var memo = ""
    @State private var notifySelf = false

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

                Section {
                    TextField("例: 渋谷Bar K / 19時〜 / 3000円くらい", text: $memo, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled()
                } header: {
                    Text("メモ（任意）")
                } footer: {
                    Text("場所・時間など、メンバーが確認できるメモを残せます")
                }

                Section {
                    Toggle(isOn: $notifySelf) {
                        Label("自分にも送る", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("通知の動作確認用。自分のデバイスにも受信者として通知が届きます。")
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
                        let memoValue = memo.trimmingCharacters(in: .whitespaces)
                        questionStore.send(text: text, to: group, friends: friendStore.friends,
                                           memo: memoValue.isEmpty ? nil : memoValue,
                                           includeSelf: notifySelf)

                        // Live Activity を自動起動（自分宛て、またはローカルのみのメンバーの代理回答用。Firebase連携済みメンバーは本人の端末で起動されるべき）
                        Task { @MainActor in
                            if let question = questionStore.questions.last {
                                var memberIds = group.memberIds
                                if notifySelf, let selfId = questionStore.senderMemberId,
                                   !memberIds.contains(selfId) {
                                    memberIds.append(selfId)
                                }
                                for memberId in memberIds {
                                    let isSelf = memberId == questionStore.senderMemberId
                                    let name: String
                                    if isSelf {
                                        name = profileStore.name
                                    } else if let friend = friendStore.friends.first(where: { $0.id == memberId }),
                                              friend.firebaseUID.isEmpty {
                                        name = friend.name
                                    } else {
                                        continue
                                    }
                                    ActivityManager.shared.start(
                                        question:   question,
                                        memberId:   memberId,
                                        memberName: name
                                    )
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

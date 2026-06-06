import SwiftUI

struct InviteSetupView: View {
    @ObservedObject var store: ProfileStore

    private static let emojis = [
        "😊","😂","😎","🥳","🤩","😴","🤔","😅",
        "👻","🐱","🐶","🦊","🐺","🐻","🐼","🐨",
        "🎉","🔥","⚡️","🌈","🌟","💫","🎵","🎮"
    ]

    @State private var selectedEmoji = "😊"
    @State private var name = ""

    private var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 10
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("招待を受け取りました")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("名前と絵文字を設定してすぐ参加できます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 36)

            Text(selectedEmoji)
                .font(.system(size: 64))
                .padding(.bottom, 20)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8),
                spacing: 8
            ) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                selectedEmoji == emoji
                                    ? Color.blue.opacity(0.15)
                                    : Color(UIColor.secondarySystemBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedEmoji == emoji ? Color.blue : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 8) {
                Text("あなたの名前")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                TextField("例: ゆきち", text: $name)
                    .font(.body)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)

            Text(canProceed ? " " : "名前を入力してください（10文字以内）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            Spacer()

            Button {
                store.completeSetup(name: name, emoji: selectedEmoji)
            } label: {
                Text("参加する")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed ? Color.blue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canProceed)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    InviteSetupView(store: ProfileStore())
}

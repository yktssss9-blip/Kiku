import SwiftUI

private let emojiOptions: [String] = [
    "👤", "🧑", "👩", "👨", "👧", "👦", "👴", "👵",
    "🧒", "👶", "🧑‍🦱", "👩‍🦱", "🧑‍🦰", "👩‍🦰",
    "🧑‍🦳", "👩‍🦳", "🧑‍🦲", "👩‍🦲",
    "😀", "😎", "🥳", "🤓", "😺", "🐶", "🐱", "🐼",
    "🦊", "🐻", "🐸", "🐨", "🦁", "🐯"
]

struct ProfileSetupView: View {
    @ObservedObject var store: ProfileStore

    @State private var name = ""
    @State private var selectedEmoji = "👤"

    var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 10
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ヘッダー
            VStack(spacing: 12) {
                Text(selectedEmoji)
                    .font(.system(size: 80))
                    .padding(.bottom, 4)

                Text("きく")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("グループの「今どうする？」を\nワンタップで聞いてまとめる")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

            // 名前入力
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
            .padding(.bottom, 24)

            // 絵文字ピッカー
            VStack(alignment: .leading, spacing: 8) {
                Text("アイコンを選ぶ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 8),
                    spacing: 8
                ) {
                    ForEach(emojiOptions, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(
                                    selectedEmoji == emoji
                                        ? Color.blue.opacity(0.15)
                                        : Color(UIColor.secondarySystemBackground)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedEmoji == emoji ? Color.blue : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()

            // はじめるボタン
            Button {
                store.name  = name.trimmingCharacters(in: .whitespaces)
                store.emoji = selectedEmoji
            } label: {
                Text("はじめる")
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
    ProfileSetupView(store: ProfileStore())
}

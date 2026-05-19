import SwiftUI

private let statusEmojis: [String] = [
    "🍺", "🍻", "🍕", "🍜", "☕️",
    "📚", "💻", "🎮", "🎵", "🎬",
    "🏃", "💪", "😴", "🌙", "✈️",
    "🎉", "😎", "🤔", "😅", "🔥"
]

struct StatusPostView: View {
    @EnvironmentObject private var statusStore: StatusStore
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedEmoji = "🍺"

    var canPost: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && text.count <= 30
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // プレビュー
                previewCard
                    .padding(.top, 8)

                Form {
                    Section("ひとこと（30文字以内）") {
                        TextField("例: 飲み募集中！", text: $text)
                            .autocorrectionDisabled()
                    }

                    Section("絵文字") {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 5),
                            spacing: 12
                        ) {
                            ForEach(statusEmojis, id: \.self) { emoji in
                                Button {
                                    selectedEmoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            selectedEmoji == emoji
                                                ? Color.blue.opacity(0.15)
                                                : Color(UIColor.tertiarySystemBackground)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(selectedEmoji == emoji ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("ステータスを投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("投稿する") {
                        statusStore.post(
                            text: text.trimmingCharacters(in: .whitespaces),
                            emoji: selectedEmoji
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canPost)
                }
            }
        }
    }

    private var previewCard: some View {
        HStack(spacing: 12) {
            Text(profileStore.emoji)
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text(profileStore.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(selectedEmoji)
                    Text(text.isEmpty ? "ここに表示されます" : text)
                        .font(.subheadline)
                        .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                }
            }
            Spacer()
            Text("24h")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

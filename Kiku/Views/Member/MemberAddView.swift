import SwiftUI

private let emojiOptions: [String] = [
    "👤", "🧑", "👩", "👨", "👧", "👦", "👴", "👵",
    "🧒", "👶", "🧑‍🦱", "👩‍🦱", "🧑‍🦰", "👩‍🦰",
    "🧑‍🦳", "👩‍🦳", "🧑‍🦲", "👩‍🦲",
    "😀", "😎", "🥳", "🤓", "😺", "🐶", "🐱", "🐼",
    "🦊", "🐻", "🐸", "🐨", "🦁", "🐯"
]

struct MemberAddView: View {
    var onAdd: (Friend) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedEmoji = "👤"

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: お母さん、田中さん", text: $name)
                        .autocorrectionDisabled()
                }

                Section("アイコン") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        selectedEmoji == emoji
                                            ? Color.blue.opacity(0.2)
                                            : Color.clear
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
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("友達を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加する") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        onAdd(Friend(name: trimmed, emoji: selectedEmoji))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.count > 10)
                }
            }
        }
    }
}

#Preview {
    MemberAddView { _ in }
}

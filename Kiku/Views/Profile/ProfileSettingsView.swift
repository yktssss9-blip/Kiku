import SwiftUI
import PhotosUI

private let emojiOptions: [String] = [
    "👤", "🧑", "👩", "👨", "👧", "👦", "👴", "👵",
    "🧒", "👶", "🧑‍🦱", "👩‍🦱", "🧑‍🦰", "👩‍🦰",
    "🧑‍🦳", "👩‍🦳", "🧑‍🦲", "👩‍🦲",
    "😀", "😎", "🥳", "🤓", "😺", "🐶", "🐱", "🐼",
    "🦊", "🐻", "🐸", "🐨", "🦁", "🐯"
]

struct ProfileSettingsView: View {
    @EnvironmentObject private var store:      ProfileStore
    @EnvironmentObject private var pointStore: PointStore
    @Environment(\.dismiss) private var dismiss

    @State private var name        = ""
    @State private var selectedEmoji = "👤"
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var showDeletePhotoConfirm = false
    @State private var showSavedToast = false

    var hasChanges: Bool {
        name != store.name
        || selectedEmoji != store.emoji
        || selectedImage != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // プロフィール画像
                Section {
                    HStack {
                        Spacer()
                        photoSection
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // シゴできポイント集計
                Section {
                    pointsSummaryRow
                }

                // 名前
                Section("名前") {
                    TextField("例: ゆきち", text: $name)
                        .autocorrectionDisabled()
                }

                // 絵文字（写真がない場合のアイコン）
                Section("絵文字アイコン（写真がないときに使用）") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 7),
                        spacing: 10
                    ) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
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
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name          = store.name
                selectedEmoji = store.emoji
            }
            .onChange(of: photoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                    }
                }
            }
            .overlay(savedToast, alignment: .bottom)
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(spacing: 12) {
            // アバター表示
            ZStack(alignment: .bottomTrailing) {
                avatarView
                    .frame(width: 100, height: 100)

                // カメラアイコン（変更ボタン）
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .offset(x: 4, y: 4)
            }

            // 写真削除ボタン
            if store.photoData != nil || selectedImage != nil {
                Button(role: .destructive) {
                    showDeletePhotoConfirm = true
                } label: {
                    Label("写真を削除", systemImage: "trash")
                        .font(.caption)
                }
                .confirmationDialog("写真を削除しますか？", isPresented: $showDeletePhotoConfirm) {
                    Button("削除する", role: .destructive) {
                        selectedImage = nil
                        store.photoData = nil
                    }
                    Button("キャンセル", role: .cancel) {}
                }
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let img = selectedImage {
                // 新しく選択した画像
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 3))
                    .shadow(radius: 4)
            } else if let profileImage = store.profileImage {
                // 既存の保存済み画像
                profileImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 3))
                    .shadow(radius: 4)
            } else {
                // 絵文字フォールバック
                Text(selectedEmoji)
                    .font(.system(size: 52))
                    .frame(width: 100, height: 100)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 3))
                    .shadow(radius: 4)
            }
        }
    }

    // MARK: - Save Toast

    private var savedToast: some View {
        Group {
            if showSavedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("保存しました")
                }
                .font(.subheadline).fontWeight(.semibold)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(radius: 8)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Points Summary

    private var totalPoints: Int {
        pointStore.records.reduce(0) { $0 + $1.points }
    }

    private var pointsSummaryRow: some View {
        NavigationLink {
            pointsHistoryView
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("シゴできポイント（累計）")
                        .font(.subheadline)
                    Text("友達が獲得した合計ポイント")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("🏆")
                    Text("\(totalPoints)pt")
                        .fontWeight(.bold)
                        .foregroundStyle(totalPoints > 0 ? .primary : .secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private var pointsHistoryView: some View {
        List {
            if pointStore.records.isEmpty {
                ContentUnavailableView(
                    "まだ記録がありません",
                    systemImage: "trophy",
                    description: Text("質問に回答すると\nポイントが記録されます")
                )
            } else {
                ForEach(pointStore.records.sorted { $0.earnedAt > $1.earnedAt }) { record in
                    HStack {
                        Text(record.tier.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Text(record.questionText)
                            .font(.body)
                            .lineLimit(1)
                        Spacer()
                        Text("+\(record.points)pt")
                            .fontWeight(.semibold)
                            .foregroundStyle(historyTierColor(record.tier))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("ポイント履歴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyTierColor(_ tier: PointTier) -> Color {
        switch tier {
        case .fast:   return .orange
        case .normal: return .blue
        case .late:   return .secondary
        }
    }

    // MARK: - Save

    private func saveChanges() {
        store.name  = name.trimmingCharacters(in: .whitespaces)
        store.emoji = selectedEmoji

        if let img = selectedImage,
           let data = img.jpegData(compressionQuality: 0.7) {
            store.photoData = data
        }

        withAnimation(.spring()) { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSavedToast = false }
            dismiss()
        }
    }
}

#Preview {
    ProfileSettingsView()
        .environmentObject(ProfileStore())
        .environmentObject(PointStore())
}

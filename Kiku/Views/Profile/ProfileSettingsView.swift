import SwiftUI
import PhotosUI

private let emojiOptions: [String] = [
    "👤", "🧑", "👩", "👨", "👧", "👦", "👴", "👵",
    "🧒", "👶", "🧑‍🦱", "👩‍🦱", "🧑‍🦰", "👩‍🦰",
    "🧑‍🦳", "👩‍🦳", "🧑‍🦲", "👩‍🦲",
    "😀", "😎", "🥳", "🤓", "😺", "🐶", "🐱", "🐼",
    "🦊", "🐻", "🐸", "🐨", "🦁", "🐯"
]

private enum IconType: String, CaseIterable {
    case emoji = "絵文字"
    case photo = "写真"

    init(_ mode: IconMode) {
        self = mode == .photo ? .photo : .emoji
    }

    var iconMode: IconMode {
        self == .photo ? .photo : .emoji
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name              = ""
    @State private var selectedEmoji     = "👤"
    @State private var iconType          = IconType.emoji
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage?      = nil
    @State private var showDeletePhotoConfirm       = false
    @State private var showSavedToast               = false
    @State private var activeHourStart   = 9
    @State private var activeHourEnd     = 12

    var hasChanges: Bool {
        name != store.name
        || selectedEmoji != store.emoji
        || selectedImage != nil
        || (iconType == .emoji && store.photoData != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                // アバター + アイコン種別セレクター
                Section {
                    VStack(spacing: 16) {
                        avatarView
                            .frame(width: 100, height: 100)

                        Picker("", selection: $iconType) {
                            ForEach(IconType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)

                        Text("どちらか一方のみ有効になります")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)

                // 返信しやすい時間帯
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ProfileStore.activeHourPresets, id: \.start) { preset in
                                let isSelected = preset.start == activeHourStart
                                Button {
                                    activeHourStart = preset.start
                                    activeHourEnd   = preset.end
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(preset.emoji).font(.title3)
                                        Text(preset.label)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isSelected ? .blue : .primary)
                                        Text("\(preset.start)〜\(preset.end == 24 ? 0 : preset.end)時")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 72)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.blue.opacity(0.12) : Color(UIColor.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                } header: {
                    Text("返信しやすい時間帯")
                } footer: {
                    Text("友達があなたへの質問を送るベストタイムをインサイトで確認できます")
                }

                // 名前
                Section("名前") {
                    TextField("例: ゆきち", text: $name)
                        .autocorrectionDisabled()
                }

                // 絵文字モード
                if iconType == .emoji {
                    Section("絵文字アイコンを選ぶ") {
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

                // 写真モード
                if iconType == .photo {
                    Section("プロフィール写真") {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Label("写真を選ぶ", systemImage: "photo.on.rectangle")
                                        .font(.subheadline)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

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
                                            // 写真がなくなったら絵文字モードへ切り替え
                                            iconType = .emoji
                                        }
                                        Button("キャンセル", role: .cancel) {}
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
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
                name            = store.name
                selectedEmoji   = store.emoji
                iconType        = IconType(store.iconMode)
                activeHourStart = store.activeHourStart
                activeHourEnd   = store.activeHourEnd
            }
            .onChange(of: photoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                    }
                }
            }
            .onChange(of: iconType) { newType in
                // 絵文字に切り替えたとき、選択中の新規写真をリセット
                if newType == .emoji {
                    selectedImage = nil
                    photoItem     = nil
                }
            }
            .overlay(savedToast, alignment: .bottom)
        }
    }

    // MARK: - Avatar View

    private var avatarView: some View {
        Group {
            if iconType == .photo {
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 3))
                        .shadow(radius: 4)
                } else if let profileImage = store.profileImage {
                    profileImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 3))
                        .shadow(radius: 4)
                } else {
                    // 写真モードだがまだ未選択
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(width: 100, height: 100)
                            .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 3))
                            .shadow(radius: 4)
                        Image(systemName: "camera")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // 絵文字モード
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

    // MARK: - Save

    private func saveChanges() {
        store.name            = name.trimmingCharacters(in: .whitespaces)
        store.activeHourStart = activeHourStart
        store.activeHourEnd   = activeHourEnd

        switch iconType {
        case .emoji:
            // 絵文字を有効化 → 写真データを破棄して排他を保証
            store.emoji     = selectedEmoji
            store.photoData = nil
            store.iconMode  = .emoji

        case .photo:
            // 写真を有効化 → 新規選択があれば保存、なければ既存を維持
            if let img = selectedImage,
               let data = img.jpegData(compressionQuality: 0.7) {
                store.photoData = data
            }
            // 写真モードに切り替えたが写真がない場合は絵文字にフォールバック
            store.iconMode = store.photoData != nil ? .photo : .emoji
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
}

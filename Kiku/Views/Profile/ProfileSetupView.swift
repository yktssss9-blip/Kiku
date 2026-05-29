import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @ObservedObject var store: ProfileStore

    @State private var name             = ""
    @State private var username         = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedData: Data?             = nil
    @State private var isSubmitting     = false
    @State private var errorMessage     = ""
    @State private var activeHourStart  = 9
    @State private var activeHourEnd    = 12

    var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && name.count <= 10
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && username.count <= 20
            && selectedData != nil
            && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── ヘッダー ──
            VStack(spacing: 12) {
                Text("きく")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("グループの「今どうする？」を\nワンタップで聞いてまとめる")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

            // ── 写真ピッカー ──
            PhotosPicker(selection: $selectedItem, matching: .images) {
                ZStack {
                    if let data = selectedData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                    } else {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 100, height: 100)
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("写真を選ぶ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if selectedData != nil {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .background(Color.white.clipShape(Circle()))
                            .offset(x: 34, y: 34)
                    }
                }
                .frame(width: 100, height: 100)
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        selectedData = data
                    }
                }
            }
            .padding(.bottom, 32)

            // ── 名前入力 ──
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
            .padding(.bottom, 12)

            // ── ユーザー名入力 ──
            VStack(alignment: .leading, spacing: 8) {
                Text("ユーザー名（友達検索に使います）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                HStack {
                    Text("@")
                        .foregroundStyle(.secondary)
                    TextField("例: yukichi", text: $username)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                .font(.body)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // ── 返信しやすい時間帯 ──
            VStack(alignment: .leading, spacing: 10) {
                Text("返信しやすい時間帯")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)

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
                                .background(isSelected ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 8)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            } else {
                Text("名前・ユーザー名・写真を設定してください")
                    .font(.caption)
                    .foregroundStyle(canProceed ? .clear : .secondary)
                    .padding(.bottom, 8)
            }

            Spacer()

            // ── はじめるボタン ──
            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("はじめる")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canProceed ? Color.blue : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .disabled(!canProceed)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = ""
        defer { isSubmitting = false }

        // ユーザー名をFirestoreに登録（一意性チェック込み）
        if let error = await store.setUsername(username) {
            errorMessage = error
            return
        }

        store.name            = name.trimmingCharacters(in: .whitespaces)
        store.photoData       = selectedData
        store.iconMode        = .photo
        store.emoji           = "👤"
        store.activeHourStart = activeHourStart
        store.activeHourEnd   = activeHourEnd
    }
}

#Preview {
    ProfileSetupView(store: ProfileStore())
}

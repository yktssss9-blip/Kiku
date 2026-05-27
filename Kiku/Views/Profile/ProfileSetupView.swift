import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @ObservedObject var store: ProfileStore

    @State private var name             = ""
    @State private var selectedItem:    PhotosPickerItem? = nil
    @State private var selectedData:    Data?             = nil

    var canProceed: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && name.count <= 10
            && selectedData != nil
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

                    // 選択済みのときは右下に編集バッジ
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
            .padding(.bottom, 8)

            Text("名前と写真を設定してください")
                .font(.caption)
                .foregroundStyle(canProceed ? .clear : .secondary)
                .padding(.bottom, 16)

            Spacer()

            // ── はじめるボタン ──
            Button {
                store.name      = name.trimmingCharacters(in: .whitespaces)
                store.photoData = selectedData
                store.iconMode  = .photo
                store.emoji     = "👤"   // フォールバック用
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

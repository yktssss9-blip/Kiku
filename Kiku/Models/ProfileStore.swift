import SwiftUI

// MARK: - Icon Mode

enum IconMode: String {
    case emoji = "emoji"
    case photo = "photo"
}

class ProfileStore: ObservableObject {
    private static let appGroup = UserDefaults(suiteName: "group.com.yukichi.kiku")

    @Published var name: String {
        didSet {
            UserDefaults.standard.set(name, forKey: "kiku.profile.name")
            Self.appGroup?.set(name, forKey: "kiku.profile.name")
        }
    }
    @Published var emoji: String {
        didSet {
            UserDefaults.standard.set(emoji, forKey: "kiku.profile.emoji")
            Self.appGroup?.set(emoji, forKey: "kiku.profile.emoji")
        }
    }
    @Published var photoData: Data? {
        didSet {
            UserDefaults.standard.set(photoData, forKey: "kiku.profile.photo")
            Self.appGroup?.set(photoData, forKey: "kiku.profile.photo")
        }
    }
    /// 有効なアイコン種別（画像 or 絵文字）。写真と絵文字は排他。
    @Published var iconMode: IconMode {
        didSet {
            UserDefaults.standard.set(iconMode.rawValue, forKey: "kiku.profile.iconMode")
            Self.appGroup?.set(iconMode.rawValue, forKey: "kiku.profile.iconMode")
        }
    }

    /// 自分を識別する固定 UUID（初回起動時に生成・永続化）
    let myId: UUID

    /// プロフィール画像（iconMode == .photo のときのみ返す）
    var profileImage: Image? {
        guard iconMode == .photo,
              let data = photoData,
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    var isSetupComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        self.name      = UserDefaults.standard.string(forKey: "kiku.profile.name")  ?? ""
        self.emoji     = UserDefaults.standard.string(forKey: "kiku.profile.emoji") ?? "👤"
        self.photoData = UserDefaults.standard.data(forKey: "kiku.profile.photo")

        // iconMode: 保存値を優先、なければ photoData の有無から推定
        let savedMode  = UserDefaults.standard.string(forKey: "kiku.profile.iconMode") ?? ""
        let hasPhoto   = UserDefaults.standard.data(forKey: "kiku.profile.photo") != nil
        self.iconMode  = IconMode(rawValue: savedMode) ?? (hasPhoto ? .photo : .emoji)

        // myId: 初回生成して永続化、以降は同じ値を使い続ける
        if let saved = UserDefaults.standard.string(forKey: "kiku.profile.myId"),
           let uuid = UUID(uuidString: saved) {
            self.myId = uuid
        } else {
            let newId = UUID()
            UserDefaults.standard.set(newId.uuidString, forKey: "kiku.profile.myId")
            self.myId = newId
        }

        // 起動時に App Group へ同期（通知拡張から参照するため）
        let appGroup = Self.appGroup
        appGroup?.set(self.name,             forKey: "kiku.profile.name")
        appGroup?.set(self.emoji,            forKey: "kiku.profile.emoji")
        appGroup?.set(self.iconMode.rawValue, forKey: "kiku.profile.iconMode")
        appGroup?.set(self.photoData,        forKey: "kiku.profile.photo")
    }

    func reset() {
        name      = ""
        emoji     = "👤"
        photoData = nil
    }
}

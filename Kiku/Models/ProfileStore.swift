import SwiftUI

class ProfileStore: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "kiku.profile.name") }
    }
    @Published var emoji: String {
        didSet { UserDefaults.standard.set(emoji, forKey: "kiku.profile.emoji") }
    }
    @Published var photoData: Data? {
        didSet { UserDefaults.standard.set(photoData, forKey: "kiku.profile.photo") }
    }

    /// プロフィール画像（写真 > 絵文字 の優先順位）
    var profileImage: Image? {
        guard let data = photoData,
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
    }

    func reset() {
        name      = ""
        emoji     = "👤"
        photoData = nil
    }
}

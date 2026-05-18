import SwiftUI

class ProfileStore: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "kiku.profile.name") }
    }
    @Published var emoji: String {
        didSet { UserDefaults.standard.set(emoji, forKey: "kiku.profile.emoji") }
    }

    var isSetupComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        self.name  = UserDefaults.standard.string(forKey: "kiku.profile.name")  ?? ""
        self.emoji = UserDefaults.standard.string(forKey: "kiku.profile.emoji") ?? "👤"
    }

    func reset() {
        name  = ""
        emoji = "👤"
    }
}

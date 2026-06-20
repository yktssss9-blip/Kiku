import SwiftUI
import CryptoKit

// MARK: - Image Cache

private final class ImageCacheService {
    static let shared = ImageCacheService()
    private let cache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    private init() {
        cache.countLimit = 100
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = caches.appendingPathComponent("avatar_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func image(for key: String) -> UIImage? {
        if let mem = cache.object(forKey: key as NSString) { return mem }
        let path = diskPath(for: key)
        guard let data = try? Data(contentsOf: path),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key as NSString)
        return img
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
        let path = diskPath(for: key)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: path, options: .atomic)
        }
    }

    private func diskPath(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
        let name = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheURL.appendingPathComponent(name)
    }
}

// MARK: - UserAvatarView

struct UserAvatarView: View {
    let emoji: String
    let photoURL: String?
    var size: CGFloat = 36

    @State private var loadedImage: UIImage?

    init(emoji: String, photoURL: String?, size: CGFloat = 36) {
        self.emoji = emoji
        self.photoURL = photoURL
        self.size = size
        // キャッシュ命中時は初期値として設定し、遷移アニメーション中のフラッシュを防ぐ
        if let urlString = photoURL, !urlString.isEmpty {
            _loadedImage = State(initialValue: ImageCacheService.shared.image(for: urlString))
        } else {
            _loadedImage = State(initialValue: nil)
        }
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                emojiCircle
            }
        }
        .frame(width: size, height: size)
        .task(id: photoURL) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let urlString = photoURL, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            loadedImage = nil
            return
        }

        if let cached = ImageCacheService.shared.image(for: urlString) {
            loadedImage = cached
            return
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }

        ImageCacheService.shared.store(image, for: urlString)
        loadedImage = image
    }

    private var emojiCircle: some View {
        Text(emoji.isEmpty ? "👤" : emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(Circle())
    }
}

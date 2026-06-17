import SwiftUI

// MARK: - Image Cache

private final class ImageCacheService {
    static let shared = ImageCacheService()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
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

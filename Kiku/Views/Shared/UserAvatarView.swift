import SwiftUI

struct UserAvatarView: View {
    let emoji: String
    let photoURL: String?
    var size: CGFloat = 36

    var body: some View {
        if let urlString = photoURL,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                default:
                    emojiCircle
                }
            }
            .frame(width: size, height: size)
        } else {
            emojiCircle
        }
    }

    private var emojiCircle: some View {
        Text(emoji.isEmpty ? "👤" : emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(Circle())
    }
}

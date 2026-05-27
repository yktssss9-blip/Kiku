import UIKit
import UserNotifications
import UserNotificationsUI
import SwiftUI

// MARK: - Extension Entry Point

class NotificationViewController: UIViewController, UNNotificationContentExtension {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func didReceive(_ notification: UNNotification) {
        let content  = notification.request.content
        let userInfo = content.userInfo

        let questionText   = content.body
        let senderName     = userInfo["senderName"]     as? String ?? ""
        let senderEmoji    = userInfo["senderEmoji"]    as? String ?? "👤"
        let senderIconMode = userInfo["senderIconMode"] as? String ?? "emoji"
        let categoryId     = content.categoryIdentifier
        let hasTime        = categoryId.contains("time")

        let sentAt: Date
        if let ts = userInfo["sentAt"] as? TimeInterval {
            sentAt = Date(timeIntervalSince1970: ts)
        } else {
            sentAt = notification.date
        }

        // 送信者の写真を App Group から読み込む（photo モード時のみ）
        var senderPhoto: UIImage? = nil
        if senderIconMode == "photo",
           let data = UserDefaults(suiteName: "group.com.yukichi.kiku")?.data(forKey: "kiku.profile.photo") {
            senderPhoto = UIImage(data: data)
        }

        let elapsed = Date().timeIntervalSince(sentAt)
        let (pointLabel, pointColorKey): (String, String)
        if hasTime {
            pointLabel    = "🕐 時刻を回答してください"
            pointColorKey = "secondary"
        } else if elapsed < 60 {
            pointLabel    = "⚡️ 今なら +20pt"
            pointColorKey = "green"
        } else if elapsed < 180 {
            pointLabel    = "🕐 +10pt"
            pointColorKey = "orange"
        } else {
            pointLabel    = "+2pt"
            pointColorKey = "red"
        }

        let contentView = NotificationContentView(
            senderName:     senderName,
            senderEmoji:    senderEmoji,
            senderPhoto:    senderPhoto.map { Image(uiImage: $0) },
            usePhoto:       senderIconMode == "photo" && senderPhoto != nil,
            questionText:   questionText,
            pointLabel:     pointLabel,
            pointColorKey:  pointColorKey
        )

        let host = UIHostingController(rootView: contentView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

// MARK: - SwiftUI View

struct NotificationContentView: View {
    let senderName:    String
    let senderEmoji:   String
    let senderPhoto:   Image?
    let usePhoto:      Bool
    let questionText:  String
    let pointLabel:    String
    let pointColorKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            VStack(alignment: .leading, spacing: 6) {
                // 送信者名
                Text("\(senderName)さんから")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // 質問文（大きく）
                Text(questionText)
                    .font(.title3).fontWeight(.bold)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // ポイントヒント / 時刻案内
                Text(pointLabel)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(pointColor)
            }

            Spacer(minLength: 4)

            // 送信者アバター
            senderAvatar
                .frame(width: 52, height: 52)
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var senderAvatar: some View {
        if usePhoto, let photo = senderPhoto {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            Text(senderEmoji)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }

    private var pointColor: Color {
        switch pointColorKey {
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        default:       return .secondary
        }
    }
}

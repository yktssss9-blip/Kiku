import SwiftUI

// MARK: - 受信した申請カード（承認 ○ / 辞退 ✕）

struct ReceivedFriendRequestCard: View {
    let request: FriendRequest

    @EnvironmentObject private var friendStore: FriendStore

    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // アバター
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: 40, height: 40)
                    Text(request.fromEmoji)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.fromName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("@\(request.fromUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isProcessing {
                    ProgressView().scaleEffect(0.8)
                } else {
                    HStack(spacing: 8) {
                        // 承認: ○
                        Button {
                            respond(accept: true)
                        } label: {
                            Text("○")
                                .font(.title2).fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 36)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        // 辞退: ✕
                        Button {
                            respond(accept: false)
                        } label: {
                            Text("✕")
                                .font(.title2).fontWeight(.bold)
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 36)
                                .background(Color(UIColor.systemGray4))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func respond(accept: Bool) {
        isProcessing = true
        Task {
            if accept {
                await friendStore.acceptFriendRequest(
                    requestId:    request.id,
                    fromUID:      request.fromUID,
                    fromName:     request.fromName,
                    fromEmoji:    request.fromEmoji,
                    fromPhotoURL: request.fromPhotoURL,
                    fromUsername: request.fromUsername
                )
            } else {
                await friendStore.declineFriendRequest(requestId: request.id)
            }
            await ActivityManager.shared.endFriendRequest(requestId: request.id)
            await MainActor.run { isProcessing = false }
        }
    }
}

// MARK: - 送信した申請カード（ステータス表示）

struct SentFriendRequestCard: View {
    let request: SentFriendRequest

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 40, height: 40)
                Text(request.toEmoji)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(request.toName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("@\(request.toUsername)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch request.status {
        case "accepted":
            Label("承認済み", systemImage: "checkmark.circle.fill")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        case "declined":
            Label("辞退", systemImage: "xmark.circle.fill")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(UIColor.systemGray5))
                .clipShape(Capsule())
        default:
            Label("申請中", systemImage: "clock.fill")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

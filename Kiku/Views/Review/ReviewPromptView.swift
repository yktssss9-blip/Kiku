import SwiftUI
import StoreKit

struct ReviewPromptView: View {
    @EnvironmentObject private var reviewManager: ReviewManager
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var hoveredStar = 0
    @State private var feedbackText = ""
    @State private var phase: Phase = .rating
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showMailCompose = false

    private enum Phase { case rating, positive, negative }

    private let feedbackEmail = "sykt.feedback@gmail.com"

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("後で") {
                            reviewManager.dismissPrompt()
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showMailCompose) {
            MailComposeView(
                recipient: feedbackEmail,
                subject: "【Kiku】ご意見・ご要望",
                body: feedbackText
            ) {
                showMailCompose = false
                reviewManager.dismissPrompt()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .rating:   ratingView
        case .positive: positiveView
        case .negative: negativeView
        }
    }

    // MARK: - Rating (初期画面)

    private var ratingView: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 8) {
                Text("Kikuはどうですか？")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("ご利用の評価をお聞かせください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        if n >= 4 {
                            requestReview()
                            reviewManager.markDone()
                            withAnimation(.spring(response: 0.35)) { phase = .positive }
                        } else {
                            selectedDetent = .large
                            withAnimation(.spring(response: 0.35)) { phase = .negative }
                        }
                    } label: {
                        Text(n <= hoveredStar ? "★" : "☆")
                            .font(.system(size: 44))
                            .foregroundStyle(n <= hoveredStar ? .orange : Color.secondary.opacity(0.35))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredStar = $0 ? n : 0 }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Positive (4〜5星)

    private var positiveView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("ありがとうございます！")
                .font(.title2)
                .fontWeight(.bold)
            Text("レビューを書いていただけると\nとても励みになります")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = AppConstants.appStoreReviewURL {
                Button {
                    openURL(url)
                    reviewManager.dismissPrompt()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                        Text("App Store でレビューを書く")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Text("App Store でレビューを書いてください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("閉じる") {
                reviewManager.dismissPrompt()
                dismiss()
            }
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Negative (1〜3星)

    private var negativeView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("ご意見をお聞かせください")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("改善のために貴重なご意見を\nお聞かせください")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                TextField("ご意見・ご要望を入力してください", text: $feedbackText, axis: .vertical)
                    .lineLimit(4...10)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Button {
                    sendFeedback()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                        Text("送信する")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        feedbackText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.secondary
                            : Color.blue
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("キャンセル") {
                    reviewManager.dismissPrompt()
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Helpers

    private func sendFeedback() {
        if MailComposeView.canSendMail {
            showMailCompose = true
        } else {
            sendViaMailtoURL()
        }
    }

    private func sendViaMailtoURL() {
        let subject = "【Kiku】ご意見・ご要望"
        guard
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let encodedBody    = feedbackText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "mailto:\(feedbackEmail)?subject=\(encodedSubject)&body=\(encodedBody)")
        else { return }
        openURL(url)
        reviewManager.dismissPrompt()
        dismiss()
    }
}

#Preview {
    ReviewPromptView()
        .environmentObject(ReviewManager())
}

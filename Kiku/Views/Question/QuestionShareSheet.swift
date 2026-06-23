import SwiftUI
import CoreImage.CIFilterBuiltins

struct QuestionShareSheet: View {
    let question: Question
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var inviteURL: String {
        "https://shigodeki-8e49a.web.app/q/\(question.id.uuidString)?token=\(question.inviteToken)"
    }

    private var qrImage: UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(inviteURL.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return UIImage() }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 10) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

                        Text("カメラで読み取って回答")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(spacing: 14) {
                        Text(inviteURL)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        actionButton(
                            title: copied ? "コピーしました！" : "リンクをコピー",
                            icon:  copied ? "checkmark.circle.fill" : "doc.on.doc",
                            color: copied ? .green : .blue
                        ) {
                            UIPasteboard.general.string = inviteURL
                            withAnimation { copied = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await MainActor.run { withAnimation { copied = false } }
                            }
                        }

                        actionButton(
                            title: "LINEで送る",
                            icon:  "paperplane.fill",
                            color: Color(red: 0.04, green: 0.78, blue: 0.35)
                        ) {
                            sendViaLine()
                        }

                        ShareLink(
                            item: URL(string: inviteURL)!,
                            subject: Text("Kiku - 回答リクエスト"),
                            message: Text("「\(question.text)」に回答してください！")
                        ) {
                            Label("その他で共有", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: 280)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("招待する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: 280)
                .padding(.vertical, 12)
                .background(color)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }

    private func sendViaLine() {
        let text = "「\(question.text)」に回答してください！\n\(inviteURL)"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://line.me/R/msg/text/\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}

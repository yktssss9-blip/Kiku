import SwiftUI

struct ReportSheet: View {
    let contentType: String
    let contentId: String
    let contentText: String
    var onDismiss: () -> Void = {}

    @State private var selectedReason: ReportReason? = nil
    @State private var detail = ""
    @State private var isSending = false
    @State private var didSend = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if didSend {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.green)
                            Text("通報を送信しました")
                                .font(.headline)
                            Text("ご報告ありがとうございます。内容を確認いたします。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section {
                        Text(contentText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } header: {
                        Text("対象コンテンツ")
                    }

                    Section {
                        ForEach(ReportReason.allCases) { reason in
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack {
                                    Text(reason.rawValue)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedReason == reason {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("通報理由")
                    }

                    Section {
                        TextField("詳細（任意）", text: $detail, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text("補足")
                    }
                }
            }
            .navigationTitle("コンテンツを通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                        onDismiss()
                    }
                }
                if !didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("送信") {
                            sendReport()
                        }
                        .disabled(selectedReason == nil || isSending)
                    }
                }
            }
        }
    }

    private func sendReport() {
        guard let reason = selectedReason else { return }
        isSending = true
        Task {
            try? await ReportStore.shared.send(
                contentType: contentType,
                contentId: contentId,
                contentText: contentText,
                reason: reason,
                detail: detail
            )
            await MainActor.run {
                withAnimation { didSend = true }
                isSending = false
            }
        }
    }
}

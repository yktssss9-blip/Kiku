import Foundation
import FirebaseAuth
import FirebaseFirestore

enum ReportReason: String, CaseIterable, Identifiable {
    case spam       = "スパム・迷惑行為"
    case harassment = "嫌がらせ・いじめ"
    case hateSpeech = "差別的・攻撃的な内容"
    case other      = "その他"

    var id: String { rawValue }
}

final class ReportStore {
    static let shared = ReportStore()
    private let db = Firestore.firestore()

    func send(
        contentType: String,
        contentId: String,
        contentText: String,
        reason: ReportReason,
        detail: String = ""
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "reporterUID": uid,
            "contentType": contentType,
            "contentId": contentId,
            "contentText": String(contentText.prefix(500)),
            "reason": reason.rawValue,
            "detail": String(detail.prefix(1000)),
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("reports").addDocument(data: data)
    }
}

import Foundation

enum AppConstants {
    // TODO: App Store 公開後に実際の ID に差し替えること（AnswerView.swift の定数も同時に削除する）
    static let appStoreID = ""

    static var appStoreReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

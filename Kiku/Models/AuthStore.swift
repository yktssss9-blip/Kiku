import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

class AuthStore: ObservableObject {
    @Published var user: User? = nil
    @Published var isLoading = true
    @Published var errorMessage: String? = nil
    @Published var appleDisplayName: String = ""

    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isLoading = false
            }
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    var userId: String? { user?.uid }

    // MARK: - Apple Sign In

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let nonce = currentNonce,
                let idTokenData = credential.identityToken,
                let idToken = String(data: idTokenData, encoding: .utf8)
            else {
                errorMessage = "認証情報の取得に失敗しました"
                return
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { appleDisplayName = parts.joined(separator: " ") }
            Task { @MainActor in await signInOrLink(with: firebaseCredential) }

        case .failure(let error):
            let code = (error as NSError).code
            if code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "サインインに失敗しました"
            }
        }
    }

    private func signInOrLink(with credential: AuthCredential) async {
        do {
            if let current = Auth.auth().currentUser, current.isAnonymous {
                try await current.link(with: credential)
            } else {
                try await Auth.auth().signIn(with: credential)
            }
            errorMessage = nil
        } catch let err as NSError {
            if err.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
               let updated = err.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                try? await Auth.auth().signIn(with: updated)
            } else {
                errorMessage = "サインインに失敗しました"
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: - Delete Account

    /// アカウントとすべての関連データを削除する。成功時は nil、失敗時はエラーメッセージを返す。
    func deleteAccount() async -> String? {
        guard let user = Auth.auth().currentUser else { return "ユーザーが見つかりません" }
        let uid = user.uid
        let db  = Firestore.firestore()

        do {
            // ユーザー名の予約を解放
            let userDoc = try? await db.collection("users").document(uid).getDocument()
            if let username = userDoc?.data()?["username"] as? String, !username.isEmpty {
                try? await db.collection("usernames").document(username).delete()
            }

            // 自分が作成した質問を削除
            let questions = try await db.collection("questions")
                .whereField("createdBy", isEqualTo: uid).getDocuments()
            for doc in questions.documents { try? await doc.reference.delete() }

            // 自分が作成したチャットを削除
            let chats = try await db.collection("chats")
                .whereField("createdBy", isEqualTo: uid).getDocuments()
            for doc in chats.documents { try? await doc.reference.delete() }

            // ポイント履歴サブコレクションを削除
            let points = try await db.collection("users").document(uid)
                .collection("points").getDocuments()
            for doc in points.documents { try? await doc.reference.delete() }

            // ユーザードキュメント本体を削除
            try? await db.collection("users").document(uid).delete()

            // Live Activity をすべて終了
            await ActivityManager.shared.endAll()

            // ローカルキャッシュ（UserDefaults / App Group）を削除
            clearLocalData()

            // Firebase Auth アカウントを削除（最後に行う）
            try await user.delete()

            return nil
        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                return "セキュリティのため再ログインが必要です。一度サインアウトしてから再度サインインのうえ、もう一度お試しください。"
            }
            return "削除に失敗しました: \(error.localizedDescription)"
        }
    }

    private func clearLocalData() {
        let standard = UserDefaults.standard
        for key in standard.dictionaryRepresentation().keys
            where key.hasPrefix("kiku.") && key != "kiku.isDark" {
            standard.removeObject(forKey: key)
        }

        guard let appGroup = UserDefaults(suiteName: "group.com.yukichi.kiku") else { return }
        for key in appGroup.dictionaryRepresentation().keys
            where key.hasPrefix("kiku.") || key.hasPrefix("answer.") {
            appGroup.removeObject(forKey: key)
        }
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

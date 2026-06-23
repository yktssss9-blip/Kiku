import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

class AuthStore: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var user: User? = nil
    @Published var isLoading = true
    @Published var isSigningIn = false
    @Published var errorMessage: String? = nil
    @Published var appleDisplayName: String = ""

    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private var authController: ASAuthorizationController?

    override init() {
        super.init()
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

    func startAppleSignIn() {
        let nonce = randomNonceString()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authController = controller
        controller.performRequests()

        isSigningIn = true
        errorMessage = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let idTokenData = credential.identityToken,
            let idToken = String(data: idTokenData, encoding: .utf8)
        else {
            errorMessage = "認証情報の取得に失敗しました"
            isSigningIn = false
            return
        }
        let firebaseCredential = OAuthProvider.credential(
            providerID: .apple,
            idToken: idToken,
            rawNonce: nonce
        )
        let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { appleDisplayName = parts.joined(separator: " ") }
        signInOrLink(with: firebaseCredential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as NSError).code
        if code != ASAuthorizationError.canceled.rawValue {
            errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
        }
        isSigningIn = false
    }

    private func signInOrLink(with credential: AuthCredential) {
        print("[Kiku Auth] signInOrLink started")
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("[Kiku Auth] signIn error: \(error.localizedDescription)")
                    let nsError = error as NSError
                    if nsError.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
                       let updated = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                        Auth.auth().signIn(with: updated) { [weak self] _, retryError in
                            DispatchQueue.main.async {
                                if let retryError = retryError {
                                    self?.errorMessage = "サインインに失敗しました: \(retryError.localizedDescription)"
                                } else {
                                    self?.errorMessage = nil
                                }
                                self?.isSigningIn = false
                            }
                        }
                    } else {
                        self.errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
                        self.isSigningIn = false
                    }
                } else {
                    print("[Kiku Auth] signIn success: \(result?.user.uid ?? "no uid")")
                    self.errorMessage = nil
                    self.isSigningIn = false
                }
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

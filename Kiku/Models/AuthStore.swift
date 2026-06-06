import SwiftUI
import FirebaseAuth
import AuthenticationServices
import CryptoKit

class AuthStore: ObservableObject {
    @Published var user: User? = nil
    @Published var isLoading = true
    @Published var errorMessage: String? = nil

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

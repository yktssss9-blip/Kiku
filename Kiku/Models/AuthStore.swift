import SwiftUI
import FirebaseAuth

class AuthStore: ObservableObject {
    @Published var user: User? = nil
    @Published var isLoading = true

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isLoading = false
            }
        }
        signInAnonymouslyIfNeeded()
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var userId: String? { user?.uid }

    private func signInAnonymouslyIfNeeded() {
        guard Auth.auth().currentUser == nil else { return }
        Task {
            do {
                try await Auth.auth().signInAnonymously()
            } catch {
                print("[AuthStore] 匿名サインイン失敗: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}

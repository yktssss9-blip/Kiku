import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var timeoutTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Text("き く")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("グループに質問を送って\nロック画面から答えてもらおう")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }

                Spacer()

                VStack(spacing: 16) {
                    if let error = authStore.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 32)
                    }

                    if authStore.isSigningIn {
                        ProgressView()
                            .tint(.white)
                            .frame(height: 52)
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            authStore.isSigningIn = true
                            authStore.errorMessage = nil
                            authStore.prepareAppleRequest(request)
                        } onCompletion: { result in
                            authStore.handleAppleSignIn(result: result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 56)
            }
        }
        .onChange(of: authStore.isSigningIn) { _, signing in
            timeoutTask?.cancel()
            if signing {
                timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(15))
                    if !Task.isCancelled && authStore.isSigningIn {
                        authStore.isSigningIn = false
                        authStore.errorMessage = "接続がタイムアウトしました。もう一度お試しください。"
                    }
                }
            }
        }
    }
}

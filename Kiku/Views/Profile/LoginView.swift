import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore

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

                    SignInWithAppleButton(.signIn) { request in
                        authStore.prepareAppleRequest(request)
                    } onCompletion: { result in
                        authStore.handleAppleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 56)
            }
        }
    }
}

import SwiftUI
import AVFoundation

private enum AddMode: String, CaseIterable {
    case search = "検索"
    case scan   = "QRスキャン"
    case myQR   = "マイQR"
}

struct MemberAddView: View {
    @EnvironmentObject private var friendStore:  FriendStore
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .search

    // 検索
    @State private var username      = ""
    @State private var searchResult: FirestoreUser? = nil
    @State private var isSearching   = false
    @State private var errorMessage  = ""
    @State private var hasSearched   = false

    // 申請
    @State private var isSendingRequest = false
    @State private var sentUserUID: String? = nil

    // スキャン
    @State private var scannedUser: FirestoreUser? = nil
    @State private var isResolvingQR               = false
    @State private var qrError                     = ""
    @State private var showScannedSheet            = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("追加方法", selection: $mode) {
                    ForEach(AddMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .search: searchContent
                case .scan:   scanContent
                case .myQR:   myQRContent
                }
            }
            .navigationTitle("友達を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(isPresented: $showScannedSheet, onDismiss: {
                scannedUser = nil
                qrError = ""
            }) {
                if let user = scannedUser {
                    ScannedUserConfirmView(user: user, isSending: isSendingRequest, isSent: sentUserUID == user.uid) {
                        addFriend(user)
                    }
                }
            }
        }
    }

    // MARK: - 検索タブ

    @ViewBuilder
    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "at")
                    .foregroundStyle(.secondary)
                TextField("ユーザー名を入力", text: $username)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .onSubmit { Task { await search() } }
                if isSearching { ProgressView() }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()

            Button {
                Task { await search() }
            } label: {
                Text("検索")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(username.isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(username.isEmpty || isSearching)
            .padding(.horizontal)
            .padding(.bottom, 16)

            if let result = searchResult {
                userCard(result, isSent: sentUserUID == result.uid) { addFriend(result) }
                    .padding(.horizontal)
            } else if hasSearched && !isSearching {
                Text(errorMessage.isEmpty ? "ユーザーが見つかりませんでした" : errorMessage)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.top, 32)
            }

            Spacer()
        }
    }

    // MARK: - QRスキャンタブ

    @ViewBuilder
    private var scanContent: some View {
        ZStack {
            QRScannerView { scanned in
                guard !isResolvingQR, scannedUser == nil else { return }
                handleScanned(scanned)
            }

            if isResolvingQR {
                ProgressView()
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !qrError.isEmpty {
                VStack {
                    Spacer()
                    Text(qrError)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 100)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - マイQRタブ

    @ViewBuilder
    private var myQRContent: some View {
        if profileStore.username.isEmpty {
            ContentUnavailableView(
                "ユーザー名が未設定",
                systemImage: "qrcode",
                description: Text("プロフィールでユーザー名を設定するとQRコードを表示できます")
            )
        } else {
            QRCodeView(username: profileStore.username)
        }
    }

    // MARK: - 共有ユーザーカード

    private func userCard(_ user: FirestoreUser, isSent: Bool = false, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            UserAvatarView(emoji: user.emoji, photoURL: user.photoURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).font(.headline)
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSent {
                Text("申請済み")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                Button(action: onAdd) {
                    if isSendingRequest {
                        ProgressView()
                            .frame(width: 60, height: 32)
                    } else {
                        Text("申請")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .disabled(isSendingRequest)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - アクション

    private func search() async {
        guard !username.isEmpty else { return }
        isSearching  = true
        searchResult = nil
        errorMessage = ""
        hasSearched  = true
        defer { isSearching = false }

        do {
            searchResult = try await friendStore.searchUser(username: username)
        } catch {
            errorMessage = "検索中にエラーが発生しました"
        }
    }

    private func handleScanned(_ raw: String) {
        guard let url = URL(string: raw) else {
            qrError = "KikuのQRコードではありません"
            return
        }

        let username: String?
        if url.scheme == "kiku" && url.host == "add" {
            username = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "username" })?.value
        } else if url.host == "shigodeki-8e49a.web.app",
                  url.pathComponents.count >= 2, url.pathComponents[1] == "add" {
            username = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "username" })?.value
        } else {
            username = nil
        }

        guard let username, !username.isEmpty else {
            qrError = "KikuのQRコードではありません"
            return
        }

        isResolvingQR = true
        qrError = ""

        Task {
            defer { isResolvingQR = false }
            do {
                if let user = try await friendStore.searchUser(username: username) {
                    scannedUser = user
                    showScannedSheet = true
                } else {
                    qrError = "ユーザーが見つかりませんでした"
                }
            } catch {
                qrError = "検索中にエラーが発生しました"
            }
        }
    }

    private func addFriend(_ user: FirestoreUser) {
        guard !isSendingRequest else { return }
        isSendingRequest = true
        Task {
            defer { Task { @MainActor in isSendingRequest = false } }
            do {
                try await friendStore.sendFriendRequest(
                    to:           user,
                    fromName:     profileStore.name,
                    fromEmoji:    profileStore.emoji,
                    fromUsername: profileStore.username,
                    fromPhotoURL: profileStore.photoURL
                )
                await MainActor.run { sentUserUID = user.uid }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run { dismiss() }
            } catch {
                print("[MemberAddView] sendFriendRequest error: \(error)")
            }
        }
    }
}

// MARK: - スキャン後の確認シート

struct ScannedUserConfirmView: View {
    let user: FirestoreUser
    let isSending: Bool
    let isSent: Bool
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .frame(width: 36, height: 5)
                .foregroundStyle(Color(UIColor.systemGray4))
                .padding(.top, 12)

            UserAvatarView(emoji: user.emoji, photoURL: user.photoURL, size: 88)

            VStack(spacing: 4) {
                Text(user.name)
                    .font(.title2.weight(.semibold))
                Text("@\(user.username)")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    onAdd()
                } label: {
                    Group {
                        if isSent {
                            Label("申請を送りました", systemImage: "checkmark")
                        } else if isSending {
                            ProgressView()
                                .frame(height: 20)
                        } else {
                            Text("友達申請を送る")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isSent ? Color.green : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSending || isSent)

                Button("キャンセル", role: .cancel) { dismiss() }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.horizontal)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    MemberAddView()
        .environmentObject(FriendStore())
        .environmentObject(ProfileStore())
}

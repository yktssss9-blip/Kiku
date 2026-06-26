import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore:   FriendStore
    @EnvironmentObject private var groupStore:    GroupStore
    @EnvironmentObject private var profileStore:  ProfileStore
    @EnvironmentObject private var chatStore:     ChatStore
    @EnvironmentObject private var authStore:     AuthStore

    // 最新順フィード
    private var feedQuestions: [Question] {
        questionStore.questions.sorted { $0.createdAt > $1.createdAt }
    }

    // 未回答者がいる質問（最新順）
    private var pendingQuestions: [Question] {
        feedQuestions.filter { $0.summary().pending > 0 }
    }

    // 全員回答済み（最新順）
    private var completedQuestions: [Question] {
        feedQuestions.filter { $0.summary().pending == 0 }
    }

    // 自分宛の未回答受信質問（最新順）
    private var myPendingReceived: [(question: Question, memberId: UUID)] {
        questionStore.receivedQuestions
            .compactMap { q in
                guard let mid = questionStore.receivedMemberMap[q.id],
                      q.answers.contains(where: { $0.memberId == mid && $0.value == "pending" })
                else { return nil }
                return (question: q, memberId: mid)
            }
            .sorted { $0.question.createdAt > $1.question.createdAt }
    }

    @State private var questionToDelete: Question? = nil
    @State private var showDeleteQuestionAlert  = false
    @State private var isCompletedExpanded      = false
    @State private var isFriendRequestExpanded  = false

    private var hasFriendActivity: Bool {
        !friendStore.pendingRequests.isEmpty || !friendStore.sentRequests.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ─── 友達申請セクション ───
                    if hasFriendActivity {
                        friendRequestSection
                            .padding(.horizontal, 16)
                    }

                    // ─── あなたへの質問セクション ───
                    if !myPendingReceived.isEmpty {
                        receivedPendingSection
                            .padding(.horizontal, 16)
                    }

                    // ─── 進行中セクション ───
                    if !pendingQuestions.isEmpty {
                        pendingSection
                            .padding(.horizontal, 16)
                    }

                    // ─── 完了セクション ───
                    if !completedQuestions.isEmpty {
                        completedSection
                            .padding(.horizontal, 16)
                    }

                    // ─── 空状態 ───
                    if feedQuestions.isEmpty && myPendingReceived.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "questionmark.bubble")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("質問を送って\n返事を集めよう")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .refreshable {
                guard let uid = authStore.user?.uid else { return }
                async let q: () = questionStore.refresh(forUID: uid)
                async let f: () = friendStore.refresh(forUID: uid)
                async let g: () = groupStore.refresh(forUID: uid)
                async let c: () = chatStore.refresh(forUID: uid)
                _ = await (q, f, g, c)
            }
            .navigationTitle("フィード")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("質問を削除しますか？", isPresented: $showDeleteQuestionAlert, presenting: questionToDelete) { q in
            Button("削除", role: .destructive) {
                questionStore.delete(questionId: q.id)
                questionToDelete = nil
            }
            Button("キャンセル", role: .cancel) { questionToDelete = nil }
        } message: { q in
            Text("「\(q.text)」と回答データをすべて削除します。この操作は元に戻せません。")
        }
    }

    // MARK: - 友達申請セクション

    @ViewBuilder
    private var friendRequestSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFriendRequestExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("友達申請")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    if !friendStore.pendingRequests.isEmpty {
                        Text("\(friendStore.pendingRequests.count)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFriendRequestExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if isFriendRequestExpanded {
                VStack(spacing: 8) {
                    // 受信した申請（pending）
                    ForEach(friendStore.pendingRequests) { request in
                        ReceivedFriendRequestCard(request: request)
                            .environmentObject(friendStore)
                    }
                    // 送信した申請（全ステータス）
                    ForEach(friendStore.sentRequests) { request in
                        SentFriendRequestCard(request: request)
                    }
                }
            }
        }
    }

    // MARK: - あなたへの質問セクション

    @ViewBuilder
    private var receivedPendingSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("あなたへの質問")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text("\(myPendingReceived.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(myPendingReceived, id: \.question.id) { item in
                    ReceivedPendingCard(
                        question: item.question,
                        memberId: item.memberId,
                        senderFriend: friendStore.friends.first { $0.firebaseUID == item.question.createdBy }
                    ) { value in
                        questionStore.submitReceived(
                            questionId: item.question.id,
                            memberId: item.memberId,
                            value: value
                        )
                    }
                }
            }
        }
    }

    // MARK: - 進行中セクション

    @ViewBuilder
    private var pendingSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("進行中")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text("\(pendingQuestions.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(pendingQuestions) { question in
                    questionCard(question)
                }
            }
        }
    }

    // MARK: - 完了セクション

    @ViewBuilder
    private var completedSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCompletedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("完了")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text("\(completedQuestions.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCompletedExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if isCompletedExpanded {
                VStack(spacing: 8) {
                    ForEach(completedQuestions) { question in
                        questionCard(question)
                    }
                }
            }
        }
    }

    // MARK: - 質問カード

    @ViewBuilder
    private func questionCard(_ question: Question) -> some View {
        QuestionFeedCard(question: question, friends: friendStore.friends)
            .environmentObject(questionStore)
            .environmentObject(groupStore)
            .environmentObject(profileStore)
            .environmentObject(chatStore)
            .contextMenu {
                Button(role: .destructive) {
                    questionToDelete = question
                    showDeleteQuestionAlert = true
                } label: {
                    Label("質問を削除", systemImage: "trash")
                }
            }
    }

}

// MARK: - ReceivedPendingCard

struct ReceivedPendingCard: View {
    let question: Question
    let memberId: UUID
    let senderFriend: Friend?
    let onAnswer: (String) -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var showTimePicker  = false
    @State private var showFreeText    = false
    @State private var showStarPicker  = false
    @State private var showEmojiPicker = false
    @State private var timeDate        = Date()
    @State private var freeTextInput   = ""

    private static let emojiOptions = [
        "😊","😍","🥰","😂","😭","😡","😮","🤔",
        "👍","👎","🔥","❤️","💯","🎉","💪","🤯"
    ]

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 8) {
                UserAvatarView(
                    emoji: senderFriend?.emoji ?? "👤",
                    photoURL: senderFriend?.photoURL,
                    size: 34
                )
                Text(senderFriend?.name ?? "誰か")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("からの質問")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                timerBadge
            }

            Text(question.text)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(question.answerChoices) { choice in
                    choiceButton(choice)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            elapsed = max(0, -question.createdAt.timeIntervalSinceNow)
        }
        .onReceive(ticker) { _ in
            elapsed = max(0, -question.createdAt.timeIntervalSinceNow)
        }
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    Text(question.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    DatePicker("時刻", selection: $timeDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .padding(.top, 8)
                .navigationTitle("時刻で回答")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showTimePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("回答する") {
                            let fmt = DateFormatter()
                            fmt.dateFormat = "HH:mm"
                            onAnswer(fmt.string(from: timeDate))
                            showTimePicker = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showFreeText) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(question.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("自由に入力してください", text: $freeTextInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding()
                .navigationTitle("自由記述で回答")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            freeTextInput = ""
                            showFreeText = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("送信") {
                            let text = freeTextInput.trimmingCharacters(in: .whitespaces)
                            onAnswer("yes:\(text)")
                            freeTextInput = ""
                            showFreeText = false
                        }
                        .fontWeight(.semibold)
                        .disabled(freeTextInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showStarPicker) {
            NavigationStack {
                VStack(spacing: 24) {
                    Text(question.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    HStack(spacing: 16) {
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                onAnswer("star:\(n)")
                                showStarPicker = false
                            } label: {
                                Text("★")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                    Text("タップした星の数で評価されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .navigationTitle("星で評価")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showStarPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showEmojiPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text(question.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 12
                    ) {
                        ForEach(Self.emojiOptions, id: \.self) { emoji in
                            Button {
                                onAnswer("emoji:\(emoji)")
                                showEmojiPicker = false
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 40))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 64)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .navigationTitle("絵文字で反応")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showEmojiPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Timer Badge

    private var tierInfo: (icon: String, label: String, color: Color) {
        switch elapsed {
        case ..<60:   return ("⚡️", "超速",  .green)
        case ..<180:  return ("🕐", "早い",  .orange)
        default:      return ("💬", "普通",  .secondary)
        }
    }

    private var timerBadge: some View {
        let t = tierInfo
        return HStack(spacing: 4) {
            Text(t.icon).font(.caption)
            Text(elapsedString).font(.caption).monospacedDigit()
            Text(t.label).font(.caption2).foregroundStyle(t.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var elapsedString: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Choice Button

    @ViewBuilder
    private func choiceButton(_ choice: AnswerChoice) -> some View {
        Button {
            switch choice {
            case .yes:      onAnswer("yes")
            case .no:       onAnswer("no")
            case .time:     showTimePicker  = true
            case .freeText: showFreeText    = true
            case .star:     showStarPicker  = true
            case .emoji:    showEmojiPicker = true
            }
        } label: {
            HStack(spacing: 6) {
                switch choice {
                case .yes:
                    Text("○").font(.title2).fontWeight(.bold)
                case .no:
                    Text("✕").font(.title2).fontWeight(.bold)
                case .time:
                    Image(systemName: "clock.fill").font(.body)
                    Text("時刻").font(.body).fontWeight(.semibold)
                case .freeText:
                    Text("・・・").font(.body).fontWeight(.bold)
                case .star:
                    Text("☆").font(.title2).fontWeight(.bold)
                    Text("星評価").font(.body).fontWeight(.semibold)
                case .emoji:
                    Text("😊").font(.title2)
                    Text("絵文字").font(.body).fontWeight(.semibold)
                }
            }
            .foregroundStyle(choice.tintColor)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(choice.tintColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(choice.tintColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(QuestionStore())
        .environmentObject(FriendStore())
        .environmentObject(GroupStore())
        .environmentObject(ProfileStore())
        .environmentObject(ChatStore())
}

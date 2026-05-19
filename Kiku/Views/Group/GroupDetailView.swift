import SwiftUI

struct GroupDetailView: View {
    let group: KikuGroup
    @EnvironmentObject private var questionStore: QuestionStore
    @EnvironmentObject private var friendStore: FriendStore

    @State private var isShowingQuestionCreate = false

    var questions: [Question] {
        questionStore.questions(for: group)
    }

    var body: some View {
        List {
            Section {
                Button {
                    isShowingQuestionCreate = true
                } label: {
                    Label("質問を作成", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }

            Section("送信済みの質問") {
                if questions.isEmpty {
                    Text("まだ質問がありません")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(questions) { question in
                        NavigationLink(destination: QuestionDetailView(question: question, group: group)) {
                            questionRow(question)
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingQuestionCreate) {
            QuestionCreateView(group: group)
        }
    }

    private func questionRow(_ question: Question) -> some View {
        let s = question.summary()
        let total = question.answers.count
        let answered = s.yes + s.no
        return VStack(alignment: .leading, spacing: 4) {
            Text(question.text)
                .font(.body)
            Text("\(answered)/\(total)人回答済み")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

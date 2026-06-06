import SwiftUI

struct MemberCardItem {
    let emoji: String
    let value: String
}

struct ResultCardView: View {
    let question: Question
    let members: [MemberCardItem]

    private var s: (yes: Int, no: Int, pending: Int) { question.summary() }
    private var memo: String? {
        guard let m = question.memo, !m.isEmpty else { return nil }
        return m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            questionSection
            divider
            memberGrid
            divider
            statsRow
        }
        .padding(26)
        .frame(width: 360)
        .background(Color.black)
    }

    // MARK: - Sections

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.text)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if let memo {
                Text(memo)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(2)
            }
        }
        .padding(.bottom, 18)
    }

    private var memberGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 52), spacing: 8)],
            spacing: 10
        ) {
            ForEach(Array(members.prefix(16).enumerated()), id: \.offset) { _, m in
                memberCell(m)
            }
        }
        .padding(.bottom, 16)
    }

    private var statsRow: some View {
        HStack {
            HStack(spacing: 10) {
                statLabel("✅", s.yes,     .green)
                statLabel("❌", s.no,      Color(red: 1, green: 0.3, blue: 0.3))
                if s.pending > 0 {
                    statLabel("⏳", s.pending, Color(white: 0.45))
                }
            }
            Spacer()
            Text("きく")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.3))
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.15))
            .frame(height: 1)
            .padding(.bottom, 16)
    }

    private func memberCell(_ m: MemberCardItem) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.12))
                    .frame(width: 50, height: 50)
                Text(m.emoji)
                    .font(.system(size: 26))
            }
            Text(statusEmoji(m.value))
                .font(.system(size: 14))
                .offset(x: 3, y: 3)
        }
        .frame(width: 56, height: 56)
    }

    private func statusEmoji(_ value: String) -> String {
        if value == "yes"        { return "✅" }
        if answerIsNo(value)     { return "❌" }
        return "⏳"
    }

    private func statLabel(_ icon: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(icon).font(.system(size: 12))
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

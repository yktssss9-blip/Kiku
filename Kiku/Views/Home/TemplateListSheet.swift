import SwiftUI

struct TemplateListSheet: View {
    let currentText: String
    let currentFriendIds: [UUID]
    let currentGroupId: UUID?
    let currentChoices: [AnswerChoice]
    var onSelect: (QuestionTemplate) -> Void

    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingScheduleFor: UUID? = nil

    var body: some View {
        NavigationStack {
            List {
                if !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button {
                            templateStore.add(
                                text: currentText,
                                friendIds: currentFriendIds,
                                groupId: currentGroupId,
                                choices: currentChoices,
                                friends: friendStore.friends
                            )
                        } label: {
                            Label("現在の内容をテンプレートとして保存", systemImage: "bookmark.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Section {
                    if templateStore.templates.isEmpty {
                        Text("テンプレートがまだありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(templateStore.templates) { template in
                            VStack(spacing: 0) {
                                Button {
                                    onSelect(template)
                                    dismiss()
                                } label: {
                                    templateRow(template)
                                }
                                .buttonStyle(.plain)

                                scheduleRow(template)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    templateStore.delete(id: template.id)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("テンプレート")
                }
            }
            .navigationTitle("テンプレート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: Binding(
                get: { editingScheduleFor.flatMap { id in templateStore.templates.first { $0.id == id } } },
                set: { editingScheduleFor = $0?.id }
            )) { template in
                ScheduleEditSheet(template: template) { updated in
                    templateStore.updateSchedule(id: template.id, schedule: updated, friends: friendStore.friends)
                }
            }
        }
    }

    // MARK: - テンプレート行

    @ViewBuilder
    private func templateRow(_ template: QuestionTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)

            destinationLabel(template)
            choicesRow(template)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 自動送信行

    @ViewBuilder
    private func scheduleRow(_ template: QuestionTemplate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.caption)
                .foregroundStyle(template.schedule.isEnabled ? .orange : .secondary)

            if template.schedule.isEnabled {
                Text(template.schedule.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("自動送信 オフ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                editingScheduleFor = template.id
            } label: {
                Text("設定")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - 送信先ラベル

    @ViewBuilder
    private func destinationLabel(_ template: QuestionTemplate) -> some View {
        if let groupId = template.groupId,
           let group = groupStore.groups.first(where: { $0.id == groupId }) {
            Label {
                Text(group.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Text("👥").font(.caption)
            }
        } else if !template.friendIds.isEmpty {
            let names = template.friendIds.compactMap { id in
                friendStore.friends.first(where: { $0.id == id })
            }
            if !names.isEmpty {
                HStack(spacing: 4) {
                    ForEach(names.prefix(3)) { friend in
                        UserAvatarView(emoji: friend.emoji, photoURL: friend.photoURL, size: 20)
                    }
                    if names.count > 3 {
                        Text("+\(names.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(names.map(\.name).joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            Text("送信先未設定")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func choicesRow(_ template: QuestionTemplate) -> some View {
        let choices = template.choices.compactMap { AnswerChoice(rawValue: $0) }
        HStack(spacing: 6) {
            ForEach(choices) { choice in
                HStack(spacing: 4) {
                    Image(systemName: choice.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(choice.tintColor)
                    if let label = choice.shortLabel {
                        Text(label).font(.caption2).foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(choice.tintColor.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - ScheduleEditSheet

private struct ScheduleEditSheet: View {
    let template: QuestionTemplate
    var onSave: (ScheduleConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var config: ScheduleConfig

    private let weekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    init(template: QuestionTemplate, onSave: @escaping (ScheduleConfig) -> Void) {
        self.template = template
        self.onSave = onSave
        _config = State(initialValue: template.schedule)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("自動送信を有効にする", isOn: $config.isEnabled)
                }

                if config.isEnabled {
                    Section("繰り返し") {
                        Picker("種類", selection: $config.repeatType) {
                            Text("毎日").tag(ScheduleConfig.RepeatType.daily)
                            Text("曜日指定").tag(ScheduleConfig.RepeatType.weekly)
                        }
                        .pickerStyle(.segmented)

                        if config.repeatType == .weekly {
                            weekdayPicker
                        }
                    }

                    Section("送信時刻") {
                        DatePicker(
                            "時刻",
                            selection: Binding(
                                get: { config.timeDate },
                                set: { config.timeDate = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                    }

                    Section {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("自動送信は Developer Program 承認後に有効になります")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("自動送信の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave(config)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                let selected = config.weekdays.contains(day)
                Button {
                    if selected {
                        config.weekdays.removeAll { $0 == day }
                    } else {
                        config.weekdays.append(day)
                    }
                } label: {
                    Text(weekdayLabels[day - 1])
                        .font(.subheadline.weight(selected ? .bold : .regular))
                        .frame(width: 36, height: 36)
                        .background(selected ? Color.orange : Color(UIColor.secondarySystemBackground))
                        .foregroundStyle(selected ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

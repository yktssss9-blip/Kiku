import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            GroupListView()
                .tabItem {
                    Label("グループ", systemImage: "person.3")
                }

            MemberListView()
                .tabItem {
                    Label("友達", systemImage: "person.badge.plus")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

struct GroupListView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Image(systemName: "person.3")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                Text("グループがありません")
                    .font(.headline)
                Text("＋ボタンから作成してください")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("グループ")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // グループ作成シート（後で実装）
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("設定")
                .navigationTitle("設定")
        }
    }
}

#Preview {
    ContentView()
}

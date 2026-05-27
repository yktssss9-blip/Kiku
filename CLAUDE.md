# きく (Kiku) — Claude Code 引き継ぎドキュメント

## プロジェクト概要

グループ向けの Yes/No 質問アプリ。主催者が質問を作成し、メンバーが通知・Live Activity・アプリ内 UI で回答する iOS アプリ。

- **プラットフォーム**: iOS 17+ / SwiftUI / Swift 5.9
- **バックエンド**: なし（UserDefaults + App Group による端末内ローカル永続化）
- **Xcode プロジェクト**: `/Users/yukichi/Kiku/Kiku.xcodeproj`

---

## 識別子・チーム情報

| 項目 | 値 |
|---|---|
| メインアプリ Bundle ID | `com.yukichi.kiku` |
| Widget Extension Bundle ID | `com.yukichi.kiku.widget` |
| App Group | `group.com.yukichi.kiku` |
| Development Team | `TT6KR8QU45` |
| UserDefaults suite | `group.com.yukichi.kiku`（App Group 共有）|

> ⚠️ 無料の個人 Apple Developer アカウントのため、**Time Sensitive Notifications は使用不可**。  
> `.entitlements` から削除済み。通知の `interruptionLevel` は `.active`。

---

## フォルダ構成

```
Kiku/
├── Kiku/                        # メインアプリ
│   ├── KikuApp.swift            # エントリポイント・EnvironmentObject 注入
│   ├── ContentView.swift        # TabView（グループ/友達/チャット/プロフィール）
│   ├── Models/
│   │   ├── SharedStore.swift    # Question / Answer / Friend / KikuGroup 型定義
│   │   ├── QuestionStore.swift  # 質問管理 + 回答処理 + ポイント連携
│   │   ├── FriendStore.swift    # 友達管理
│   │   ├── GroupStore.swift     # グループ管理
│   │   ├── ChatStore.swift      # チャット管理（回答解放チャット）
│   │   ├── ProfileStore.swift   # 自分のプロフィール
│   │   ├── StatusStore.swift    # ステータス投稿
│   │   ├── PointRecord.swift    # PointTitle / PointTier / PointRecord 型
│   │   ├── PointStore.swift     # ポイント集計・永続化（直近7日間）
│   │   ├── ActivityManager.swift# Live Activity 起動管理
│   │   └── KikuActivityAttributes.swift # Live Activity 属性定義（ローカル）
│   ├── ViewModels/
│   │   ├── AnswerIntent.swift   # AppIntent 実装（Live Activity ボタン処理）
│   │   └── NotificationManager.swift # UNUserNotificationCenter 管理
│   └── Views/
│       ├── Group/               # GroupDetailView, GroupCreateView
│       ├── Question/            # QuestionDetailView, QuestionCreateView, AnswerView, BroadcastQuestionView
│       ├── Member/              # MemberListView（ランキング表）, MemberAddView
│       ├── Chat/                # ChatListView, ChatView
│       ├── Profile/             # ProfileSettingsView, ProfileSetupView
│       └── Status/              # StatusPostView
├── KikuWidget/                  # Widget Extension（Live Activity）
│   ├── KikuWidgetBundle.swift
│   ├── KikuLiveActivity.swift   # Dynamic Island / Lock Screen UI
│   ├── KikuActivityAttributes.swift # Widget 側の属性定義コピー
│   ├── SharedStore.swift        # Widget 側の型定義コピー
│   └── AnswerIntent.swift       # Widget 側スタブ（perform は空）
└── KikuShared/                  # Swift Package（共有型）
    └── Sources/KikuShared/
        ├── KikuActivityAttributes.swift
        └── SharedStore.swift
```

---

## 重要な実装詳細

### Live Activity ボタン（iOS 18 バグ対応済み）

iOS 18 で `AppIntent` の `openAppWhenRun = false` だと `perform()` が無言で無視されるバグあり。

**修正済みアプローチ**:
```swift
// Kiku/ViewModels/AnswerIntent.swift
struct AnswerIntent: AppIntent, LiveActivityIntent {
    static var openAppWhenRun: Bool = true  // ← これが必須

    func perform() async throws -> some IntentResult {
        // App Group UserDefaults に回答を保存
        UserDefaults(suiteName: "group.com.yukichi.kiku")?
            .set(value, forKey: "answer.\(questionId).\(memberId)")
        // NotificationCenter でアプリに即時通知
        await MainActor.run {
            NotificationCenter.default.post(name: .kikuAnswerSubmitted, object: nil)
        }
        return .result()
    }
}
```

- Widget 側の `AnswerIntent` は `perform()` が空のスタブ（実行は main app のみ）
- `KikuApp.swift` で `.kikuAnswerSubmitted` を observe して回答を `QuestionStore` に反映

### シゴできポイントシステム

| 回答速度 | ティア | ポイント |
|---|---|---|
| 60秒以内 | `.fast` ⚡️ 超速 | +20pt |
| 60〜180秒 | `.normal` 🕐 早い | +10pt |
| 180秒超 | `.late` 💬 普通 | +2pt |

- 有効期間: **直近7日間のみ**（`PointStore.activeRecords` でフィルタ）
- 永続化: `UserDefaults.standard` キー `kiku.points`

### 称号システム（PointTitle）

順位の百分位で称号決定（ポイント数ではなく**順位**ベース）。

| 称号 | 条件 |
|---|---|
| 👑 支配者 | 友達10人以上かつ1位 |
| 👔 CEO | 友達10人以上かつ上位 |
| 🤵 取締役 | 上位 |
| 🏢 部長 / 🗂️ 課長 / 📊 係長 / 📋 主任 | 中位 |
| 💼 平社員 / 🐣 新入社員 | 下位 |

- 友達9人以下のときは支配者・CEO を解放せず7段階で均等割り
- `PointStore.title(rank:outOf:)` → `PointTitle(rank:outOf:)`

### チャット解放（回答後）

- `ChatStore.unlock(questionId:memberId:questionText:answerValue:)` を呼ぶ
- 最初のメッセージとして「「{question}」に ✅ はい と回答しました」が自動挿入
- `ChatSession` は `answerValue: String` を保持（後方互換 Codable デコーダ実装済み）

### EnvironmentObject の注入（KikuApp.swift）

```swift
@StateObject private var questionStore  = QuestionStore()
@StateObject private var friendStore    = FriendStore()
@StateObject private var groupStore     = GroupStore()
@StateObject private var chatStore      = ChatStore()
@StateObject private var profileStore   = ProfileStore()
@StateObject private var statusStore    = StatusStore()
@StateObject private var pointStore     = PointStore()

// onAppear で連携
questionStore.pointStore = pointStore
```

---

## 現在の状態（2025-05-27 時点）

### 実装済み ✅
- グループ作成・質問送信
- Live Activity（Dynamic Island + ロック画面）でのはい/いいえボタン
- 通知長押しでのはい/いいえ回答
- 回答後チャット解放（回答内容も表示）
- シゴできポイントシステム（速度ティア・7日間ウィンドウ）
- 友達タブのランキング表（順位バッジ・称号・ポイント合計・履歴展開）
- プロフィール画面にポイント累計・履歴ページ
- QuestionDetailView: 集計カード・リマインド・Live Activity送信・メンバー回答一覧（ポイントティア表示）

### 未実装 / 検討中 🚧
- **時間回答機能**: 質問タイプを「時間」にして回答時に時刻ピッカー表示
- **絵文字リアクション**: チャットや質問への絵文字スタンプ
- **回答選択肢の拡張**: Yes/No 以外（感情・温度計など）の回答タイプ
- **QuestionDetailView のデザイン刷新**: アイコンが動くフローティング UI を一度実装したが **ユーザーの要望でリバート済み**。別アプローチで再検討予定。

---

## 開発ルール（このプロジェクト）

- 作業前に計画を提示し、ユーザー確認を取ってから実行する
- 変更後は変更内容の要約を出力する
- テスト/型チェックは `xcodebuild -scheme Kiku -destination 'generic/platform=iOS' build` で確認
- データの新規作成・上書き・削除はユーザー確認必須

---

## よくある落とし穴

1. **Widget の AnswerIntent は空スタブ** — Widget target に実処理を書いても動かない。常に main app target の `AnswerIntent` を編集する。
2. **App Group UserDefaults** — `UserDefaults.standard` と `UserDefaults(suiteName: "group.com.yukichi.kiku")` は別物。回答データは App Group 側に保存。
3. **`PBXFileSystemSynchronizedRootGroup`** — Xcode が自動でファイルを検出するので `.pbxproj` への手動ファイル追加は不要。新ファイルはフォルダに置くだけでよい。
4. **`openAppWhenRun = true`** は Live Activity ボタンを使う上で現状必須。将来の iOS アップデートで変わる可能性あり。
5. **PointTitle の init** は `init(rank: Int, outOf total: Int)` — かつての `init(points: Int)` とは異なる。

# きく (Kiku) — Claude Code 引き継ぎドキュメント

## プロジェクト概要

グループ向けの質問アプリ。主催者が質問を作成し、メンバーが通知・Live Activity・アプリ内 UI で回答する iOS アプリ。回答タイプは Yes/No のほか、時間・自由記述・星評価・絵文字に対応（詳細は後述の「回答タイプ（AnswerChoice）」参照）。

- **プラットフォーム**: iOS 17+ / SwiftUI / Swift 5.9
- **バックエンド**: Firebase（Firestore + Auth + Messaging）/ UserDefaults はローカルキャッシュとして併用
- **Xcode プロジェクト**: `/Users/yukichi/Kiku/Kiku.xcodeproj`
- **Firebase プロジェクト**: Shigodeki（`shigodeki-8e49a`）

---

## 識別子・チーム情報

| 項目 | 値 |
|---|---|
| メインアプリ Bundle ID | `com.yukichi.kiku` |
| Widget Extension Bundle ID | `com.yukichi.kiku.widget` |
| App Group | `group.com.yukichi.kiku` |
| Development Team | `TT6KR8QU45` |
| UserDefaults suite | `group.com.yukichi.kiku`（App Group 共有）|

> ✅ 2026-06-08 時点で有料 Apple Developer Program に登録済み。以前の「無料アカウントのため Time Sensitive Notifications 使用不可」という制約は解消された。  
> ただし `.entitlements` からは削除済みのまま・通知の `interruptionLevel` も `.active` のままで、再有効化の実装は未着手。再度使う場合は `.entitlements` に追加し `interruptionLevel: .timeSensitive` に変更する。

---

## フォルダ構成

```
Kiku/
├── Kiku/                        # メインアプリ
│   ├── KikuApp.swift            # エントリポイント・EnvironmentObject 注入
│   ├── ContentView.swift        # TabView（送る/フィード/チャット/ランキング/設定）
│   ├── Models/
│   │   ├── SharedStore.swift    # Question / Answer / Friend / KikuGroup 型定義
│   │   ├── AnswerChoice.swift   # 回答タイプ定義（yes/no/時間/自由記述/星評価/絵文字）
│   │   ├── AuthStore.swift      # Firebase Auth（Apple Sign In）・アカウント削除
│   │   ├── QuestionStore.swift  # 質問管理 + 回答処理 + ポイント連携
│   │   ├── FriendStore.swift    # 友達管理
│   │   ├── GroupStore.swift     # グループ管理（ローカルのみ・Firestore未移行）
│   │   ├── ChatStore.swift      # チャット管理（回答解放チャット）
│   │   ├── ProfileStore.swift   # 自分のプロフィール
│   │   ├── StatusStore.swift    # ステータス投稿
│   │   ├── PointRecord.swift    # PointTitle / PointTier / PointRecord 型
│   │   ├── PointStore.swift     # ポイント集計・永続化（直近7日間）
│   │   ├── TemplateStore.swift  # 質問テンプレート + 自動送信スケジュール
│   │   ├── PurchaseStore.swift  # RevenueCat連携（Proプラン判定・購入）
│   │   ├── ActivityManager.swift# Live Activity 起動管理
│   │   └── KikuActivityAttributes.swift # Live Activity 属性定義（ローカル）
│   ├── ViewModels/
│   │   ├── AnswerIntent.swift   # AppIntent 実装（Live Activity ボタン処理）
│   │   └── NotificationManager.swift # UNUserNotificationCenter 管理
│   └── Views/
│       ├── Home/                # HomeView（フィード）, SendTabView（送るタブ）, QuestionComposerView, QuestionFeedCard, TemplateListSheet
│       ├── Group/               # GroupDetailView, GroupCreateView, GroupEditView
│       ├── Question/            # QuestionDetailView, QuestionCreateView, AnswerView, ResultCardView
│       ├── Member/              # MemberListView（ランキング表）, MemberAddView, QRCodeView, QRScannerView
│       ├── Insight/             # InsightView（友達の回答傾向インサイト・自動送信設定、Pro限定）
│       ├── Chat/                # ChatListView, ChatView
│       ├── Notification/        # NotificationInboxView（未回答の通知一覧）
│       ├── Paywall/             # PaywallView（RevenueCatUI ペイウォール）
│       ├── Profile/             # LoginView, ProfileSetupView, ProfileSettingsView, InviteSetupView
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

### 回答タイプ（AnswerChoice）

`Models/AnswerChoice.swift` で yes/no 以外の回答タイプを定義済み・実装済み。

| タイプ | 内容 |
|---|---|
| `.yes` / `.no` | 通常の Yes/No |
| `.time` | 時刻ピッカーで回答 |
| `.freeText` | 自由記述 |
| `.star` | 星評価 + コメント（`AnswerView` の `.starComment` ステップ） |
| `.emoji` | 絵文字スタンプで回答 |

- `Question.answerChoices` で質問ごとに有効な選択肢を保持し、`AnswerView` が `hasTime` / `hasStar` / `hasEmoji` を見て表示を切り替える
- 通知アクション（長押しで回答）も各タイプに対応済み

### Pro プラン（RevenueCat）

- `KikuApp.swift` で `Purchases.configure(withAPIKey:)` により起動時に設定
- `PurchaseStore`: `entitlements["Shigodeki Pro"]` を見て `isPro` を判定。`refresh()` / `purchase()` / `restorePurchases()` を提供
- `PaywallView`（`Views/Paywall/`）: RevenueCatUI の `OfferingView` を表示
- Pro 限定機能: テンプレートからの送信（`SendTabView`）、自動送信スケジュール（`InsightView`）

### テンプレート・自動送信（TemplateStore）

- `TemplateStore`: 質問テンプレートの CRUD + Firestore 同期 + `ScheduleConfig`（毎日/毎週の繰り返し設定・`nextSendAt`）
- テンプレート保存時に `recipientUIDs`/`recipientMemberMap`/`memberNames`（`Friend.firebaseUID` から解決）も Firestore に保存し、Cloud Functions が宛先を解決できるようにしている（`QuestionStore.firestoreData` と同じパターン）
- 自動送信は `functions/src/index.ts` の `sendScheduledTemplates`（`onSchedule`、5分おき実行）で実装済み: `collectionGroup("templates")` を `schedule.isEnabled == true && nextSendAt <= now` で横断検索 → 該当テンプレートから `/questions/{questionId}` を新規作成 → `repeatType`/`hour`/`minute`/`weekdays` から次回 `nextSendAt` を計算して更新。質問作成により既存の `notifyOnQuestionCreated` が連鎖し通知/Live Activityも自動送信される
- UI: `TemplateListSheet`（テンプレート選択）、`InsightView` 内の `ScheduledSendSheet`（自動送信設定）

### インサイト（InsightView）

- `Views/Insight/InsightView.swift`: 友達ごとの「回答しやすい時間帯」「平均回答速度」などの傾向を可視化
- `MemberListView` 内のタブとして統合。Pro プラン限定機能

### 通知インボックス（NotificationInboxView）

- `Views/Notification/NotificationInboxView.swift`: 自分宛の未回答（pending）質問の一覧を表示
- `HomeView` のバナーから遷移

### アカウント削除（AuthStore.deleteAccount）

- `AuthStore.deleteAccount() async -> String?`: 以下を順に実行し、成功時 `nil` / 失敗時エラーメッセージを返す
  1. `usernames/{username}` の解放
  2. 自分が作成した `questions` / `chats`（`createdBy == uid`）を一括削除
  3. `users/{uid}/points/*` サブコレクション削除
  4. `users/{uid}` ドキュメント削除
  5. Live Activity 全終了（`ActivityManager.endAll()`）
  6. ローカル UserDefaults（標準 + App Group）の `kiku.*` / `answer.*` キー削除（`kiku.isDark` 等の表示設定は維持）
  7. `Auth.auth().currentUser?.delete()` で Firebase Auth アカウント自体を削除
- `requiresRecentLogin` エラー時は専用メッセージを返す（再サインインを促す）
- UI: `SettingsView`（`ContentView.swift`）の「アカウント」セクション。写真削除と同じ `confirmationDialog` パターンで確認

### EnvironmentObject の注入（KikuApp.swift）

```swift
@StateObject private var authStore     = AuthStore()
@StateObject private var profileStore  = ProfileStore()
@StateObject private var friendStore   = FriendStore()
@StateObject private var groupStore    = GroupStore()
@StateObject private var questionStore = QuestionStore()
@StateObject private var statusStore   = StatusStore()
@StateObject private var chatStore     = ChatStore()
@StateObject private var pointStore    = PointStore()
@StateObject private var templateStore = TemplateStore()
@StateObject private var purchaseStore = PurchaseStore()

// onAppear で連携
questionStore.pointStore = pointStore
```

---

## 現在の状態（2026-06-07 時点）

### 実装済み ✅
- グループ作成・質問送信（`SendTabView`）、フィード（`HomeView`）
- Live Activity（Dynamic Island + ロック画面）でのはい/いいえボタン
- 通知長押しでの回答（yes/no/時間/自由記述/星評価/絵文字 — `AnswerChoice` 全タイプ対応）
- 回答後チャット解放（回答内容も表示）
- シゴできポイントシステム（速度ティア・7日間ウィンドウ）
- ランキングタブ（順位バッジ・称号・ポイント合計・履歴展開）、インサイト（友達の回答傾向、Pro限定）
- プロフィール画面にポイント累計・履歴ページ
- 通知インボックス（未回答の質問一覧）
- テンプレート + 自動送信スケジュール（Cloud Functions `sendScheduledTemplates`、Pro限定）
- Pro プラン課金（RevenueCat / `PurchaseStore` / `PaywallView`）
- アカウント削除（`AuthStore.deleteAccount()`、設定画面から実行可能）
- QuestionDetailView: 集計カード・リマインド・Live Activity送信・メンバー回答一覧（ポイントティア表示）
- **Firebase 実装済み**:
  - **Apple Sign In 認証**（匿名認証から切り替え済み。`LoginView` で `SignInWithAppleButton` を表示、`AuthStore` に実装あり）
  - ProfileStore / QuestionStore / ChatStore / PointStore / TemplateStore → Firestore リアルタイム同期
  - ユーザー名検索による友達追加（`/usernames/{username}` コレクション）
  - FCMトークン登録コード（`/users/{uid}` の `fcmToken` に保存済み）。配信側 Cloud Functions も実装・デプロイ済み（`functions/src/index.ts` の `notifyOnQuestionCreated`、Blazeプラン移行済み）。残作業は APNs キー設定と実機確認のみ

### 未実装 / 検討中 🚧

- **FCM プッシュ通知（他ユーザーへの通知の配信）**: Cloud Functions（`notifyOnQuestionCreated`）は実装・デプロイ済み、Blaze プランへのアップグレードも完了。残るのは APNs 認証キー（`.p8`）の作成・Firebase Console へのアップロードと、実機 2 台での配信動作確認

- **GroupStore → Firestore 移行**: 現在もローカル（UserDefaults）のまま。グループをFirestoreに保存してメンバー間で共有できるようにする

- **絵文字リアクション**: チャットへの絵文字スタンプ（`AnswerChoice.emoji` は回答タイプとして実装済みだが、チャットメッセージへのリアクションは別件・未実装）
- **QuestionDetailView のデザイン刷新**: アイコンが動くフローティング UI を一度実装したが **ユーザーの要望でリバート済み**。別アプローチで再検討予定。

---

## Firebase 実装詳細

### 認証フロー（KikuApp.swift）

Apple Sign In 実装済み（`Kiku.entitlements` に `com.apple.developer.applesignin` 設定済み）。`LoginView` で `SignInWithAppleButton` を表示し、`AuthStore.handleAppleSignIn` が認証情報を処理する。

```swift
// 起動時の表示ロジック
authStore.isLoading → ProgressView
authStore.user == nil → LoginView（Apple でサインイン）
profileStore.isSetupComplete == false → ProfileSetupView
上記以外 → ContentView

// 認証完了時に各Storeのリスナーを起動
.onChange(of: authStore.user) { _, user in
    if let user {
        profileStore.syncFromFirestore()
        questionStore.startListening(forUID: user.uid)
        chatStore.startListening(forUID: user.uid)
        pointStore.startListening(forUID: user.uid)
        templateStore.startListening(forUID: user.uid)
    } else {
        questionStore.stopListening()
        chatStore.stopListening()
        pointStore.stopListening()
        templateStore.stopListening()
    }
}
```

> ⚠️ シミュレータでサインインをテストするには、Apple ID でサインイン済みの実機 or シミュレータが必要（匿名認証のフォールバックは無い）。

### Firestoreコレクション構造

```
/users/{uid}
  name, emoji, username, localId, fcmToken, updatedAt

/usernames/{username}
  uid   ← ユーザー名の一意性保証・検索用

/questions/{questionId}
  text, groupId, choices, createdAt, createdBy
  answers: { "{memberId-uuid}": { value, answeredAt } }

/chats/{questionId}
  questionText, memberAnswers, createdAt, createdBy
  messages: [ { id, text, senderId, channel, sentAt, ... } ]

/users/{uid}/points/{recordId}
  questionId, memberId, questionText, tier, earnedAt
```

### Storeとリスナーの対応

| Store | リスナー条件 | Firestoreパス |
|---|---|---|
| QuestionStore | `createdBy == uid` | `/questions` |
| ChatStore | `createdBy == uid` | `/chats` |
| PointStore | `earnedAt > 7日前` | `/users/{uid}/points` |

### よくある落とし穴（Firebase）

- **`isUpdatingFromFirestore` フラグ**: Firestoreからの更新時に `didSet { save() }` が走って二重書き込みになるのを防いでいる。各Storeに実装済み。
- **Apple Sign In の UID**: 匿名認証から Apple Sign In に切り替え済み。`current.link(with: credential)` で既存の匿名アカウントに紐付ける実装になっているため、匿名時代のデータは引き継がれる想定（`AuthStore.signInOrLink`）。
- **FCMトークン保存タイミング**: `messaging(_:didReceiveRegistrationToken:)` はサインイン前に呼ばれる場合があるため、`Auth.auth().currentUser?.uid` が nil のときは保存されない。サインイン後に `Messaging.messaging().token(completion:)` で再取得して保存する処理が必要になる場合がある。

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

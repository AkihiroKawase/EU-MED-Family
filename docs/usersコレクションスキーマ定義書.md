## users コレクション スキーマ定義書

### 1. `users` コレクションの運用ルール
- `users` コレクションは、ユーザーの公開プロフィール情報（表示名、自己紹介、画像URLなど）を保持します。
- **ドキュメントIDには、Firebase Authentication が発行する ユーザーID (uid) をそのまま使用します。** これにより、Auth情報とプロフィール情報が1対1で紐付きます。
- このドキュメントは、ユーザーがアカウントを新規登録した（サインアップした）タイミングで作成されることを想定します。
- このドキュメントの更新は、主に「プロフィール登録・修正画面」からユーザー自身によって行われます。

### 2. フィールド: `users` に必要なフィールド

| フィールド名（日本語） | フィールド名（英語） | 型 | 説明 |
| :--- | :--- | :--- | :--- |
| 表示名 | `displayName` | String | アプリ内で表示される名前。 |
| プロフィール画像URL | `profileImageUrl` | String | Cloud Storage等のURL。 |
| 背景画像URL | `backgroundImageUrl` | String | Cloud Storage等のURL。 |
| MBTI | `mbti` | String | (例: "INFP") |
| Canva URL | `canvaUrl` | String | 共有URL。 |
| 現在の国 | `currentCountry` | String | (例: "ハンガリー") |
| PDF URL | `pdfUrl` | String | 共有URL。 |
| 卒後行きたい国 | `futureCountry` | String | (例: "アメリカ", "日本") |
| 卒後の夢 | `futureDream` | String | 夢や目標。 |
| 大学 | `school` | String | 在籍（または出身）大学名。 |
| 学年 | `grade` | String | (例: "1年生", "卒業生") |
| 自己紹介 | `bio` | String | 長文の自己紹介文。 |
| チェック1 | `check1` | Boolean | **(隠しフラグ)** デフォルト `false`。管理者用または特定ロジック用。 |
| チェック2 | `check2` | Boolean | **(隠しフラグ)** デフォルト `false`。管理者用または特定ロジック用。 |
| 作成日時 | `createdAt` | Timestamp | アカウント登録日時。 |
| 更新日時 | `updatedAt` | Timestamp | プロフィール最終更新日時。 |

### 3. インデックス（推奨）

「プロフィール一覧画面」での検索・絞り込み要件に基づき、以下の複合インデックスを推奨します。

- **新着ユーザー順での一覧表示用:**
    - `createdAt` (降順)
- **国別での絞り込み + 新着順:**
    - (`currentCountry`, `createdAt` desc)
- **大学別での絞り込み + 新着順:**
    - (`school`, `createdAt` desc)
- **学年別での絞り込み + 新着順:**
    - (`grade`, `createdAt` desc)

**※ 注意（キーワード検索について）**
`displayName` や `bio` での「キーワード検索（部分一致）」は、Firestoreの標準機能では効率的に実現できません。これを要件とする場合、**Algolia** などの外部全文検索サービスの利用を強く推奨します。
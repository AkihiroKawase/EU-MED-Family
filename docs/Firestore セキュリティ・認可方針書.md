# Firestore セキュリティ・認可方針書

## 1. 基本原則

1.  **デフォルトDeny:** すべてのコレクションへのアクセスは、明示的に許可されていない限り、デフォルトで拒否（`allow read, write: if false;`）されます。
2.  **認証必須:** ログインしていないユーザー（`request.auth == null`）によるデータの読み書きは、原則として一切許可しません。
3.  **所有権の強制:** ユーザーが作成したデータ（設定、ブックマークなど）は、原則としてそのユーザー（`request.auth.uid == resource.data.userId`）または管理者のみが変更・削除できるようにします。
4.  **サーバーサイドのロジック:** 統計情報（いいね数など）の更新や通知の作成は、クライアント（アプリ）から直接Firestoreに書き込ませず、必ずCloud Functions（サーバーサイド）経由で実行します。

## 2. ロール定義

| ロール | 説明 | 判定方法（例） |
| :--- | :--- | :--- |
| `user` | 一般ユーザー。認証済み。 | `request.auth != null` |
| `admin` | 管理者。不適切なコメントの削除などを行える。 | `get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin'` |

## 3. コレクション別ルール

### /userSettings/{userId}
* **対象:** ユーザー個別の設定（通知ON/OFFなど）
* **Read:** 本人（`userId == request.auth.uid`）のみ
* **Create:** 本人（`userId == request.auth.uid`）のみ
* **Update:** 本人（`userId == request.auth.uid`）のみ
* **Delete:** 原則不可（または本人）

### /postStats/{postId}
* **対象:** 投稿の統計情報（いいね数、コメント数など）
* **Read:** 認証ユーザー（`user`）なら誰でも
* **Create:** サーバーサイド（Cloud Functions）のみ
* **Update:** サーバーサイド（Cloud Functions）のみ
* **Delete:** サーバーサイド（Cloud Functions）のみ

### /likes/{likeId} (※または /users/{userId}/likes/{postId})
* **対象:** ユーザーの「いいね」情報
* **Read:** 本人（`resource.data.userId == request.auth.uid`）のみ
* **Create:** 本人（`request.resource.data.userId == request.auth.uid`）のみ
* **Delete:** 本人（`resource.data.userId == request.auth.uid`）のみ

### /bookmarks/{bookmarkId} (※または /users/{userId}/bookmarks/{postId})
* **対象:** ユーザーの「ブックマーク」情報
* **Read:** 本人（`resource.data.userId == request.auth.uid`）のみ
* **Create:** 本人（`request.resource.data.userId == request.auth.uid`）のみ
* **Delete:** 本人（`resource.data.userId == request.auth.uid`）のみ

### /comments/{commentId}
* **対象:** 投稿へのコメント
* **Read:** 認証ユーザー（`user`）なら誰でも
* **Create:** 認証ユーザー（`user`）なら誰でも（`request.resource.data.userId == request.auth.uid` を検証）
* **Update:** 本人（`resource.data.userId == request.auth.uid`） または 管理者（`admin`）
* **Delete:** 本人（`resource.data.userId == request.auth.uid`） または 管理者（`admin`）
    * *注: 仕様（4.2）に基づき、これはソフトデリート（`isDeleted: true` のUpdate）を指す。*

### /notifications/{notificationId}
* **対象:** ユーザーへの通知
* **Read:** 本人（`resource.data.userId == request.auth.uid`）のみ
* **Create:** サーバーサイド（Cloud Functions）のみ
* **Update:** 本人（`resource.data.userId == request.auth.uid`）（例: 既読フラグの更新）
* **Delete:** 本人（`resource.data.userId == request.auth.uid`）
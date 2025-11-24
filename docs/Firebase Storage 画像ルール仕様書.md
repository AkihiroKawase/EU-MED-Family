# Firebase Storage 画像ルール仕様書 (v1.0 Draft)

## 1. 目的
投稿のカバー画像に関して、クライアント（Flutterアプリ）とFirebase Storage間のアップロード仕様、ファイル制約、およびNotion DBへのURL保存フローを定義する。

## 2. ファイル制約 (クライアントサイド)
アプリは、ユーザーが画像を選択する際、以下の制約を適用する。

* **ファイル形式:** `PNG`, `JPG`, `JPEG` のみ許可。
* **ファイルサイズ上限:** `5MB` まで。これを超えるファイルはアップロード前に拒否する。
* **アスペクト比:** `16:9` に固定。ユーザーには中央トリミング（クロッピング）UIを提供する。

## 3. Storageパス設計 (命名規則)
アップロードされる画像ファイルは、衝突を避けるため以下のパス規則に従う。

* **保存パス:** `covers/{post_id}.[拡張子]`
* **例:** `covers/a1b2c3d4-e5f6-7890-g1h2-i3j4k5l6m7n8.jpg`
* **備考:** `post_id` は、`POST /posts` APIのレスポンスとして取得したNotionページIDを使用する。

## 4. アップロードとURL保存フロー (案D)
カバー画像（任意）のアップロードは、投稿作成（`POST /posts`）が完了した後、以下の手順で実行する。

1.  **[API] 投稿作成:**
    * アプリが `POST /posts` を呼び出す。（この時点では `Cover Image URL` は空）
    * APIはNotionにページを作成し、成功レスポンスとして新しい `post_id` をアプリに返す。

2.  **[App] 画像アップロード:**
    * （ユーザーがカバー画像を選択していた場合のみ）アプリはステップ1で取得した `post_id` を使用し、画像を `covers/{post_id}.[拡張子]` としてFirebase Storageにアップロードする。

3.  **[App] 公開URL取得:**
    * アプリはアップロードしたファイルの公開ダウンロードURL（`https://firebasestorage.googleapis.com/...`）を取得する。

4.  **[API] URL保存:**
    * アプリは `PUT /posts/{id}` API（または専用の `PATCH /posts/{id}/cover` API）を呼び出し、ステップ3で取得した公開URLをNotionの `Cover Image URL` フィールドに保存するようリクエストする。

## 5. セキュリティルール (Firebase Storage)
Storageのセキュリティルール（`storage.rules`）は、認証済みユーザーが指定されたパス（`covers/`）にのみ書き込めるよう制限する。

```rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // covers/ 以下は認証済みユーザーのみ書き込み可
    // {postId} は {userId} と一致する必要はないが、ファイルサイズと形式を制限
    match /covers/{postId} {
      allow write: if request.auth != null
                      && request.resource.size < 5 * 1024 * 1024
                      && request.resource.contentType.matches('image/(jpeg|png)');
      
      // 公開読み取りを許可
      allow read; 
    }
  }
}
```
*(このルールはSprint 2以降の実装時に検証・確定する)*
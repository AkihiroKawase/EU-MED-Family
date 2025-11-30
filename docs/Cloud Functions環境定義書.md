#  Cloud Functions 環境定義書 (v1.0 Draft)

## 1. 目的

この文書は、[EU Med Student APP] のCloud Functionsプロジェクトで使用する環境変数の管理ポリシーとキー一覧を定義します。
目的は、APIキーなどの機密情報をコードから分離し、ローカル開発環境と本番環境（Firebase）で安全かつ一貫した設定を運用することです。

## 2. 管理ポリシー

環境変数は「ローカル開発環境」と「本番環境」の2種類で管理します。

### 2.1 本番環境 (Production)

* **管理方法:** Firebase CLIの `functions:config` コマンドを使用して設定します。
* **設定者:** プロジェクト管理者のみが設定・更新権限を持ちます。
* **コードからの参照:** `functions.config().service_name.key_name` の形式で参照します。（例: `functions.config().notion.api_key`）

### 2.2 ローカル開発環境 (Local)

* **管理方法:** プロジェクトルートに `.env.local` ファイル（または `.env`）を配置して管理します。
* **セキュリティ:** **`.env.local` ファイルは `.gitignore` に追加し、絶対にGitリポジトリにコミットしません。**
* **読み込み:** Firebaseエミュレータやローカルサーバー起動時に、`dotenv` ライブラリなどを使用して自動で読み込みます。

---

## 3. 環境変数キー一覧

キーは `SERVICE.KEY` の形式（例: `notion.api_key`）で統一します。

| サービス | キー (Local: `.env.local`) | Firebase Config コマンド (例) | 説明 |
| :--- | :--- | :--- | :--- |
| **Notion** | `NOTION_API_KEY` | `firebase functions:config:set notion.api_key="sk_..."` | Notionインテグレーションのシークレットキー |
| **Notion** | `NOTION_POSTS_DATABASE_ID` | `firebase functions:config:set notion.posts_db_id="..."` | 投稿DBのデータベースID |
| **Notion** | `NOTION_TAGS_DATABASE_ID` | `firebase functions:config:set notion.tags_db_id="..."` | タグDBのデータベースID |

*(将来、外部API（例: メール送信、ストレージバケット名指定など）を追加した場合は、この一覧に追記します。)*

---

## 4. 運用ルール

1.  **キーの取得と設定:**
    * Notion APIキーと各DB IDは、Notionの該当ページから管理者が取得します。
    * **本番環境:** 管理者が上記「Firebase Config コマンド」を実行して設定します。設定後は `firebase functions:config:get` で内容を確認します。
    * **ローカル環境:** 開発者各自が `.env.local` ファイルを作成し、管理者から安全な方法（例: 1Password, SlackのDMなど）で共有されたキーの値をコピー＆ペーストします。
2.  **キーの追加・変更:**
    * 新しいキーが必要になった場合、まずこの文書（環境定義書）を更新します。
    * 管理者がローカルの `.env.local`（のテンプレート） と Firebase `functions:config` の両方に設定を反映させます。
    * `firebase deploy --only functions` を実行して本番環境に反映させます。
3.  **`.gitignore` の設定:**
    プロジェクトの `.gitignore` に以下が記載されていることを確認します。

    ```gitignore
    # Environment variables
    .env
    .env.*
    !.env.example
    ```
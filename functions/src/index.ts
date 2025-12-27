import * as functions from "firebase-functions/v1"; // v1を明示的に指定してエラーを回避
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Client } from "@notionhq/client";
import {
  PageObjectResponse,
  CreatePageParameters,
} from "@notionhq/client/build/src/api-endpoints";

const notion = new Client({
  auth: process.env.NOTION_TOKEN,
});

// ★ これを追加
export const getMediaUrl = functions.https.onCall(async (data) => {
  const pageId = data.pageId as string;
  if (!pageId) {
    throw new functions.https.HttpsError("invalid-argument", "pageId is required");
  }

  const page: any = await notion.pages.retrieve({ page_id: pageId });

  const propName = "ファイル&メディア";
  const prop = page.properties[propName];

  if (!prop || prop.type !== "files") {
    return { url: null };
  }

  const file = prop.files?.[0];
  if (!file) return { url: null };

  const url =
    file.type === "file"
      ? file.file?.url
      : file.type === "external"
      ? file.external?.url
      : null;

  return { url };
});

// Firebase Admin SDKの初期化
admin.initializeApp();
const db = admin.firestore();

// ---------------------------------------------------------------------------
// 遅延初期化: Notion クライアント
// ---------------------------------------------------------------------------
let cachedNotionClient: Client | null = null;

/**
 * Notion クライアントを取得する（遅延初期化 + キャッシュ）
 * 関数実行時に初めて環境変数を読み込むことで、.env の値を確実に取得する
 */
function getNotionClient(): Client {
  if (cachedNotionClient) return cachedNotionClient;

  const apiKey = process.env.NOTION_API_KEY || "";
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "NOTION_API_KEY is not configured.");
  }

  cachedNotionClient = new Client({ auth: apiKey });
  return cachedNotionClient;
}

/**
 * Notion Database ID を取得する（遅延取得）
 */
function getNotionDatabaseId(): string {
  const databaseId = process.env.NOTION_DATABASE_ID || "";
  if (!databaseId) {
    throw new HttpsError("failed-precondition", "NOTION_DATABASE_ID is not configured.");
  }
  return databaseId;
}

// ---------------------------------------------------------------------------
// 型定義
// ---------------------------------------------------------------------------
interface PostData {
  id: string;
  title: string;
  firstCheck: boolean;
  secondCheck: boolean;
  canvaUrl: string | null;

  // ✅ Category は Notion 側が select 想定（アプリ側は配列で扱ってOK）
  categories: string[];

  // ✅ 追加：詳細表示用
  secondCheckAssignees: string[];
  authors: string[];
  fileUrls: string[];

  status: string | null;
  createdTime: string | null;
  lastEditedTime: string | null;
}

interface UpsertPostInput {
  id?: string;
  title: string;
  firstCheck: boolean;
  secondCheck: boolean;
  canvaUrl?: string | null;
  categories?: string[];
  status?: string | null;
}

// ---------------------------------------------------------------------------
// ヘルパー関数: Notion ページを PostData に変換
// ---------------------------------------------------------------------------
function parseNotionPageToPost(page: PageObjectResponse): PostData {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const props = page.properties as any;

  const getTitle = (key: string): string => {
    const prop = props[key];
    if (!prop || prop.type !== "title") return "";
    const arr = prop.title ?? [];
    return arr.length > 0 ? (arr[0]?.plain_text ?? "") : "";
  };

  const getCheckbox = (key: string): boolean => {
    const prop = props[key];
    if (!prop || prop.type !== "checkbox") return false;
    return prop.checkbox ?? false;
  };

  const getUrl = (key: string): string | null => {
    const prop = props[key];
    if (!prop || prop.type !== "url") return null;
    return prop.url ?? null;
  };

  // ✅ select / multi_select 両対応
  const getCategoryNames = (key: string): string[] => {
    const prop = props[key];
    if (!prop) return [];

    if (prop.type === "select") {
      const sel = prop.select;
      return sel?.name ? [sel.name] : [];
    }

    if (prop.type === "multi_select") {
      const ms = prop.multi_select ?? [];
      return ms
        .map((e: any) => e?.name ?? "")
        .filter((name: string) => name.length > 0);
    }

    return [];
  };

  // ✅ people: prop.people ではなく prop.people配列(型チェック込み)
  const getPeopleNames = (key: string): string[] => {
    const prop = props[key];
    if (!prop || prop.type !== "people") return [];
    const people = prop.people ?? [];
    return people
      .map((p: any) => p?.name ?? "")
      .filter((name: string) => name.length > 0);
  };

  // ✅ files: prop.files は配列。file/external の url を取る
  const getFileUrls = (key: string): string[] => {
    const prop = props[key];
    if (!prop || prop.type !== "files") return [];
    const files = prop.files ?? [];
    return files
      .map((f: any) => {
        // Notion: { type: "file", file: { url } } or { type: "external", external:{ url } }
        if (f?.type === "file") return f?.file?.url ?? "";
        if (f?.type === "external") return f?.external?.url ?? "";
        // 互換（念のため）
        const fileObj = f?.file ?? f?.external;
        return fileObj?.url ?? "";
      })
      .filter((u: string) => u.length > 0);
  };

  const getStatusName = (key: string): string | null => {
    const prop = props[key];
    if (!prop || prop.type !== "status") return null;
    return prop.status?.name ?? null;
  };

  console.log("DEBUG keys:", Object.keys(props));
  console.log("DEBUG Category raw:", props["Category"]);
  console.log("DEBUG 著者 raw:", props["著者"]);
  console.log("DEBUG ファイル raw:", props["ファイル&メディア"]);
  
  return {
    id: page.id,
    title: getTitle("タイトル"),
    firstCheck: getCheckbox("1st check"),
    secondCheck: getCheckbox("Check ②"),
    canvaUrl: getUrl("Canva URL"),

    categories: getCategoryNames("Category"),

    secondCheckAssignees: getPeopleNames("Check ② 担当"),
    authors: getPeopleNames("著者"),
    fileUrls: getFileUrls("ファイル&メディア"),

    status: getStatusName("ステータス"),
    createdTime: page.created_time || null,
    lastEditedTime: page.last_edited_time || null,

  };

}

// ---------------------------------------------------------------------------
// ヘルパー関数: PostData を Notion プロパティに変換
// ---------------------------------------------------------------------------
function buildNotionProperties(post: UpsertPostInput) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const props: any = {
    "タイトル": {
      title: [
        {
          text: { content: post.title },
        },
      ],
    },
    "1st check": {
      checkbox: post.firstCheck,
    },
    "Check ②": {
      checkbox: post.secondCheck,
    },
  };

  // Canva URL
  if (post.canvaUrl !== undefined) {
    props["Canva URL"] = {
      url: post.canvaUrl || null,
    };
  }

  // ✅ Category（select型）
  // - post.categories が渡された場合は、先頭のみ保存（selectのため）
  // - 空配列ならカテゴリをクリアしたい場合は select:null
  if (post.categories !== undefined) {
    const name = post.categories.length > 0 ? post.categories[0] : null;
    props["Category"] = name ? { select: { name } } : { select: null };
  }

  // ステータス（status型）
  if (post.status !== undefined) {
    props["ステータス"] = {
      status: post.status ? { name: post.status } : null,
    };
  }

  return props;
}

/**
 * 共通ロジック: メールアドレスからNotionユーザーIDを取得してFirestoreを更新する
 * @param {string | undefined} email - ユーザーのメールアドレス
 * @param {string} uid - Firebase AuthのUser ID
 * @return {Promise<string | null>} Notion User ID または null
 */
async function syncUserWithNotion(email: string | undefined, uid: string) {
  if (!email) {
    console.log(`User ${uid} has no email. Skipping Notion sync.`);
    return null;
  }

  const client = getNotionClient();

  try {
    // 1. Notionの全ユーザーを取得
    const response = await client.users.list({});
    const notionUsers = response.results;

    // 2. メールアドレスが一致するユーザーを検索
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const targetNotionUser = notionUsers.find((user: any) => {
      return user.person && user.person.email === email;
    });

    if (targetNotionUser) {
      // 3. Firestoreを更新
      await db.collection("users").doc(uid).set({
        notionUserId: targetNotionUser.id,
        lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      console.log(`Synced ${email} to Notion User ID: ${notionUserId}`);
      return notionUserId;
    } else {
      console.log(`No matching user found in database for email: ${email}`);
      return null;
    }
  } catch (error) {
    console.error("Error syncing with Notion:", error);
    throw error;
  }
}

/**
 * A. 自動トリガー: ユーザー新規登録時に実行
 * v1の書き方を明示的に使用
 */
export const onUserCreated = functions.auth.user().onCreate(async (user) => {
  await syncUserWithNotion(user.email, user.uid);
});

/**
 * B. 手動リトライ用: アプリから呼び出し可能 (Callable Function)
 * v2の書き方を使用
 */
export const syncNotionUser = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const uid = request.auth.uid;
  const email = request.auth.token.email;

  const notionUserId = await syncUserWithNotion(email, uid);

  return {
    success: !!notionUserId,
    notionUserId: notionUserId,
  };
});

// ===========================================================================
// Notion Post 関連の Callable Functions
// ===========================================================================

/**
 * getPosts: Notion DBから投稿一覧を取得
 */
export const getPosts = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const client = getNotionClient();
  const databaseId = getNotionDatabaseId();

  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const response = await (client as any).databases.query({
      database_id: databaseId,
      sorts: [
        {
          timestamp: "created_time",
          direction: "descending",
        },
      ],
    });

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const posts: PostData[] = (response.results as any[])
      .filter((page): page is PageObjectResponse => "properties" in page)
      .map(parseNotionPageToPost);

    return { success: true, posts };
  } catch (error) {
    console.error("Error fetching posts from Notion:", error);
    throw new HttpsError("internal", "Failed to fetch posts from Notion.");
  }
});

/**
 * getPost: Notion から単一ページを取得
 */
export const getPost = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const pageId = request.data?.pageId;
  if (!pageId || typeof pageId !== "string") {
    throw new HttpsError("invalid-argument", "pageId is required.");
  }

  const client = getNotionClient();

  try {
    const page = await client.pages.retrieve({ page_id: pageId });

    if (!("properties" in page)) {
      throw new HttpsError("not-found", "Page not found or is not accessible.");
    }

    const post = parseNotionPageToPost(page as PageObjectResponse);

    return { success: true, post };
  } catch (error) {
    console.error("Error fetching post from Notion:", error);
    throw new HttpsError("internal", "Failed to fetch post from Notion.");
  }
});

/**
 * upsertPost: Notion にページを作成または更新
 */
export const upsertPost = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const client = getNotionClient();
  const databaseId = getNotionDatabaseId();

  const data = request.data as UpsertPostInput | undefined;
  if (!data || typeof data.title !== "string") {
    throw new HttpsError("invalid-argument", "title is required.");
  }

  const properties = buildNotionProperties(data);

  try {
    if (data.id && data.id.length > 0) {
      await client.pages.update({
        page_id: data.id,
        properties,
      });

      return { success: true, message: "Post updated successfully." };
    } else {
      const createParams: CreatePageParameters = {
        parent: { database_id: databaseId },
        properties,
      };

      const newPage = await client.pages.create(createParams);

      return {
        success: true,
        message: "Post created successfully.",
        pageId: newPage.id,
      };
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("Error upserting post to Notion:", error);
    console.error("Error details:", errorMessage);
    throw new HttpsError("internal", `Failed to upsert post to Notion: ${errorMessage}`);
  }
});
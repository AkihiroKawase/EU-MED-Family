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
  imagePath: string | null;
}

interface UpsertPostInput {
  id?: string;
  title: string;
  firstCheck: boolean;
  secondCheck: boolean;
  canvaUrl?: string | null;
  categories?: string[];
  status?: string | null;
  imagePath: string | null;
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

  const getRichTextPlain = (key: string): string | null => {
    const prop = props[key];
    if (!prop || prop.type !== "rich_text") return null;
    const arr = prop.rich_text ?? [];
    const text = arr.map((t: any) => t?.plain_text ?? "").join("");
    return text.length > 0 ? text : null;
  };

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
    imagePath: getRichTextPlain("ImagePath"),
  };
}

// ---------------------------------------------------------------------------
// ヘルパー関数: PostData を Notion プロパティに変換
// ---------------------------------------------------------------------------
function buildNotionProperties(post: UpsertPostInput) {
  const props: Record<string, any> = {
    "タイトル": {
      title: [{ text: { content: post.title } }],
    },
    "1st check": { checkbox: !!post.firstCheck },
    "Check ②": { checkbox: !!post.secondCheck },
  };

  // Canva URL（空なら送らない）
  if (post.canvaUrl != null && post.canvaUrl.trim() !== "") {
    props["Canva URL"] = { url: post.canvaUrl.trim() };
  }

  // ✅ Category（select）: 空なら送らない（nullでクリアしない）
  if (Array.isArray(post.categories) && post.categories.length > 0) {
    const name = String(post.categories[0]).trim();
    if (name !== "") {
      props["Category"] = { select: { name } };
    }
  }

  if (post.imagePath !== undefined) {
    props["ImagePath"] = {
      rich_text: post.imagePath
        ? [{ text: { content: post.imagePath } }]
        : [],
    };
  }

  // ✅ ステータス（status）: 空なら送らない（nullでクリアしない）
  if (post.status != null && String(post.status).trim() !== "") {
    props["ステータス"] = { status: { name: String(post.status).trim() } };
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
  
  // 「アプリユーザーDB」データベースID
  const appUserDatabaseId = "299aae8f429e8006aabae5f8c7899915";

  try {
    console.log(`Searching for user with email: ${email}`);

    // 「アプリユーザーDB」で「Email」プロパティが一致するエントリを検索
    const dbResponse = await client.databases.query({
      database_id: appUserDatabaseId,
      filter: {
        property: "Email",
        email: {
          equals: email,
        },
      },
    });

    console.log(`Found ${dbResponse.results.length} matching entries`);

    if (dbResponse.results.length > 0) {
      const matchedPage = dbResponse.results[0];

      // People型の「Person」プロパティからNotionユーザーIDを取得
      if (!("properties" in matchedPage)) {
        console.log("No properties found in matched page");
        return null;
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const props = matchedPage.properties as any;
      const personProp = props["Person"];

      if (!personProp || personProp.type !== "people" ||
          !personProp.people || personProp.people.length === 0) {
        console.log("No Person property found or it is empty");
        return null;
      }

      const notionUserId = personProp.people[0].id;

      // Firestoreを更新（notionUserIdフィールドにNotionユーザーIDを保存）
      await db.collection("users").doc(uid).set({
        notionUserId: notionUserId,
        lastSyncedAt: new Date(),
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
 * ヘルパー関数: メールアドレスからNotionユーザーIDを取得
 * @param {string} email - メールアドレス
 * @return {Promise<string | null>} Notion User ID または null
 */
async function getNotionUserIdByEmail(email: string): Promise<string | null> {
  const client = getNotionClient();
  const appUserDatabaseId = "299aae8f429e8006aabae5f8c7899915";

  try {
    const dbResponse = await client.databases.query({
      database_id: appUserDatabaseId,
      filter: {
        property: "Email",
        email: {
          equals: email,
        },
      },
    });

    if (dbResponse.results.length > 0) {
      const matchedPage = dbResponse.results[0];

      if (!("properties" in matchedPage)) {
        return null;
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const props = matchedPage.properties as any;
      const personProp = props["Person"];

      if (!personProp || personProp.type !== "people" ||
          !personProp.people || personProp.people.length === 0) {
        return null;
      }

      return personProp.people[0].id;
    }

    return null;
  } catch (error) {
    console.error("Error getting Notion user ID:", error);
    return null;
  }
}

/**
 * getMyPosts: ログインユーザーが著者の投稿一覧を取得
 */
export const getMyPosts = onCall(async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const email = request.auth.token.email;
  if (!email) {
    return {
      success: false,
      posts: [],
      message: "User has no email.",
    };
  }

  // メールアドレスからNotionユーザーIDを取得
  const notionUserId = await getNotionUserIdByEmail(email);
  if (!notionUserId) {
    return {
      success: false,
      posts: [],
      message: "Notion user not found for this email.",
    };
  }

  const client = getNotionClient();
  const databaseId = getNotionDatabaseId();

  try {
    // 著者がこのNotionユーザーIDを含み、ステータスが「完了」の記事を検索
    const response = await client.databases.query({
      database_id: databaseId,
      filter: {
        and: [
          {
            property: "著者",
            people: {
              contains: notionUserId,
            },
          },
          {
            property: "ステータス",
            status: {
              equals: "完了",
            },
          },
        ],
      },
      sorts: [
        {
          timestamp: "created_time",
          direction: "descending",
        },
      ],
    });

    const posts: PostData[] = (response.results as PageObjectResponse[])
      .filter((page): page is PageObjectResponse => "properties" in page)
      .map(parseNotionPageToPost);

    return {
      success: true,
      posts: posts,
    };
  } catch (error) {
    console.error("Error fetching my posts from Notion:", error);
    throw new HttpsError("internal", "Failed to fetch posts from Notion.");
  }
});

/**
 * getPostsByUserId: 指定したユーザーIDの投稿一覧を取得（ステータス「完了」のみ）
 */
export const getPostsByUserId = onCall(async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const targetUserId = request.data?.userId;
  if (!targetUserId || typeof targetUserId !== "string") {
    throw new HttpsError("invalid-argument", "userId is required.");
  }

  try {
    // FirestoreからユーザーのnotionUserIdを取得
    const userDoc = await db.collection("users").doc(targetUserId).get();
    
    if (!userDoc.exists) {
      return {
        success: false,
        posts: [],
        message: "User not found.",
      };
    }

    const userData = userDoc.data();
    const notionUserId = userData?.notionUserId;

    if (!notionUserId) {
      return {
        success: false,
        posts: [],
        message: "Notion user not linked.",
      };
    }

    const client = getNotionClient();
    const databaseId = getNotionDatabaseId();

    // 著者がこのNotionユーザーIDを含み、ステータスが「完了」の記事を検索
    const response = await client.databases.query({
      database_id: databaseId,
      filter: {
        and: [
          {
            property: "著者",
            people: {
              contains: notionUserId,
            },
          },
          {
            property: "ステータス",
            status: {
              equals: "完了",
            },
          },
        ],
      },
      sorts: [
        {
          timestamp: "created_time",
          direction: "descending",
        },
      ],
    });

    const posts: PostData[] = (response.results as PageObjectResponse[])
      .filter((page): page is PageObjectResponse => "properties" in page)
      .map(parseNotionPageToPost);

    return {
      success: true,
      posts: posts,
    };
  } catch (error) {
    console.error("Error fetching posts by user ID:", error);
    throw new HttpsError("internal", "Failed to fetch posts from Notion.");
  }
});

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
  if (!data || typeof data.title !== "string" || data.title.trim() === "") {
    throw new HttpsError("invalid-argument", "title is required.");
  }

  const properties = buildNotionProperties(data);

  // ✅ デバッグしやすいログ（Functionsログで確認）
  console.log("upsertPost input:", JSON.stringify(data));
  console.log("notion properties:", JSON.stringify(properties));

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
    throw new HttpsError("internal", `Failed to upsert post to Notion: ${errorMessage}`);
  }
});
import * as functions from "firebase-functions/v1"; // v1を明示的に指定してエラーを回避
import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {Client} from "@notionhq/client";
import {
  PageObjectResponse,
  CreatePageParameters,
} from "@notionhq/client/build/src/api-endpoints";

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
  if (cachedNotionClient) {
    return cachedNotionClient;
  }

  const apiKey = process.env.NOTION_API_KEY || "";

  if (!apiKey) {
    throw new HttpsError(
      "failed-precondition",
      "NOTION_API_KEY is not configured."
    );
  }

  cachedNotionClient = new Client({auth: apiKey});
  return cachedNotionClient;
}

/**
 * Notion Database ID を取得する（遅延取得）
 */
function getNotionDatabaseId(): string {
  const databaseId = process.env.NOTION_DATABASE_ID || "";

  if (!databaseId) {
    throw new HttpsError(
      "failed-precondition",
      "NOTION_DATABASE_ID is not configured."
    );
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
  categories: string[];
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

  // タイトル取得
  const getTitle = (key: string): string => {
    const prop = props[key];
    if (!prop || prop.type !== "title") return "";
    const titleList = prop.title || [];
    if (titleList.length === 0) return "";
    return titleList[0]?.plain_text || "";
  };

  // チェックボックス取得
  const getCheckbox = (key: string): boolean => {
    const prop = props[key];
    if (!prop || prop.type !== "checkbox") return false;
    return prop.checkbox ?? false;
  };

  // URL取得
  const getUrl = (key: string): string | null => {
    const prop = props[key];
    if (!prop || prop.type !== "url") return null;
    return prop.url;
  };

  // マルチセレクト取得
  const getMultiSelectNames = (key: string): string[] => {
    const prop = props[key];
    if (!prop || prop.type !== "multi_select") return [];
    const ms = prop.multi_select || [];
    return ms
      .map((e: {name?: string}) => e.name || "")
      .filter((name: string) => name.length > 0);
  };

  // ステータス取得
  const getStatusName = (key: string): string | null => {
    const prop = props[key];
    if (!prop || prop.type !== "status") return null;
    const status = prop.status;
    if (!status) return null;
    return status.name || null;
  };

  return {
    id: page.id,
    title: getTitle("タイトル"),
    firstCheck: getCheckbox("1st check"),
    secondCheck: getCheckbox("Check ②"),
    canvaUrl: getUrl("Canva URL"),
    categories: getMultiSelectNames("Category"),
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
    // タイトル
    "タイトル": {
      title: [
        {
          text: {content: post.title},
        },
      ],
    },
    // 1st check
    "1st check": {
      checkbox: post.firstCheck,
    },
    // Check ②
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

  // Category (select型: 配列の最初の要素のみを使用)
  if (post.categories !== undefined && post.categories.length > 0) {
    props["Category"] = {
      select: {name: post.categories[0]},
    };
  }

  // ステータス
  if (post.status !== undefined) {
    props["ステータス"] = {
      status: post.status ? {name: post.status} : null,
    };
  }

  return props;
}

/**
 * 共通ロジック: メールアドレスからNotionユーザーIDを取得してFirestoreを更新する
 * 「アプリユーザーDB」の「Email」プロパティで検索し、「Person」プロパティからNotionユーザーIDを取得
 * @param {string | undefined} email - ユーザーのメールアドレス
 * @param {string} uid - Firebase AuthのUser ID
 * @return {Promise<string | null>} Notion User ID または null
 */
async function syncUserWithNotion(email: string | undefined, uid: string) {
  if (!email) {
    console.log(`User ${uid} has no email. Skipping Notion sync.`);
    return null;
  }

  // 遅延初期化でクライアントを取得
  const client = getNotionClient();

  // 「アプリユーザーDB」データベースID
  const appUserDatabaseId = "299aae8f429e8006aabae5f8c7899915";

  try {
    console.log(`=== DEBUG: syncUserWithNotion started ===`);
    console.log(`DEBUG: Searching for user with email: ${email}`);
    console.log(`DEBUG: Using database ID: ${appUserDatabaseId}`);

    // まず、データベースの全エントリを取得してログに出力（デバッグ用）
    const allEntriesResponse = await client.databases.query({
      database_id: appUserDatabaseId,
      page_size: 10,
    });
    console.log(`DEBUG: Total entries in database: ${allEntriesResponse.results.length}`);
    
    // 各エントリのEmailプロパティをログに出力
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    allEntriesResponse.results.forEach((entry: any, index: number) => {
      if ("properties" in entry) {
        const emailProp = entry.properties["Email"];
        console.log(`DEBUG: Entry ${index + 1} Email property:`, JSON.stringify(emailProp));
      }
    });

    // 「アプリユーザーDB」で「Email」プロパティが一致するエントリを検索
    console.log(`DEBUG: Now querying with filter for email: ${email}`);
    const dbResponse = await client.databases.query({
      database_id: appUserDatabaseId,
      filter: {
        property: "Email",
        email: {
          equals: email,
        },
      },
    });

    console.log(`DEBUG: Found ${dbResponse.results.length} matching entries`);

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
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const uid = request.auth.uid;
  const email = request.auth.token.email;

  const notionUserId = await syncUserWithNotion(email, uid);

  // フロントエンドへの戻り値
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
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  // 遅延初期化でクライアントとDB IDを取得
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

    return {
      success: true,
      posts: posts,
    };
  } catch (error) {
    console.error("Error fetching posts from Notion:", error);
    throw new HttpsError("internal", "Failed to fetch posts from Notion.");
  }
});

/**
 * getPost: Notion から単一ページを取得
 */
export const getPost = onCall(async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const pageId = request.data?.pageId;
  if (!pageId || typeof pageId !== "string") {
    throw new HttpsError("invalid-argument", "pageId is required.");
  }

  // 遅延初期化でクライアントを取得
  const client = getNotionClient();

  try {
    const page = await client.pages.retrieve({page_id: pageId});

    if (!("properties" in page)) {
      throw new HttpsError("not-found", "Page not found or is not accessible.");
    }

    const post = parseNotionPageToPost(page as PageObjectResponse);

    return {
      success: true,
      post: post,
    };
  } catch (error) {
    console.error("Error fetching post from Notion:", error);
    throw new HttpsError("internal", "Failed to fetch post from Notion.");
  }
});

/**
 * upsertPost: Notion にページを作成または更新
 */
export const upsertPost = onCall(async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  // 遅延初期化でクライアントとDB IDを取得
  const client = getNotionClient();
  const databaseId = getNotionDatabaseId();

  const data = request.data as UpsertPostInput | undefined;
  if (!data || typeof data.title !== "string") {
    throw new HttpsError("invalid-argument", "title is required.");
  }

  const properties = buildNotionProperties(data);

  try {
    if (data.id && data.id.length > 0) {
      // 更新
      await client.pages.update({
        page_id: data.id,
        properties: properties,
      });

      return {
        success: true,
        message: "Post updated successfully.",
      };
    } else {
      // 新規作成
      const createParams: CreatePageParameters = {
        parent: {database_id: databaseId},
        properties: properties,
      };

      const newPage = await client.pages.create(createParams);

      return {
        success: true,
        message: "Post created successfully.",
        pageId: newPage.id,
      };
    }
  } catch (error) {
    // Notion API エラーの詳細をログに出力
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("Error upserting post to Notion:", error);
    console.error("Error details:", errorMessage);
    throw new HttpsError("internal", `Failed to upsert post to Notion: ${errorMessage}`);
  }
});

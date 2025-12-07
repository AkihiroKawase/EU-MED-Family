import * as functions from "firebase-functions/v1"; // v1を明示的に指定してエラーを回避
import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {Client} from "@notionhq/client";

// Firebase Admin SDKの初期化
admin.initializeApp();
const db = admin.firestore();

// Notion APIキーの取得
const notion = new Client({auth: process.env.NOTION_API_KEY});

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

  try {
    // 1. Notionの全ユーザーを取得
    const response = await notion.users.list({});
    const notionUsers = response.results;

    // デバッグ: Botが認識している全Notionユーザーを出力
    console.log(`=== DEBUG: Notion API returned ${notionUsers.length} users ===`);
    notionUsers.forEach((user, index) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const u = user as any;
      console.log(`[${index}] id: ${u.id}, type: ${u.type}, name: ${u.name}, email: ${u.person?.email ?? "N/A"}`);
    });
    console.log(`=== DEBUG: Searching for email: ${email} ===`);

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

      console.log(`Synced ${email} to Notion ID: ${targetNotionUser.id}`);
      return targetNotionUser.id;
    } else {
      console.log(`No matching Notion user found for email: ${email}`);
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

// lib/services/notion_post_service.dart
import 'package:cloud_functions/cloud_functions.dart';

import '../models/post.dart';

/// Firebase Cloud Functions 経由で Notion DB とやり取りするサービス
///
/// セキュリティ上の理由から、Notion API キーはサーバーサイド（Cloud Functions）
/// でのみ扱い、クライアント側には公開しない設計になっています。
class NotionPostService {
  final FirebaseFunctions _functions;

  NotionPostService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  // ---------------------------------------------------------------------------
  // 一覧取得
  // ---------------------------------------------------------------------------

  /// Notion DB から投稿一覧を取得
  Future<List<Post>> fetchPosts() async {
    try {
      final callable = _functions.httpsCallable('getPosts');
      final result = await callable.call();

      // Map<Object?, Object?> から Map<String, dynamic> への安全な変換
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        throw Exception('Failed to fetch posts: success=false');
      }

      final postsJson = List<dynamic>.from(data['posts'] as List);
      return postsJson
          .map((json) => Post.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(
        'Cloud Function error (${e.code}): ${e.message ?? "Unknown error"}',
      );
    } catch (e) {
      throw Exception('Failed to fetch posts: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 単一取得
  // ---------------------------------------------------------------------------

  /// 単一のページ(Post) を取得
  Future<Post> fetchPost(String pageId) async {
    try {
      final callable = _functions.httpsCallable('getPost');
      final result = await callable.call({'pageId': pageId});

      // Map<Object?, Object?> から Map<String, dynamic> への安全な変換
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        throw Exception('Failed to fetch post: success=false');
      }

      final postJson = Map<String, dynamic>.from(data['post'] as Map);
      return Post.fromJson(postJson);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(
        'Cloud Function error (${e.code}): ${e.message ?? "Unknown error"}',
      );
    } catch (e) {
      throw Exception('Failed to fetch post: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 作成 / 更新（upsert）
  // ---------------------------------------------------------------------------

  /// Post を作成または更新する。
  ///
  /// - [isUpdate] が true かつ post.id が空でない → 更新
  /// - それ以外 → 新規作成
  Future<void> upsertPost(
    Post post, {
    required bool isUpdate,
  }) async {
    try {
      final callable = _functions.httpsCallable('upsertPost');

      final payload = <String, dynamic>{
        'title': post.title,
        'firstCheck': post.firstCheck,
        'secondCheck': post.secondCheck,
        'canvaUrl': post.canvaUrl,
        'categories': post.categories,
        'status': post.status,
        'imagePath': post.imagePath,
      };

      // 更新時のみ id を含める
      if (isUpdate && post.id.isNotEmpty) {
        payload['id'] = post.id;
      }

      final result = await callable.call(payload);
      // Map<Object?, Object?> から Map<String, dynamic> への安全な変換
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        throw Exception('Failed to upsert post: success=false');
      }
    } on FirebaseFunctionsException catch (e) {
      throw Exception(
        'Cloud Function error (${e.code}): ${e.message ?? "Unknown error"}',
      );
    } catch (e) {
      throw Exception('Failed to upsert post: $e');
    }
  }
}

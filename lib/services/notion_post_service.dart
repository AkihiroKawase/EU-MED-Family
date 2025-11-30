// lib/services/notion_post_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env.dart';
import '../models/post.dart';

/// Notion の DB（NOTION_DATABASE_ID）とやり取りするサービス
class NotionPostService {
  static const String _baseUrl = 'https://api.notion.com/v1';
  static const String _notionVersion = '2022-06-28';

  final String _apiKey;
  final String _databaseId;

  NotionPostService({
    String? apiKey,
    String? databaseId,
  })  : _apiKey = apiKey ?? notionApiKey,
        _databaseId = databaseId ?? notionDatabaseId;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiKey',
        'Notion-Version': _notionVersion,
        'Content-Type': 'application/json',
      };

  // ---------------------------------------------------------------------------
  // 一覧取得
  // ---------------------------------------------------------------------------

  Future<List<Post>> fetchPosts() async {
    if (_apiKey.isEmpty || _databaseId.isEmpty) {
      throw Exception(
          'Notion API key or database ID is empty. dart-define を確認してください。');
    }

    final uri = Uri.parse('$_baseUrl/databases/$_databaseId/query');

    final body = jsonEncode({
      'sorts': [
        {
          'timestamp': 'created_time',
          'direction': 'descending',
        }
      ],
    });

    final res = await http.post(
      uri,
      headers: _headers,
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception(
          'Failed to fetch posts from Notion: ${res.statusCode} ${res.body}');
    }

    final Map<String, dynamic> json = jsonDecode(res.body);
    final List<dynamic> results = json['results'] as List<dynamic>;

    return results
        .map((pageJson) =>
            Post.fromNotionPage(pageJson as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 作成 / 更新（upsert）
  // ---------------------------------------------------------------------------

  /// Post を作成または更新する。
  ///
  /// - [isUpdate] が true かつ post.id が空でない → PATCH /pages/{id}
  /// - それ以外 → POST /pages
  Future<void> upsertPost(
    Post post, {
    required bool isUpdate,
  }) async {
    if (_apiKey.isEmpty || _databaseId.isEmpty) {
      throw Exception(
          'Notion API key or database ID is empty. dart-define を確認してください。');
    }

    final properties = _buildProperties(post);

    if (isUpdate && post.id.isNotEmpty) {
      // 更新
      final uri = Uri.parse('$_baseUrl/pages/${post.id}');
      final body = jsonEncode({
        'properties': properties,
      });

      final res = await http.patch(
        uri,
        headers: _headers,
        body: body,
      );

      if (res.statusCode != 200) {
        throw Exception(
            'Failed to update post in Notion: ${res.statusCode} ${res.body}');
      }
    } else {
      // 新規作成
      final uri = Uri.parse('$_baseUrl/pages');
      final body = jsonEncode({
        'parent': {'database_id': _databaseId},
        'properties': properties,
      });

      final res = await http.post(
        uri,
        headers: _headers,
        body: body,
      );

      if (res.statusCode != 200) {
        throw Exception(
            'Failed to create post in Notion: ${res.statusCode} ${res.body}');
      }
    }
  }

    /// 単一のページ(Post) を取得
  Future<Post> fetchPost(String pageId) async {
    final uri = Uri.parse('$_baseUrl/pages/$pageId');

    final res = await http.get(
      uri,
      headers: _headers,
    );

    if (res.statusCode != 200) {
      throw Exception(
          'Failed to fetch post from Notion: ${res.statusCode} ${res.body}');
    }

    final Map<String, dynamic> json = jsonDecode(res.body);

    return Post.fromNotionPage(json);
  }

  // ---------------------------------------------------------------------------
  // Notion プロパティのマッピング
  // ---------------------------------------------------------------------------

  /// Post → Notion properties JSON
  ///
  /// Notion DB 側のプロパティ名と 1:1 で対応させています。
  ///
  /// - タイトル (title)
  /// - 1st check (checkbox)
  /// - Canva URL (url)
  /// - Category (multi_select)
  /// - Check ② (checkbox)
  /// - ステータス (status)
  Map<String, dynamic> _buildProperties(Post post) {
    final Map<String, dynamic> props = {
      // タイトル
      'タイトル': {
        'title': [
          {
            'text': {'content': post.title}
          }
        ],
      },

      // 1st check
      '1st check': {
        'checkbox': post.firstCheck,
      },

      // Check ②
      'Check ②': {
        'checkbox': post.secondCheck,
      },
    };

    // Canva URL（空文字なら null 扱い）
    if (post.canvaUrl != null && post.canvaUrl!.isNotEmpty) {
      props['Canva URL'] = {
        'url': post.canvaUrl,
      };
    } else {
      props['Canva URL'] = {
        'url': null,
      };
    }

    // Category（multi_select）
    if (post.categories.isNotEmpty) {
      props['Category'] = {
        'multi_select': post.categories
            .map((name) => {
                  'name': name,
                })
            .toList(),
      };
    } else {
      props['Category'] = {
        'multi_select': <dynamic>[],
      };
    }

    // ステータス（status）
    if (post.status != null && post.status!.isNotEmpty) {
      props['ステータス'] = {
        'status': {
          'name': post.status,
        },
      };
    } else {
      // ステータスをリセットしたい場合は null にする
      props['ステータス'] = {
        'status': null,
      };
    }

    // 今回は authors / secondCheckAssignees / fileUrls は編集しない前提。
    // もし編集したくなったら、ここに people / files のマッピングを追加。

    return props;
  }
}
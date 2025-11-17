// lib/services/notion_post_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/post.dart';

class NotionPostService {
  // TODO: あとで .env や dart-define で秘匿する
  static const String _notionApiBaseUrl = 'https://api.notion.com/v1';
  static const String _notionApiKey = 'YOUR_NOTION_SECRET'; // secret_...
  static const String _databaseId = 'YOUR_DATABASE_ID';

  static const Map<String, String> _headers = {
    'Authorization': 'Bearer $_notionApiKey',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json',
  };

  /// 投稿一覧取得
  Future<List<Post>> fetchPosts() async {
    final url = Uri.parse('$_notionApiBaseUrl/databases/$_databaseId/query');

    final res = await http.post(url, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch posts from Notion: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>;

    return results.map((page) => _pageToPost(page)).toList();
  }

  /// 1件取得（詳細用）
  Future<Post> fetchPost(String pageId) async {
    final url = Uri.parse('$_notionApiBaseUrl/pages/$pageId');

    final res = await http.get(url, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch post: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _pageToPost(data);
  }

  /// 新規作成 or 更新
  Future<void> upsertPost(Post post, {bool isUpdate = false}) async {
    final body = {
      'parent': {'database_id': _databaseId},
      'properties': {
        'Title': {
          'title': [
            {'text': {'content': post.title}}
          ]
        },
        'PDF': {'url': post.pdfUrl},
        'Comment': {
          'rich_text': [
            {'text': {'content': post.comment}}
          ]
        },
        'Tags': {
          'multi_select': post.hashtags
              .map((tag) => {
                    'name': tag,
                  })
              .toList()
        },
      },
    };

    http.Response res;

    if (isUpdate) {
      final url = Uri.parse('$_notionApiBaseUrl/pages/${post.id}');
      res = await http.patch(url, headers: _headers, body: jsonEncode(body));
    } else {
      final url = Uri.parse('$_notionApiBaseUrl/pages');
      res = await http.post(url, headers: _headers, body: jsonEncode(body));
    }

    if (res.statusCode != 200) {
      throw Exception('Failed to upsert post: ${res.body}');
    }
  }

  /// Notionのpage JSON → Postモデル変換
  Post _pageToPost(Map<String, dynamic> page) {
    final properties = page['properties'] as Map<String, dynamic>;

    final titleProp = properties['Title']?['title'] as List<dynamic>? ?? [];
    final titleText =
        titleProp.isNotEmpty ? (titleProp.first['plain_text'] ?? '') : '';

    final pdfUrl = properties['PDF']?['url'] as String? ?? '';

    final commentProp =
        properties['Comment']?['rich_text'] as List<dynamic>? ?? [];
    final commentText = commentProp.isNotEmpty
        ? (commentProp.first['plain_text'] as String? ?? '')
        : '';

    final tagsProp =
        properties['Tags']?['multi_select'] as List<dynamic>? ?? [];
    final tags = tagsProp
        .map((e) => e['name'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    return Post(
      id: page['id'] as String,
      title: titleText,
      pdfUrl: pdfUrl,
      comment: commentText,
      hashtags: tags,
    );
  }
}
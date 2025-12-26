// lib/models/post.dart

/// Notion の DB（タイトル / 1st check / Canva URL / Category /
/// Check ② / Check ② 担当 / ステータス / ファイル&メディア / 著者）
/// と 1 対 1 で対応するモデルクラス。
class Post {
  /// Notion ページ ID
  final String id;

  /// タイトル（Notion プロパティ名: タイトル / type: title）
  final String title;

  /// 1st check（checkbox）
  final bool firstCheck;

  /// Canva URL（url）
  final String? canvaUrl;

  /// Category（select or multi_select）
  /// ※ DB が select の場合は最大1件、multi_select なら複数入る
  final List<String> categories;

  /// Check ②（checkbox）
  final bool secondCheck;

  /// Check ② 担当（people）
  final List<String> secondCheckAssignees;

  /// ステータス（status / select）
  final String? status;

  /// ファイル&メディア（files）→ URL のリスト
  final List<String> fileUrls;

  /// 著者（people）
  final List<String> authors;

  /// Notion の created_time / last_edited_time
  final DateTime? createdTime;
  final DateTime? lastEditedTime;

  Post({
    required this.id,
    required this.title,
    required this.firstCheck,
    this.canvaUrl,
    required this.categories,
    required this.secondCheck,
    this.secondCheckAssignees = const [],
    this.status,
    this.fileUrls = const [],
    this.authors = const [],
    this.createdTime,
    this.lastEditedTime,
  });

  /// Category の先頭だけ使いたい場合
  String? get firstCategory => categories.isNotEmpty ? categories.first : null;

  /// 著者の先頭だけ使いたい場合
  String? get firstAuthor => authors.isNotEmpty ? authors.first : null;

  // ---------------------------------------------------------------------------
  // Cloud Functions から返却される整形済み JSON を Post に変換
  // ---------------------------------------------------------------------------
  factory Post.fromJson(Map<String, dynamic> json) {
    List<String> _toStringList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      return <String>[];
    }

    return Post(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      firstCheck: json['firstCheck'] as bool? ?? false,
      secondCheck: json['secondCheck'] as bool? ?? false,
      canvaUrl: json['canvaUrl']?.toString(),
      categories: _toStringList(json['categories']),
      secondCheckAssignees: _toStringList(json['secondCheckAssignees']),
      status: json['status']?.toString(),
      fileUrls: _toStringList(json['fileUrls']),
      authors: _toStringList(json['authors']),
      createdTime: json['createdTime'] != null
          ? DateTime.tryParse(json['createdTime'].toString())
          : null,
      lastEditedTime: json['lastEditedTime'] != null
          ? DateTime.tryParse(json['lastEditedTime'].toString())
          : null,
    );
  }

  /// Post を JSON (Map) に変換（Cloud Functions への送信用）
  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'title': title,
      'firstCheck': firstCheck,
      'secondCheck': secondCheck,
      'canvaUrl': canvaUrl,
      'categories': categories,
      'secondCheckAssignees': secondCheckAssignees,
      'status': status,
      'fileUrls': fileUrls,
      'authors': authors,
      'createdTime': createdTime?.toIso8601String(),
      'lastEditedTime': lastEditedTime?.toIso8601String(),
    };
  }

  // ---------------------------------------------------------------------------
  // Notion の「ページ JSON」から Post へ変換（直叩き/サーバ側で使う用）
  // ---------------------------------------------------------------------------
  factory Post.fromNotionPage(Map<String, dynamic> page) {
    final props = (page['properties'] as Map?)?.cast<String, dynamic>() ?? {};

    String _getTitle(String key) {
      final prop = props[key];
      if (prop == null) return '';
      final List<dynamic> titleList = (prop['title'] as List?) ?? [];
      if (titleList.isEmpty) return '';
      return titleList.first['plain_text']?.toString() ?? '';
    }

    bool _getCheckbox(String key) {
      final prop = props[key];
      if (prop == null) return false;
      return (prop['checkbox'] as bool?) ?? false;
    }

    String? _getUrl(String key) {
      final prop = props[key];
      if (prop == null) return null;
      return prop['url']?.toString();
    }

    // ✅ multi_select 用
    List<String> _getMultiSelectNames(String key) {
      final prop = props[key];
      if (prop == null) return <String>[];
      final List<dynamic> ms = (prop['multi_select'] as List?) ?? [];
      return ms
          .map((e) => (e as Map)['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    }

    // ✅ select 用（今回 Category は select 想定）
    String? _getSelectName(String key) {
      final prop = props[key];
      if (prop == null) return null;
      final sel = prop['select'];
      if (sel == null) return null;
      return (sel['name'])?.toString();
    }

    // status
    String? _getStatusName(String key) {
      final prop = props[key];
      if (prop == null) return null;
      final status = prop['status'];
      if (status == null) return null;
      return status['name']?.toString();
    }

    List<String> _getFileUrls(String key) {
      final prop = props[key];
      if (prop == null) return <String>[];
      final List<dynamic> files = (prop['files'] as List?) ?? [];
      return files
          .map((f) {
            final m = (f as Map).cast<String, dynamic>();
            final fileObj = m['file'] ?? m['external'];
            if (fileObj == null) return '';
            return (fileObj['url'])?.toString() ?? '';
          })
          .where((url) => url.isNotEmpty)
          .toList();
    }

    List<String> _getPeopleNames(String key) {
      final prop = props[key];
      if (prop == null) return <String>[];
      final List<dynamic> people = (prop['people'] as List?) ?? [];
      return people
          .map((p) => (p as Map)['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    }

    DateTime? _parseDateTimeTopLevel(String key) {
      final v = page[key]?.toString();
      if (v == null) return null;
      return DateTime.tryParse(v);
    }

    // ✅ Category は select 想定なので select を優先
    final categorySelect = _getSelectName('Category');
    final categories = (categorySelect != null && categorySelect.isNotEmpty)
        ? <String>[categorySelect]
        : _getMultiSelectNames('Category'); // multi_select の DB でも動く保険

    return Post(
      id: page['id']?.toString() ?? '',
      title: _getTitle('タイトル'),
      firstCheck: _getCheckbox('1st check'),
      canvaUrl: _getUrl('Canva URL'),
      categories: categories,
      secondCheck: _getCheckbox('Check ②'),
      secondCheckAssignees: _getPeopleNames('Check ② 担当'),
      status: _getStatusName('ステータス'),
      fileUrls: _getFileUrls('ファイル&メディア'),
      authors: _getPeopleNames('著者'),
      createdTime: _parseDateTimeTopLevel('created_time'),
      lastEditedTime: _parseDateTimeTopLevel('last_edited_time'),
    );
  }
}